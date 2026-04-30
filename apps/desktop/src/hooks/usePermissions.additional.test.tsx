// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PermissionState, UsePermissionsResult } from "./usePermissions";
import { usePermissions } from "./usePermissions";

// ─── Mock the backend module ──────────────────────────────────────────────────

vi.mock("@/lib/backend", () => ({
	getPlatform: vi.fn(),
	getEffectiveScreenRecordingPermissionStatus: vi.fn(),
	getScreenRecordingPermissionStatus: vi.fn(),
	getMicrophonePermissionStatus: vi.fn(),
	getCameraPermissionStatus: vi.fn(),
	getAccessibilityPermissionStatus: vi.fn(),
	requestScreenRecordingPermission: vi.fn(),
	requestMicrophonePermission: vi.fn(),
	requestCameraPermission: vi.fn(),
	openScreenRecordingPreferences: vi.fn(),
	openMicrophonePreferences: vi.fn(),
	openCameraPreferences: vi.fn(),
	openAccessibilityPreferences: vi.fn(),
}));

// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const backend = vi.mocked(await import("@/lib/backend"));

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// ─── Helpers ─────────────────────────────────────────────────────────────────

type HookHarnessResult = {
	getCurrent: () => UsePermissionsResult;
	unmount: () => Promise<void>;
};

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function mountHook(): Promise<HookHarnessResult> {
	const container = document.createElement("div");
	const root: Root = createRoot(container);
	const store = createStore();
	let currentValue!: UsePermissionsResult;

	function Harness() {
		currentValue = usePermissions();
		return null;
	}

	await act(async () => {
		root.render(
			<Provider store={store}>
				<Harness />
			</Provider>,
		);
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

function setupMediaDevicesMock(getUserMediaImpl?: () => Promise<MediaStream>) {
	const stop = vi.fn();
	const defaultImpl = async () => ({ getTracks: () => [{ stop }] }) as unknown as MediaStream;

	Object.defineProperty(navigator, "mediaDevices", {
		configurable: true,
		value: {
			getUserMedia: vi.fn(getUserMediaImpl ?? defaultImpl),
			enumerateDevices: vi.fn(async () => []),
		},
	});

	return { stop };
}

// ─── Setup / Teardown ────────────────────────────────────────────────────────

beforeEach(() => {
	vi.clearAllMocks();
	setupMediaDevicesMock();
});

afterEach(() => {
	vi.restoreAllMocks();
});

// ─── Additional Tests ─────────────────────────────────────────────────────────

describe("usePermissions – additional coverage", () => {
	// ── allPermissionsGranted and allRequiredPermissionsGranted ──────────────

	describe("allPermissionsGranted computed flags", () => {
		it("allRequiredPermissionsGranted is false when accessibility is denied", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("denied");

			const hook = await mountHook();
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(false);
			expect(hook.getCurrent().allPermissionsGranted).toBe(false);

			await hook.unmount();
		});

		it("allPermissionsGranted is false when only microphone is denied", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("denied");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(true);
			expect(hook.getCurrent().allPermissionsGranted).toBe(false);

			await hook.unmount();
		});

		it("allPermissionsGranted is false when only camera is denied", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("denied");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(true);
			expect(hook.getCurrent().allPermissionsGranted).toBe(false);

			await hook.unmount();
		});

		it("allRequiredPermissionsGranted is false when screenRecording is 'not_determined'", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("not_determined");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(false);

			await hook.unmount();
		});

		it("treats 'restricted' status as not granted for all computed flags", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("restricted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("restricted");
			backend.getCameraPermissionStatus.mockResolvedValue("restricted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("restricted");

			const hook = await mountHook();
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(false);
			expect(hook.getCurrent().allPermissionsGranted).toBe(false);

			await hook.unmount();
		});
	});

	// ── refreshPermissions ────────────────────────────────────────────────────

	describe("refreshPermissions – return value and side effects", () => {
		it("returns the resolved PermissionState as its value", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("denied");
			backend.getMicrophonePermissionStatus.mockResolvedValue("denied");
			backend.getCameraPermissionStatus.mockResolvedValue("denied");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("denied");

			const hook = await mountHook();

			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			let result!: PermissionState;
			await act(async () => {
				result = await hook.getCurrent().refreshPermissions();
			});

			expect(result).toEqual({
				screenRecording: "granted",
				microphone: "granted",
				camera: "granted",
				accessibility: "granted",
			});

			await hook.unmount();
		});

		it("calls getPlatform on each refresh invocation", async () => {
			backend.getPlatform.mockResolvedValue("win32");

			const hook = await mountHook();
			expect(backend.getPlatform).toHaveBeenCalledTimes(1);

			await act(async () => {
				await hook.getCurrent().refreshPermissions();
			});

			expect(backend.getPlatform).toHaveBeenCalledTimes(2);

			await hook.unmount();
		});

		it("sets isChecking to false after completing", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();
			expect(hook.getCurrent().isChecking).toBe(false);

			await hook.unmount();
		});

		it("handles partial backend errors – succeeding checks retain their values, failing checks become 'unknown'", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockRejectedValue(new Error("IPC error"));
			backend.getCameraPermissionStatus.mockResolvedValue("denied");
			backend.getAccessibilityPermissionStatus.mockRejectedValue(new Error("IPC error"));

			const hook = await mountHook();
			const { permissions } = hook.getCurrent();

			expect(permissions.screenRecording).toBe("granted");
			expect(permissions.microphone).toBe("unknown");
			expect(permissions.camera).toBe("denied");
			expect(permissions.accessibility).toBe("unknown");

			await hook.unmount();
		});
	});

	// ── requestMicrophoneAccess ───────────────────────────────────────────────

	describe("requestMicrophoneAccess – fallback and edge cases", () => {
		it("falls back to getUserMedia when native macOS request throws", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus
				.mockResolvedValueOnce("not_determined")
				.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestMicrophonePermission.mockRejectedValue(new Error("IPC error"));

			const hook = await mountHook();

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestMicrophoneAccess();
			});
			await flushEffects();

			expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledWith({
				audio: true,
				video: false,
			});
			expect(granted).toBe(true);

			await hook.unmount();
		});

		it("uses getUserMedia directly on non-macOS (skips native request)", async () => {
			backend.getPlatform.mockResolvedValue("linux");

			const hook = await mountHook();

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestMicrophoneAccess();
			});
			await flushEffects();

			expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledWith({
				audio: true,
				video: false,
			});
			expect(backend.requestMicrophonePermission).not.toHaveBeenCalled();
			expect(granted).toBe(true);

			await hook.unmount();
		});

		it("returns false when getUserMedia fails on non-macOS", async () => {
			backend.getPlatform.mockResolvedValue("win32");
			setupMediaDevicesMock(async () => {
				throw new DOMException("denied", "NotAllowedError");
			});

			const hook = await mountHook();

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestMicrophoneAccess();
			});
			await flushEffects();

			expect(granted).toBe(false);

			await hook.unmount();
		});

		it("stops all tracks returned by getUserMedia stream", async () => {
			backend.getPlatform.mockResolvedValue("win32");
			const stop1 = vi.fn();
			const stop2 = vi.fn();
			setupMediaDevicesMock(
				async () =>
					({
						getTracks: () => [{ stop: stop1 }, { stop: stop2 }],
					}) as unknown as MediaStream,
			);

			const hook = await mountHook();

			await act(async () => {
				await hook.getCurrent().requestMicrophoneAccess();
			});
			await flushEffects();

			expect(stop1).toHaveBeenCalledTimes(1);
			expect(stop2).toHaveBeenCalledTimes(1);

			await hook.unmount();
		});
	});

	// ── requestCameraAccess ───────────────────────────────────────────────────

	describe("requestCameraAccess – fallback and edge cases", () => {
		it("falls back to getUserMedia when native macOS camera request throws", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus
				.mockResolvedValueOnce("not_determined")
				.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestCameraPermission.mockRejectedValue(new Error("IPC error"));

			const hook = await mountHook();

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestCameraAccess();
			});
			await flushEffects();

			expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledWith({
				audio: false,
				video: true,
			});
			expect(granted).toBe(true);

			await hook.unmount();
		});

		it("uses getUserMedia with video constraints on non-macOS", async () => {
			backend.getPlatform.mockResolvedValue("win32");

			const hook = await mountHook();

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestCameraAccess();
			});
			await flushEffects();

			expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledWith({
				audio: false,
				video: true,
			});
			expect(backend.requestCameraPermission).not.toHaveBeenCalled();
			expect(granted).toBe(true);

			await hook.unmount();
		});
	});

	// ── requestScreenRecordingAccess ──────────────────────────────────────────

	describe("requestScreenRecordingAccess – edge cases", () => {
		it("returns false when backend throws and status remains denied", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("denied");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestScreenRecordingPermission.mockRejectedValue(new Error("IPC error"));

			const hook = await mountHook();

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestScreenRecordingAccess();
			});
			await flushEffects();

			expect(granted).toBe(false);

			await hook.unmount();
		});

		it("returns true when backend returns false but re-check shows granted", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus
				.mockResolvedValueOnce("not_determined")
				.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestScreenRecordingPermission.mockResolvedValue(false);

			const hook = await mountHook();

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestScreenRecordingAccess();
			});
			await flushEffects();

			expect(granted).toBe(true);

			await hook.unmount();
		});
	});

	// ── mountedRef guard ──────────────────────────────────────────────────────

	describe("mountedRef guard", () => {
		it("does not update state after component unmounts during an in-flight refresh", async () => {
			let resolvePlatform!: (v: string) => void;
			backend.getPlatform.mockReturnValueOnce(
				new Promise<string>((resolve) => {
					resolvePlatform = resolve;
				}),
			);

			const container = document.createElement("div");
			const root = createRoot(container);
			let currentValue!: UsePermissionsResult;

			function Harness() {
				currentValue = usePermissions();
				return null;
			}

			await act(async () => {
				root.render(<Harness />);
			});

			// Capture state before platform resolves – should still be in initial "checking" state
			expect(currentValue.permissions.screenRecording).toBe("checking");

			// Unmount before the platform promise resolves
			await act(async () => {
				root.unmount();
			});

			// Resolve after unmount – the mountedRef guard should prevent state updates
			await act(async () => {
				resolvePlatform("win32");
				await new Promise((r) => setTimeout(r, 0));
			});

			// We get here without errors – the guard worked
			expect(currentValue.permissions.screenRecording).toBe("checking");
		});
	});

	// ── isMacOS state ─────────────────────────────────────────────────────────

	describe("isMacOS state transitions", () => {
		it("sets isMacOS=true when darwin is detected on mount", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();
			expect(hook.getCurrent().isMacOS).toBe(true);

			await hook.unmount();
		});

		it("updates isMacOS when platform changes between refreshPermissions calls", async () => {
			backend.getPlatform.mockResolvedValue("win32");

			const hook = await mountHook();
			expect(hook.getCurrent().isMacOS).toBe(false);

			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			await act(async () => {
				await hook.getCurrent().refreshPermissions();
			});
			await flushEffects();

			expect(hook.getCurrent().isMacOS).toBe(true);

			await hook.unmount();
		});

		it("prefers the effective probe over the cached screen status", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("denied");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();

			expect(hook.getCurrent().permissions.screenRecording).toBe("denied");
			expect(backend.getScreenRecordingPermissionStatus).not.toHaveBeenCalled();

			await hook.unmount();
		});
	});
});
