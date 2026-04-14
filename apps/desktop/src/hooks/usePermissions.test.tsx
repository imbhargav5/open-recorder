// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PermissionState, UsePermissionsResult } from "./usePermissions";
import { usePermissions } from "./usePermissions";

// ─── Mock the backend module ─────────────────────────────────────────────────

vi.mock("@/lib/backend", () => ({
	getPlatform: vi.fn(),
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

// ─── Test Harness ────────────────────────────────────────────────────────────

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

// ─── Setup / Teardown ────────────────────────────────────────────────────────

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

beforeEach(() => {
	vi.clearAllMocks();
	setupMediaDevicesMock();
});

afterEach(() => {
	vi.restoreAllMocks();
});

// ─── Tests ───────────────────────────────────────────────────────────────────

describe("usePermissions", () => {
	// ==================== Non-macOS Platform ====================

	describe("on non-macOS platforms", () => {
		beforeEach(() => {
			backend.getPlatform.mockResolvedValue("win32");
		});

		it("returns all permissions as granted", async () => {
			const hook = await mountHook();
			const { permissions, isMacOS, isChecking } = hook.getCurrent();

			expect(isMacOS).toBe(false);
			expect(isChecking).toBe(false);
			expect(permissions).toEqual({
				screenRecording: "granted",
				microphone: "granted",
				camera: "granted",
				accessibility: "granted",
			});

			await hook.unmount();
		});

		it("reports allPermissionsGranted as true", async () => {
			const hook = await mountHook();
			expect(hook.getCurrent().allPermissionsGranted).toBe(true);
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(true);
			await hook.unmount();
		});

		it("does not call any native permission check commands", async () => {
			const hook = await mountHook();

			expect(backend.getScreenRecordingPermissionStatus).not.toHaveBeenCalled();
			expect(backend.getMicrophonePermissionStatus).not.toHaveBeenCalled();
			expect(backend.getCameraPermissionStatus).not.toHaveBeenCalled();
			expect(backend.getAccessibilityPermissionStatus).not.toHaveBeenCalled();

			await hook.unmount();
		});

		it("also treats linux as non-macOS", async () => {
			backend.getPlatform.mockResolvedValue("linux");

			const hook = await mountHook();
			expect(hook.getCurrent().permissions.microphone).toBe("granted");
			expect(hook.getCurrent().isMacOS).toBe(false);
			await hook.unmount();
		});
	});

	// ==================== macOS Platform ====================

	describe("on macOS", () => {
		beforeEach(() => {
			backend.getPlatform.mockResolvedValue("darwin");
		});

		it("fetches all permission statuses on mount", async () => {
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("not_determined");
			backend.getCameraPermissionStatus.mockResolvedValue("denied");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();
			const { permissions, isMacOS, isChecking } = hook.getCurrent();

			expect(isMacOS).toBe(true);
			expect(isChecking).toBe(false);
			expect(permissions).toEqual({
				screenRecording: "granted",
				microphone: "not_determined",
				camera: "denied",
				accessibility: "granted",
			});

			expect(backend.getScreenRecordingPermissionStatus).toHaveBeenCalledTimes(1);
			expect(backend.getMicrophonePermissionStatus).toHaveBeenCalledTimes(1);
			expect(backend.getCameraPermissionStatus).toHaveBeenCalledTimes(1);
			expect(backend.getAccessibilityPermissionStatus).toHaveBeenCalledTimes(1);

			await hook.unmount();
		});

		it("reports allRequiredPermissionsGranted correctly", async () => {
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("not_determined");
			backend.getCameraPermissionStatus.mockResolvedValue("denied");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();

			// Screen + Accessibility are granted → required = true
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(true);
			// Mic and camera are not granted → all = false
			expect(hook.getCurrent().allPermissionsGranted).toBe(false);

			await hook.unmount();
		});

		it("reports allPermissionsGranted when everything is granted", async () => {
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();

			expect(hook.getCurrent().allPermissionsGranted).toBe(true);
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(true);

			await hook.unmount();
		});

		it("reports allRequiredPermissionsGranted as false when screen recording is denied", async () => {
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("denied");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			const hook = await mountHook();
			expect(hook.getCurrent().allRequiredPermissionsGranted).toBe(false);
			await hook.unmount();
		});

		it("handles backend errors gracefully, falling back to 'unknown'", async () => {
			backend.getScreenRecordingPermissionStatus.mockRejectedValue(new Error("IPC error"));
			backend.getMicrophonePermissionStatus.mockRejectedValue(new Error("IPC error"));
			backend.getCameraPermissionStatus.mockRejectedValue(new Error("IPC error"));
			backend.getAccessibilityPermissionStatus.mockRejectedValue(new Error("IPC error"));

			const hook = await mountHook();
			const { permissions } = hook.getCurrent();

			expect(permissions.screenRecording).toBe("unknown");
			expect(permissions.microphone).toBe("unknown");
			expect(permissions.camera).toBe("unknown");
			expect(permissions.accessibility).toBe("unknown");

			await hook.unmount();
		});
	});

	// ==================== refreshPermissions ====================

	describe("refreshPermissions", () => {
		it("re-fetches all statuses and updates state", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("denied");
			backend.getMicrophonePermissionStatus.mockResolvedValue("not_determined");
			backend.getCameraPermissionStatus.mockResolvedValue("not_determined");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("denied");

			const hook = await mountHook();
			expect(hook.getCurrent().permissions.screenRecording).toBe("denied");

			// Simulate user granting screen recording externally
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");

			let result!: PermissionState;
			await act(async () => {
				result = await hook.getCurrent().refreshPermissions();
			});
			await flushEffects();

			expect(result.screenRecording).toBe("granted");
			expect(hook.getCurrent().permissions.screenRecording).toBe("granted");

			await hook.unmount();
		});
	});

	// ==================== requestMicrophoneAccess ====================

	describe("requestMicrophoneAccess", () => {
		it("uses the native request path on macOS", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("not_determined");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestMicrophonePermission.mockResolvedValue(true);

			const hook = await mountHook();

			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestMicrophoneAccess();
			});
			await flushEffects();

			expect(backend.requestMicrophonePermission).toHaveBeenCalled();
			expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
			expect(granted).toBe(true);
			expect(hook.getCurrent().permissions.microphone).toBe("granted");

			await hook.unmount();
		});

		it("returns false when the native macOS request is denied", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("not_determined");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestMicrophonePermission.mockResolvedValue(false);

			const hook = await mountHook();

			backend.getMicrophonePermissionStatus.mockResolvedValue("denied");

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestMicrophoneAccess();
			});
			await flushEffects();

			expect(backend.requestMicrophonePermission).toHaveBeenCalled();
			expect(granted).toBe(false);
			expect(hook.getCurrent().permissions.microphone).toBe("denied");

			await hook.unmount();
		});
	});

	// ==================== requestCameraAccess ====================

	describe("requestCameraAccess", () => {
		it("uses the native request path on macOS", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("not_determined");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestCameraPermission.mockResolvedValue(true);

			const hook = await mountHook();

			backend.getCameraPermissionStatus.mockResolvedValue("granted");

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestCameraAccess();
			});
			await flushEffects();

			expect(backend.requestCameraPermission).toHaveBeenCalled();
			expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
			expect(granted).toBe(true);

			await hook.unmount();
		});

		it("returns false on native camera permission denial", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("not_determined");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestCameraPermission.mockResolvedValue(false);

			const hook = await mountHook();

			backend.getCameraPermissionStatus.mockResolvedValue("denied");

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestCameraAccess();
			});
			await flushEffects();

			expect(backend.requestCameraPermission).toHaveBeenCalled();
			expect(granted).toBe(false);

			await hook.unmount();
		});
	});

	// ==================== requestScreenRecordingAccess ====================

	describe("requestScreenRecordingAccess", () => {
		it("delegates to backend.requestScreenRecordingPermission and refreshes on success", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("denied");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.requestScreenRecordingPermission.mockResolvedValue(true);

			const hook = await mountHook();
			expect(hook.getCurrent().permissions.screenRecording).toBe("denied");

			// After granting, native API returns "granted"
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");

			let granted!: boolean;
			await act(async () => {
				granted = await hook.getCurrent().requestScreenRecordingAccess();
			});
			await flushEffects();

			expect(backend.requestScreenRecordingPermission).toHaveBeenCalled();
			expect(granted).toBe(true);

			await hook.unmount();
		});

		it("falls back to re-checking status when requestScreenRecordingPermission returns false", async () => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("denied");
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

			expect(granted).toBe(false);

			await hook.unmount();
		});
	});

	// ==================== openPermissionSettings ====================

	describe("openPermissionSettings", () => {
		beforeEach(() => {
			backend.getPlatform.mockResolvedValue("darwin");
			backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
			backend.getMicrophonePermissionStatus.mockResolvedValue("granted");
			backend.getCameraPermissionStatus.mockResolvedValue("granted");
			backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
			backend.openScreenRecordingPreferences.mockResolvedValue(undefined);
			backend.openMicrophonePreferences.mockResolvedValue(undefined);
			backend.openCameraPreferences.mockResolvedValue(undefined);
			backend.openAccessibilityPreferences.mockResolvedValue(undefined);
		});

		it("opens screen recording preferences", async () => {
			const hook = await mountHook();
			await act(async () => {
				await hook.getCurrent().openPermissionSettings("screenRecording");
			});
			expect(backend.openScreenRecordingPreferences).toHaveBeenCalled();
			await hook.unmount();
		});

		it("opens microphone preferences", async () => {
			const hook = await mountHook();
			await act(async () => {
				await hook.getCurrent().openPermissionSettings("microphone");
			});
			expect(backend.openMicrophonePreferences).toHaveBeenCalled();
			await hook.unmount();
		});

		it("opens camera preferences", async () => {
			const hook = await mountHook();
			await act(async () => {
				await hook.getCurrent().openPermissionSettings("camera");
			});
			expect(backend.openCameraPreferences).toHaveBeenCalled();
			await hook.unmount();
		});

		it("opens accessibility preferences", async () => {
			const hook = await mountHook();
			await act(async () => {
				await hook.getCurrent().openPermissionSettings("accessibility");
			});
			expect(backend.openAccessibilityPreferences).toHaveBeenCalled();
			await hook.unmount();
		});
	});

	// ==================== Initial State ====================

	describe("initial state", () => {
		it("starts with isChecking=true and 'checking' status for all permissions", async () => {
			// Use a never-resolving promise to keep the hook in its initial state
			let resolveGetPlatform!: (value: string) => void;
			backend.getPlatform.mockReturnValue(
				new Promise((resolve) => {
					resolveGetPlatform = resolve;
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

			// Before the platform check resolves, state should be initial
			expect(currentValue.isChecking).toBe(true);
			expect(currentValue.permissions.screenRecording).toBe("checking");
			expect(currentValue.permissions.microphone).toBe("checking");
			expect(currentValue.permissions.camera).toBe("checking");
			expect(currentValue.permissions.accessibility).toBe("checking");

			// Resolve to cleanup
			resolveGetPlatform("win32");
			await flushEffects();

			await act(async () => {
				root.unmount();
			});
		});
	});
});
