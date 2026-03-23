// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useCameraDevices } from "./useCameraDevices";
import { useMicrophoneDevices } from "./useMicrophoneDevices";
import {
	resolveSelectedDeviceId,
	shouldRequestDeviceAccess,
} from "./usePermissionAwareMediaDevices";

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

type DeviceKind = "audioinput" | "videoinput";

type HookHarnessResult<T> = {
	getCurrent: () => T;
	unmount: () => Promise<void>;
};

function createDevice(
	kind: DeviceKind,
	deviceId: string,
	label: string,
	groupId: string = `${deviceId}-group`,
): MediaDeviceInfo {
	return {
		deviceId,
		groupId,
		kind,
		label,
		toJSON: () => ({ deviceId, groupId, kind, label }),
	} as MediaDeviceInfo;
}

function createMediaDevicesMock(
	enumerateResponses: MediaDeviceInfo[][],
	getUserMediaImpl: MediaDevices["getUserMedia"] = vi.fn(async () => ({
		getTracks: () => [{ stop: vi.fn() }],
	})) as MediaDevices["getUserMedia"],
) {
	let enumerateCall = 0;
	const deviceChangeListeners = new Set<() => void>();

	const mediaDevices = {
		enumerateDevices: vi.fn(async () => {
			const responseIndex = Math.min(enumerateCall, enumerateResponses.length - 1);
			enumerateCall += 1;
			return enumerateResponses[responseIndex];
		}),
		getUserMedia: vi.fn(getUserMediaImpl),
		addEventListener: vi.fn((event: string, listener: EventListenerOrEventListenerObject) => {
			if (event === "devicechange" && typeof listener === "function") {
				deviceChangeListeners.add(listener as () => void);
			}
		}),
		removeEventListener: vi.fn((event: string, listener: EventListenerOrEventListenerObject) => {
			if (event === "devicechange" && typeof listener === "function") {
				deviceChangeListeners.delete(listener as () => void);
			}
		}),
		emitDeviceChange: async () => {
			await act(async () => {
				deviceChangeListeners.forEach((listener) => listener());
			});
			await flushEffects();
		},
	};

	Object.defineProperty(navigator, "mediaDevices", {
		configurable: true,
		value: mediaDevices,
	});

	return mediaDevices;
}

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function mountHook<T>(renderHook: () => T): Promise<HookHarnessResult<T>> {
	const container = document.createElement("div");
	const root: Root = createRoot(container);
	let currentValue!: T;

	function Harness() {
		currentValue = renderHook();
		return null;
	}

	await act(async () => {
		root.render(<Harness />);
	});
	await flushEffects();

	return {
		getCurrent: () => currentValue,
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
		},
	};
}

afterEach(() => {
	vi.restoreAllMocks();
});

describe("permission-aware media device hooks", () => {
	it("loads microphone devices immediately when permission is already available", async () => {
		const mediaDevices = createMediaDevicesMock([
			[
				createDevice("audioinput", "default", "Default Microphone"),
				createDevice("audioinput", "usb-mic", "USB Microphone"),
			],
		]);

		const hook = await mountHook(() => useMicrophoneDevices(true));

		expect(hook.getCurrent().devices).toEqual([
			{ deviceId: "default", groupId: "default-group", label: "Default Microphone" },
			{ deviceId: "usb-mic", groupId: "usb-mic-group", label: "USB Microphone" },
		]);
		expect(hook.getCurrent().isRequestingAccess).toBe(false);
		expect(hook.getCurrent().permissionDenied).toBe(false);
		expect(mediaDevices.getUserMedia).not.toHaveBeenCalled();

		await hook.unmount();
	});

	it("requests temporary microphone access when the initial list looks incomplete", async () => {
		const stop = vi.fn();
		let resolveAccess: ((stream: MediaStream) => void) | undefined;

		const mediaDevices = createMediaDevicesMock(
			[
				[createDevice("audioinput", "default", "")],
				[
					createDevice("audioinput", "default", "Default Microphone"),
					createDevice("audioinput", "usb-mic", "USB Microphone"),
				],
			],
			vi.fn(
				() =>
					new Promise<MediaStream>((resolve) => {
						resolveAccess = resolve;
					}),
			) as MediaDevices["getUserMedia"],
		);

		const hook = await mountHook(() => useMicrophoneDevices(true));

		expect(hook.getCurrent().isRequestingAccess).toBe(true);
		expect(mediaDevices.getUserMedia).toHaveBeenCalledTimes(1);

		resolveAccess?.({
			getTracks: () => [{ stop }],
		} as MediaStream);

		await flushEffects();
		await flushEffects();

		expect(hook.getCurrent().isRequestingAccess).toBe(false);
		expect(hook.getCurrent().permissionDenied).toBe(false);
		expect(hook.getCurrent().devices.map((device) => device.deviceId)).toEqual([
			"default",
			"usb-mic",
		]);
		expect(stop).toHaveBeenCalledTimes(1);

		await hook.unmount();
	});

	it("keeps the fallback microphone state when access is denied", async () => {
		createMediaDevicesMock(
			[[createDevice("audioinput", "default", "")], [createDevice("audioinput", "default", "")]],
			vi.fn(async () => {
				throw new DOMException("denied", "NotAllowedError");
			}) as MediaDevices["getUserMedia"],
		);

		const hook = await mountHook(() => useMicrophoneDevices(true));

		expect(hook.getCurrent().permissionDenied).toBe(true);
		expect(hook.getCurrent().error).toContain("Microphone access was denied");
		expect(hook.getCurrent().devices).toEqual([
			{ deviceId: "default", groupId: "default-group", label: "Microphone default" },
		]);

		await hook.unmount();
	});

	it("refreshes the camera list on device changes and preserves the current selection", async () => {
		const mediaDevices = createMediaDevicesMock([
			[
				createDevice("videoinput", "cam-1", "Facecam One"),
				createDevice("videoinput", "cam-2", "Facecam Two"),
			],
			[
				createDevice("videoinput", "cam-1", "Facecam One"),
				createDevice("videoinput", "cam-2", "Facecam Two"),
				createDevice("videoinput", "cam-3", "Facecam Three"),
			],
		]);

		const hook = await mountHook(() => useCameraDevices(true));

		expect(hook.getCurrent().selectedDeviceId).toBe("cam-1");
		expect(hook.getCurrent().devices.map((device) => device.deviceId)).toEqual(["cam-1", "cam-2"]);

		await mediaDevices.emitDeviceChange();

		expect(hook.getCurrent().devices.map((device) => device.deviceId)).toEqual([
			"cam-1",
			"cam-2",
			"cam-3",
		]);
		expect(hook.getCurrent().selectedDeviceId).toBe("cam-1");

		await hook.unmount();
	});
});

describe("permission-aware device utilities", () => {
	it("flags incomplete device lists for a permission prompt", () => {
		const incompleteDevices = [createDevice("audioinput", "default", "")];
		const fullDevices = [
			createDevice("audioinput", "default", "Default Microphone"),
			createDevice("audioinput", "usb-mic", "USB Microphone"),
		];

		expect(shouldRequestDeviceAccess(incompleteDevices)).toBe(true);
		expect(shouldRequestDeviceAccess(fullDevices)).toBe(false);
	});

	it("falls back to the default selection when a chosen device disappears", () => {
		const devices = [{ deviceId: "cam-2", groupId: "cam-2-group", label: "Facecam Two" }];

		expect(resolveSelectedDeviceId("cam-1", devices, false)).toBe("default");
		expect(resolveSelectedDeviceId("default", devices, true)).toBe("cam-2");
	});
});
