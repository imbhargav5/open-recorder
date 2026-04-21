// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
	enumeratePermissionAwareDevices,
	filterDevicesByKind,
	mapSelectableDevice,
	resolveSelectedDeviceId,
	shouldRequestDeviceAccess,
	usePermissionAwareMediaDevices,
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

// ── filterDevicesByKind ───────────────────────────────────────────────────────

describe("filterDevicesByKind", () => {
	it("returns only audioinput devices from a mixed list", () => {
		const devices = [
			createDevice("audioinput", "mic-1", "Microphone"),
			createDevice("videoinput", "cam-1", "Camera"),
			createDevice("audioinput", "mic-2", "Headset"),
		];
		const result = filterDevicesByKind(devices, "audioinput");
		expect(result).toHaveLength(2);
		expect(result.every((d) => d.kind === "audioinput")).toBe(true);
	});

	it("returns only videoinput devices from a mixed list", () => {
		const devices = [
			createDevice("audioinput", "mic-1", "Microphone"),
			createDevice("videoinput", "cam-1", "Camera"),
			createDevice("videoinput", "cam-2", "Webcam"),
		];
		const result = filterDevicesByKind(devices, "videoinput");
		expect(result).toHaveLength(2);
		expect(result.every((d) => d.kind === "videoinput")).toBe(true);
	});

	it("returns empty array when no devices match the requested kind", () => {
		const devices = [createDevice("audioinput", "mic-1", "Microphone")];
		expect(filterDevicesByKind(devices, "videoinput")).toHaveLength(0);
	});

	it("returns empty array when the input list is empty", () => {
		expect(filterDevicesByKind([], "audioinput")).toHaveLength(0);
	});
});

// ── shouldRequestDeviceAccess ────────────────────────────────────────────────

describe("shouldRequestDeviceAccess", () => {
	it("returns true for an empty device list", () => {
		expect(shouldRequestDeviceAccess([])).toBe(true);
	});

	it("returns true when there is exactly one device", () => {
		const devices = [createDevice("audioinput", "default", "Default Microphone")];
		expect(shouldRequestDeviceAccess(devices)).toBe(true);
	});

	it("returns true when any device has an empty label", () => {
		const devices = [
			createDevice("audioinput", "mic-1", "Microphone"),
			createDevice("audioinput", "mic-2", ""),
		];
		expect(shouldRequestDeviceAccess(devices)).toBe(true);
	});

	it("returns true when all device IDs are placeholder values", () => {
		const devices = [
			createDevice("audioinput", "default", "Default"),
			createDevice("audioinput", "communications", "Communications"),
		];
		expect(shouldRequestDeviceAccess(devices)).toBe(true);
	});

	it("returns false when 2+ devices all have real IDs and labels", () => {
		const devices = [
			createDevice("audioinput", "mic-1", "USB Microphone"),
			createDevice("audioinput", "mic-2", "Built-in Microphone"),
		];
		expect(shouldRequestDeviceAccess(devices)).toBe(false);
	});

	it("returns true when a label contains only whitespace", () => {
		const devices = [
			createDevice("audioinput", "mic-1", "Microphone"),
			createDevice("audioinput", "mic-2", "   "),
		];
		expect(shouldRequestDeviceAccess(devices)).toBe(true);
	});
});

// ── mapSelectableDevice ───────────────────────────────────────────────────────

describe("mapSelectableDevice", () => {
	it("preserves the device label when it is non-empty", () => {
		const device = createDevice("audioinput", "abc123", "USB Microphone");
		const result = mapSelectableDevice(device, "Microphone");
		expect(result.label).toBe("USB Microphone");
		expect(result.deviceId).toBe("abc123");
		expect(result.groupId).toBe("abc123-group");
	});

	it("uses fallback prefix + first 8 chars of deviceId when label is empty", () => {
		const device = createDevice("audioinput", "abc123def456", "");
		const result = mapSelectableDevice(device, "Microphone");
		expect(result.label).toBe("Microphone abc123de");
	});

	it("preserves all three selectable-device fields", () => {
		const device = createDevice("videoinput", "cam-999", "My Camera", "group-abc");
		const result = mapSelectableDevice(device, "Camera");
		expect(result).toEqual({ deviceId: "cam-999", label: "My Camera", groupId: "group-abc" });
	});
});

// ── resolveSelectedDeviceId ───────────────────────────────────────────────────

describe("resolveSelectedDeviceId", () => {
	const devices = [
		{ deviceId: "cam-1", label: "Camera One", groupId: "g1" },
		{ deviceId: "cam-2", label: "Camera Two", groupId: "g2" },
	];

	it("keeps the current selection when it exists in the device list", () => {
		expect(resolveSelectedDeviceId("cam-2", devices, false)).toBe("cam-2");
	});

	it("returns 'default' when current selection is not in list and autoSelect is off", () => {
		expect(resolveSelectedDeviceId("cam-99", devices, false)).toBe("default");
	});

	it("auto-selects first device when current is 'default' and autoSelectFirstDevice=true", () => {
		expect(resolveSelectedDeviceId("default", devices, true)).toBe("cam-1");
	});

	it("auto-selects first device when current is missing and autoSelectFirstDevice=true", () => {
		expect(resolveSelectedDeviceId("cam-99", devices, true)).toBe("cam-1");
	});

	it("returns 'default' when devices are empty even with autoSelectFirstDevice=true", () => {
		expect(resolveSelectedDeviceId("default", [], true)).toBe("default");
	});

	it("returns 'default' for 'default' currentId without auto-select enabled", () => {
		expect(resolveSelectedDeviceId("default", devices, false)).toBe("default");
	});
});

// ── enumeratePermissionAwareDevices ──────────────────────────────────────────

describe("enumeratePermissionAwareDevices", () => {
	it("returns filtered and mapped devices by kind", async () => {
		const mockMediaDevices = {
			enumerateDevices: vi.fn(async () => [
				createDevice("audioinput", "mic-1", "USB Mic"),
				createDevice("videoinput", "cam-1", "Webcam"),
				createDevice("audioinput", "mic-2", "Headset"),
			]),
		} as unknown as MediaDevices;

		const result = await enumeratePermissionAwareDevices(mockMediaDevices, "audioinput", "Mic");
		expect(result).toHaveLength(2);
		expect(result.every((d) => d.deviceId !== "")).toBe(true);
	});

	it("excludes devices with an empty deviceId", async () => {
		const mockMediaDevices = {
			enumerateDevices: vi.fn(async () => [
				createDevice("audioinput", "", "Empty ID device"),
				createDevice("audioinput", "mic-1", "Real Device"),
			]),
		} as unknown as MediaDevices;

		const result = await enumeratePermissionAwareDevices(mockMediaDevices, "audioinput", "Mic");
		expect(result).toHaveLength(1);
		expect(result[0].deviceId).toBe("mic-1");
	});
});

// ── hook: disabled state ──────────────────────────────────────────────────────

describe("usePermissionAwareMediaDevices – disabled state", () => {
	it("does not load devices when enabled=false", async () => {
		const mediaDevices = createMediaDevicesMock([
			[createDevice("audioinput", "mic-1", "USB Microphone")],
		]);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				enabled: false,
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(hook.getCurrent().devices).toEqual([]);
		expect(hook.getCurrent().isLoading).toBe(false);
		expect(mediaDevices.enumerateDevices).not.toHaveBeenCalled();

		await hook.unmount();
	});

	it("does not register a devicechange listener when disabled", async () => {
		const mediaDevices = createMediaDevicesMock([
			[createDevice("audioinput", "mic-1", "USB Microphone")],
		]);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				enabled: false,
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(mediaDevices.addEventListener).not.toHaveBeenCalled();

		await hook.unmount();
	});
});

// ── hook: error handling ──────────────────────────────────────────────────────

describe("usePermissionAwareMediaDevices – error handling", () => {
	afterEach(() => {
		// Restore a valid mediaDevices object after each test in this block
		Object.defineProperty(navigator, "mediaDevices", {
			configurable: true,
			value: {
				enumerateDevices: vi.fn(async () => []),
				addEventListener: vi.fn(),
				removeEventListener: vi.fn(),
				getUserMedia: vi.fn(async () => ({ getTracks: () => [] })),
			},
		});
	});

	it("sets the unavailableMessage error when mediaDevices is undefined", async () => {
		Object.defineProperty(navigator, "mediaDevices", {
			configurable: true,
			value: undefined,
		});

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Microphone not available",
			}),
		);

		expect(hook.getCurrent().error).toBe("Microphone not available");
		expect(hook.getCurrent().devices).toEqual([]);
		expect(hook.getCurrent().isLoading).toBe(false);

		await hook.unmount();
	});

	it("sets error and empty devices when enumerateDevices throws", async () => {
		Object.defineProperty(navigator, "mediaDevices", {
			configurable: true,
			value: {
				enumerateDevices: vi.fn(async () => {
					throw new Error("Enumeration failed");
				}),
				addEventListener: vi.fn(),
				removeEventListener: vi.fn(),
			},
		});

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(hook.getCurrent().error).toBe("Enumeration failed");
		expect(hook.getCurrent().devices).toEqual([]);
		expect(hook.getCurrent().isLoading).toBe(false);

		await hook.unmount();
	});

	it("sets permissionDenied=true and specific error for PermissionDeniedError", async () => {
		createMediaDevicesMock(
			[[createDevice("audioinput", "default", "")]],
			vi.fn(async () => {
				throw new DOMException("Permission denied", "PermissionDeniedError");
			}) as MediaDevices["getUserMedia"],
		);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(hook.getCurrent().permissionDenied).toBe(true);
		expect(hook.getCurrent().error).toContain("Microphone access was denied");

		await hook.unmount();
	});

	it("sets permissionDenied=true for SecurityError", async () => {
		createMediaDevicesMock(
			[[createDevice("audioinput", "default", "")]],
			vi.fn(async () => {
				throw new DOMException("Security error", "SecurityError");
			}) as MediaDevices["getUserMedia"],
		);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(hook.getCurrent().permissionDenied).toBe(true);

		await hook.unmount();
	});

	it("sets error but not permissionDenied for generic getUserMedia errors", async () => {
		createMediaDevicesMock(
			[[createDevice("audioinput", "default", "")]],
			vi.fn(async () => {
				throw new Error("Generic device error");
			}) as MediaDevices["getUserMedia"],
		);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(hook.getCurrent().permissionDenied).toBe(false);
		expect(hook.getCurrent().error).toBe("Generic device error");

		await hook.unmount();
	});
});

// ── hook: camera devices ──────────────────────────────────────────────────────

describe("usePermissionAwareMediaDevices – videoinput (camera)", () => {
	it("loads camera devices and auto-selects the first when configured", async () => {
		createMediaDevicesMock([
			[
				createDevice("videoinput", "cam-1", "Built-in Camera"),
				createDevice("videoinput", "cam-2", "USB Camera"),
			],
		]);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "videoinput",
				fallbackLabelPrefix: "Camera",
				unavailableMessage: "Camera unavailable",
				autoSelectFirstDevice: true,
			}),
		);

		expect(hook.getCurrent().devices).toHaveLength(2);
		expect(hook.getCurrent().selectedDeviceId).toBe("cam-1");
		expect(hook.getCurrent().permissionDenied).toBe(false);

		await hook.unmount();
	});

	it("shows the correct camera-specific denial message on NotAllowedError", async () => {
		createMediaDevicesMock(
			[[createDevice("videoinput", "default", "")]],
			vi.fn(async () => {
				throw new DOMException("denied", "NotAllowedError");
			}) as MediaDevices["getUserMedia"],
		);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "videoinput",
				fallbackLabelPrefix: "Camera",
				unavailableMessage: "Camera unavailable",
			}),
		);

		expect(hook.getCurrent().permissionDenied).toBe(true);
		expect(hook.getCurrent().error).toContain("Camera access was denied");

		await hook.unmount();
	});
});

// ── hook: devicechange listener lifecycle ─────────────────────────────────────

describe("usePermissionAwareMediaDevices – listener lifecycle", () => {
	it("registers a devicechange listener on mount and removes it on unmount", async () => {
		const mediaDevices = createMediaDevicesMock([
			[createDevice("audioinput", "mic-1", "Microphone")],
		]);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(mediaDevices.addEventListener).toHaveBeenCalledWith(
			"devicechange",
			expect.any(Function),
		);

		await hook.unmount();

		expect(mediaDevices.removeEventListener).toHaveBeenCalledWith(
			"devicechange",
			expect.any(Function),
		);
	});

	it("does not re-request getUserMedia on device change after a previous denial", async () => {
		const getUserMedia = vi.fn(async () => {
			throw new DOMException("denied", "NotAllowedError");
		}) as MediaDevices["getUserMedia"];

		const mediaDevices = createMediaDevicesMock(
			[[createDevice("audioinput", "default", "")], [createDevice("audioinput", "default", "")]],
			getUserMedia,
		);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(hook.getCurrent().permissionDenied).toBe(true);
		expect(mediaDevices.getUserMedia).toHaveBeenCalledTimes(1);

		await mediaDevices.emitDeviceChange();

		// After denial the device-change handler passes allowPermissionPrompt=false
		expect(mediaDevices.getUserMedia).toHaveBeenCalledTimes(1);

		await hook.unmount();
	});

	it("clears a latched denial when a later devicechange surfaces real labels", async () => {
		const getUserMedia = vi.fn(async () => {
			throw new DOMException("denied", "NotAllowedError");
		}) as MediaDevices["getUserMedia"];

		const mediaDevices = createMediaDevicesMock(
			[
				// Initial load: empty label → prompt → denied → latch.
				[createDevice("audioinput", "default", "")],
				// devicechange after the user flipped the OS toggle: labels
				// now populated, which only happens once permission is granted.
				[
					createDevice("audioinput", "default", "Default Microphone"),
					createDevice("audioinput", "usb-mic", "USB Microphone"),
				],
			],
			getUserMedia,
		);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(hook.getCurrent().permissionDenied).toBe(true);

		await mediaDevices.emitDeviceChange();

		expect(hook.getCurrent().permissionDenied).toBe(false);
		expect(hook.getCurrent().error).toBeNull();
		expect(hook.getCurrent().devices.map((device) => device.deviceId)).toEqual([
			"default",
			"usb-mic",
		]);
		// No re-prompt for getUserMedia — the labels alone told us we're granted.
		expect(mediaDevices.getUserMedia).toHaveBeenCalledTimes(1);

		await hook.unmount();
	});

	it("retries getUserMedia on window focus after a previous denial", async () => {
		let grantNow = false;
		const getUserMedia = vi.fn(async () => {
			if (grantNow) {
				return {
					getTracks: () => [{ stop: vi.fn() }],
				} as unknown as MediaStream;
			}
			throw new DOMException("denied", "NotAllowedError");
		}) as MediaDevices["getUserMedia"];

		const mediaDevices = createMediaDevicesMock(
			[
				// Mount: initial enumerate (empty label → prompt).
				[createDevice("audioinput", "default", "")],
				// Mount: post-denial re-enumerate (still empty → stays denied).
				[createDevice("audioinput", "default", "")],
				// Focus refresh: initial enumerate still empty → triggers prompt.
				[createDevice("audioinput", "default", "")],
				// Focus refresh: post-grant enumerate returns real labels.
				[
					createDevice("audioinput", "default", "Default Microphone"),
					createDevice("audioinput", "usb-mic", "USB Microphone"),
				],
			],
			getUserMedia,
		);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(hook.getCurrent().permissionDenied).toBe(true);
		expect(mediaDevices.getUserMedia).toHaveBeenCalledTimes(1);

		// Simulate: user flipped the OS toggle while the app was unfocused.
		grantNow = true;

		await act(async () => {
			window.dispatchEvent(new Event("focus"));
		});
		await flushEffects();
		await flushEffects();

		// Focus handler re-attempted getUserMedia and it now succeeds silently.
		expect(mediaDevices.getUserMedia).toHaveBeenCalledTimes(2);
		expect(hook.getCurrent().permissionDenied).toBe(false);
		expect(hook.getCurrent().error).toBeNull();
		expect(hook.getCurrent().devices.map((device) => device.deviceId)).toEqual([
			"default",
			"usb-mic",
		]);

		await hook.unmount();
	});

	it("debounces a focus + visibilitychange burst into a single refresh", async () => {
		const getUserMedia = vi.fn(async () => {
			throw new DOMException("denied", "NotAllowedError");
		}) as MediaDevices["getUserMedia"];

		const mediaDevices = createMediaDevicesMock(
			[[createDevice("audioinput", "default", "")]],
			getUserMedia,
		);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(mediaDevices.getUserMedia).toHaveBeenCalledTimes(1);

		Object.defineProperty(document, "visibilityState", {
			configurable: true,
			value: "visible",
		});

		await act(async () => {
			window.dispatchEvent(new Event("focus"));
			document.dispatchEvent(new Event("visibilitychange"));
			window.dispatchEvent(new Event("focus"));
		});
		await flushEffects();
		await flushEffects();

		// Three rapid events should coalesce into exactly one retry.
		expect(mediaDevices.getUserMedia).toHaveBeenCalledTimes(2);

		await hook.unmount();
	});

	it("does not prompt on focus when permission is already granted", async () => {
		const mediaDevices = createMediaDevicesMock([
			[
				createDevice("audioinput", "default", "Default Microphone"),
				createDevice("audioinput", "usb-mic", "USB Microphone"),
			],
		]);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(mediaDevices.getUserMedia).not.toHaveBeenCalled();

		await act(async () => {
			window.dispatchEvent(new Event("focus"));
		});
		await flushEffects();
		await flushEffects();

		// Focus-driven refresh with allowPermissionPrompt=false means no getUserMedia.
		expect(mediaDevices.getUserMedia).not.toHaveBeenCalled();

		await hook.unmount();
	});

	it("removes focus and visibilitychange listeners on unmount", async () => {
		const windowAdd = vi.spyOn(window, "addEventListener");
		const windowRemove = vi.spyOn(window, "removeEventListener");
		const documentAdd = vi.spyOn(document, "addEventListener");
		const documentRemove = vi.spyOn(document, "removeEventListener");

		createMediaDevicesMock([[createDevice("audioinput", "mic-1", "Microphone")]]);

		const hook = await mountHook(() =>
			usePermissionAwareMediaDevices({
				kind: "audioinput",
				fallbackLabelPrefix: "Microphone",
				unavailableMessage: "Unavailable",
			}),
		);

		expect(windowAdd).toHaveBeenCalledWith("focus", expect.any(Function));
		expect(documentAdd).toHaveBeenCalledWith("visibilitychange", expect.any(Function));

		await hook.unmount();

		expect(windowRemove).toHaveBeenCalledWith("focus", expect.any(Function));
		expect(documentRemove).toHaveBeenCalledWith("visibilitychange", expect.any(Function));
	});
});
