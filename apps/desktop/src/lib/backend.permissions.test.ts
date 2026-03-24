/**
 * Tests for the permission-related backend wrappers.
 *
 * These verify that each permission function delegates to the correct
 * Tauri invoke command with the expected arguments.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Mock the Tauri invoke API before importing the module under test
vi.mock("@tauri-apps/api/core", () => ({
	invoke: vi.fn(),
	convertFileSrc: vi.fn((path: string) => `asset://localhost/${path}`),
}));

vi.mock("@tauri-apps/api/event", () => ({
	listen: vi.fn(),
}));

vi.mock("@/lib/mediaPlaybackUrl", () => ({
	resolveMediaPlaybackUrl: vi.fn((path: string) => path),
}));

const { invoke } = vi.mocked(await import("@tauri-apps/api/core"));

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
	});

	describe("openMicrophonePreferences", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue(undefined);
			await backend.openMicrophonePreferences();
			expect(invoke).toHaveBeenCalledWith("open_microphone_preferences");
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
	});

	describe("openCameraPreferences", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue(undefined);
			await backend.openCameraPreferences();
			expect(invoke).toHaveBeenCalledWith("open_camera_preferences");
		});
	});

	// ==================== Screen Recording (existing, verify still works) ====================

	describe("getScreenRecordingPermissionStatus", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue("granted");
			const result = await backend.getScreenRecordingPermissionStatus();
			expect(invoke).toHaveBeenCalledWith("get_screen_recording_permission_status");
			expect(result).toBe("granted");
		});
	});

	describe("requestScreenRecordingPermission", () => {
		it("invokes the correct command and returns boolean", async () => {
			invoke.mockResolvedValue(true);
			const result = await backend.requestScreenRecordingPermission();
			expect(invoke).toHaveBeenCalledWith("request_screen_recording_permission");
			expect(result).toBe(true);
		});
	});

	describe("openScreenRecordingPreferences", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue(undefined);
			await backend.openScreenRecordingPreferences();
			expect(invoke).toHaveBeenCalledWith("open_screen_recording_preferences");
		});
	});

	// ==================== Accessibility (existing, verify still works) ====================

	describe("getAccessibilityPermissionStatus", () => {
		it("invokes the correct command", async () => {
			invoke.mockResolvedValue("granted");
			const result = await backend.getAccessibilityPermissionStatus();
			expect(invoke).toHaveBeenCalledWith("get_accessibility_permission_status");
			expect(result).toBe("granted");
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
