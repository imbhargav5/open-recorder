/**
 * Tests for the permission-related backend wrappers.
 *
 * These verify that each permission function delegates to the correct
 * IPC command with the expected arguments.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Mock the Electron IPC bridge before importing the module under test
vi.mock("@/lib/electronBridge", () => ({
	invoke: vi.fn(),
	listen: vi.fn(),
}));

vi.mock("@/lib/mediaPlaybackUrl", () => ({
	resolveMediaPlaybackUrl: vi.fn((path: string) => path),
}));

const { invoke } = vi.mocked(await import("@/lib/electronBridge"));

const backend = await import("@/lib/backend");

beforeEach(() => {
	vi.clearAllMocks();
});

afterEach(() => {
	vi.restoreAllMocks();
});

describe("permission backend wrappers", () => {
	// ==================== Microphone ====================

	describe("getMicrophonePermissionStatus", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue("granted");
			const result = await backend.getMicrophonePermissionStatus();
			expect(invoke).toHaveBeenCalledWith("get_microphone_permission_status");
			expect(result).toBe("granted");
		});

		it("propagates all possible status values", async () => {
			for (const status of ["granted", "denied", "not_determined", "restricted", "unknown"]) {
				invoke.mockResolvedValue(status);
				const result = await backend.getMicrophonePermissionStatus();
				expect(result).toBe(status);
			}
		});

		it("normalizes Electron's 'not-determined' status", async () => {
			invoke.mockResolvedValue("not-determined");
			const result = await backend.getMicrophonePermissionStatus();
			expect(result).toBe("not_determined");
		});

		it("logs error and returns 'unknown' when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.getMicrophonePermissionStatus();

			expect(result).toBe("unknown");
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith(
				"[backend] getMicrophonePermissionStatus failed:",
				ipcError,
			);
		});
	});

	describe("openMicrophonePreferences", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue(undefined);
			await backend.openMicrophonePreferences();
			expect(invoke).toHaveBeenCalledWith("open_microphone_preferences");
		});
	});

	describe("requestMicrophonePermission", () => {
		it("invokes the correct command and returns a boolean", async () => {
			invoke.mockResolvedValue(true);
			const result = await backend.requestMicrophonePermission();
			expect(invoke).toHaveBeenCalledWith("request_microphone_permission");
			expect(result).toBe(true);
		});

		it("logs error and returns false when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.requestMicrophonePermission();

			expect(result).toBe(false);
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith(
				"[backend] requestMicrophonePermission failed:",
				ipcError,
			);
		});
	});

	// ==================== Camera ====================

	describe("getCameraPermissionStatus", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue("not_determined");
			const result = await backend.getCameraPermissionStatus();
			expect(invoke).toHaveBeenCalledWith("get_camera_permission_status");
			expect(result).toBe("not_determined");
		});

		it("logs error and returns 'unknown' when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.getCameraPermissionStatus();

			expect(result).toBe("unknown");
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith(
				"[backend] getCameraPermissionStatus failed:",
				ipcError,
			);
		});

		it("normalizes Electron's 'not-determined' status", async () => {
			invoke.mockResolvedValue("not-determined");
			const result = await backend.getCameraPermissionStatus();
			expect(result).toBe("not_determined");
		});
	});

	describe("openCameraPreferences", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue(undefined);
			await backend.openCameraPreferences();
			expect(invoke).toHaveBeenCalledWith("open_camera_preferences");
		});
	});

	describe("requestCameraPermission", () => {
		it("invokes the correct command and returns a boolean", async () => {
			invoke.mockResolvedValue(false);
			const result = await backend.requestCameraPermission();
			expect(invoke).toHaveBeenCalledWith("request_camera_permission");
			expect(result).toBe(false);
		});

		it("logs error and returns false when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.requestCameraPermission();

			expect(result).toBe(false);
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith("[backend] requestCameraPermission failed:", ipcError);
		});
	});

	// ==================== Screen Recording ====================

	describe("getScreenRecordingPermissionStatus", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue("granted");
			const result = await backend.getScreenRecordingPermissionStatus();
			expect(invoke).toHaveBeenCalledWith("get_screen_recording_permission_status");
			expect(result).toBe("granted");
		});

		it("logs error and returns 'unknown' when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.getScreenRecordingPermissionStatus();

			expect(result).toBe("unknown");
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith(
				"[backend] getScreenRecordingPermissionStatus failed:",
				ipcError,
			);
		});

		it("normalizes Electron's 'not-determined' status", async () => {
			invoke.mockResolvedValue("not-determined");
			const result = await backend.getScreenRecordingPermissionStatus();
			expect(result).toBe("not_determined");
		});
	});

	describe("probeScreenRecordingEffectiveStatus", () => {
		it("invokes the probe command", async () => {
			invoke.mockResolvedValue("granted");
			const result = await backend.probeScreenRecordingEffectiveStatus();
			expect(invoke).toHaveBeenCalledWith("probe_screen_recording_effective_status");
			expect(result).toBe("granted");
		});

		it("normalizes Electron's 'not-determined' status", async () => {
			invoke.mockResolvedValue("not-determined");
			const result = await backend.probeScreenRecordingEffectiveStatus();
			expect(result).toBe("not_determined");
		});

		it("logs error and returns 'unknown' when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.probeScreenRecordingEffectiveStatus();

			expect(result).toBe("unknown");
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith(
				"[backend] probeScreenRecordingEffectiveStatus failed:",
				ipcError,
			);
		});
	});

	describe("getEffectiveScreenRecordingPermissionStatus", () => {
		it("returns the probe result when it is known", async () => {
			invoke.mockResolvedValueOnce("granted");

			const result = await backend.getEffectiveScreenRecordingPermissionStatus();

			expect(result).toBe("granted");
			expect(invoke).toHaveBeenCalledTimes(1);
			expect(invoke).toHaveBeenCalledWith("probe_screen_recording_effective_status");
		});

		it("falls back to the cached status when the probe is unknown", async () => {
			invoke.mockResolvedValueOnce("unknown").mockResolvedValueOnce("not-determined");

			const result = await backend.getEffectiveScreenRecordingPermissionStatus();

			expect(result).toBe("not_determined");
			expect(invoke).toHaveBeenNthCalledWith(1, "probe_screen_recording_effective_status");
			expect(invoke).toHaveBeenNthCalledWith(2, "get_screen_recording_permission_status");
		});
	});

	describe("requestScreenRecordingPermission", () => {
		it("invokes the correct command and returns boolean", async () => {
			invoke.mockResolvedValue(true);
			const result = await backend.requestScreenRecordingPermission();
			expect(invoke).toHaveBeenCalledWith("request_screen_recording_permission");
			expect(result).toBe(true);
		});

		it("logs error and returns false when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.requestScreenRecordingPermission();

			expect(result).toBe(false);
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith(
				"[backend] requestScreenRecordingPermission failed:",
				ipcError,
			);
		});
	});

	describe("openScreenRecordingPreferences", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue(undefined);
			await backend.openScreenRecordingPreferences();
			expect(invoke).toHaveBeenCalledWith("open_screen_recording_preferences");
		});
	});

	// ==================== Accessibility ====================

	describe("getAccessibilityPermissionStatus", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue("granted");
			const result = await backend.getAccessibilityPermissionStatus();
			expect(invoke).toHaveBeenCalledWith("get_accessibility_permission_status");
			expect(result).toBe("granted");
		});

		it("logs error and returns 'unknown' when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.getAccessibilityPermissionStatus();

			expect(result).toBe("unknown");
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith(
				"[backend] getAccessibilityPermissionStatus failed:",
				ipcError,
			);
		});
	});

	describe("requestAccessibilityPermission", () => {
		it("logs error and returns false when IPC call rejects", async () => {
			const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
			const ipcError = new Error("IPC channel closed");
			invoke.mockRejectedValue(ipcError);

			const result = await backend.requestAccessibilityPermission();

			expect(result).toBe(false);
			expect(errorSpy).toHaveBeenCalledOnce();
			expect(errorSpy).toHaveBeenCalledWith(
				"[backend] requestAccessibilityPermission failed:",
				ipcError,
			);
		});
	});

	describe("openAccessibilityPreferences", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue(undefined);
			await backend.openAccessibilityPreferences();
			expect(invoke).toHaveBeenCalledWith("open_accessibility_preferences");
		});
	});
});
