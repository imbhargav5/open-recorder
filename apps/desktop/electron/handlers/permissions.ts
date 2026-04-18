/**
 * Permission check IPC handlers.
 *
 * On macOS, permissions are checked via systemPreferences.
 * On Linux/Windows, permissions are always "granted".
 */

import { shell, systemPreferences } from "electron";

export function registerPermissionHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
): void {
	// ─── Screen Recording ────────────────────────────────────────────────────

	handle("get_screen_recording_permission_status", async () => {
		if (process.platform === "darwin") {
			const status = systemPreferences.getMediaAccessStatus("screen");
			return status === "granted" ? "granted" : "denied";
		}
		return "granted";
	});

	handle("request_screen_recording_permission", async () => {
		if (process.platform === "darwin") {
			// On macOS, screen recording permission must be granted in System Preferences.
			// Opening the preferences pane is the only way to prompt the user.
			await shell.openExternal(
				"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
			);
			return systemPreferences.getMediaAccessStatus("screen") === "granted";
		}
		return true;
	});

	handle("open_screen_recording_preferences", async () => {
		if (process.platform === "darwin") {
			await shell.openExternal(
				"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
			);
		}
		return null;
	});

	// ─── Accessibility ────────────────────────────────────────────────────────

	handle("get_accessibility_permission_status", async () => {
		if (process.platform === "darwin") {
			// isTrustedAccessibilityClient is synchronous
			const trusted = systemPreferences.isTrustedAccessibilityClient(false);
			return trusted ? "granted" : "denied";
		}
		return "granted";
	});

	handle("request_accessibility_permission", async () => {
		if (process.platform === "darwin") {
			await shell.openExternal(
				"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
			);
			return systemPreferences.isTrustedAccessibilityClient(false);
		}
		return true;
	});

	handle("open_accessibility_preferences", async () => {
		if (process.platform === "darwin") {
			await shell.openExternal(
				"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
			);
		}
		return null;
	});

	// ─── Microphone ──────────────────────────────────────────────────────────

	handle("get_microphone_permission_status", async () => {
		if (process.platform === "darwin") {
			const status = systemPreferences.getMediaAccessStatus("microphone");
			return status;
		}
		return "granted";
	});

	handle("request_microphone_permission", async () => {
		if (process.platform === "darwin") {
			const granted = await systemPreferences.askForMediaAccess("microphone");
			return granted;
		}
		return true;
	});

	handle("open_microphone_preferences", async () => {
		if (process.platform === "darwin") {
			await shell.openExternal(
				"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
			);
		}
		return null;
	});

	// ─── Camera ──────────────────────────────────────────────────────────────

	handle("get_camera_permission_status", async () => {
		if (process.platform === "darwin") {
			const status = systemPreferences.getMediaAccessStatus("camera");
			return status;
		}
		return "granted";
	});

	handle("request_camera_permission", async () => {
		if (process.platform === "darwin") {
			const granted = await systemPreferences.askForMediaAccess("camera");
			return granted;
		}
		return true;
	});

	handle("open_camera_preferences", async () => {
		if (process.platform === "darwin") {
			await shell.openExternal(
				"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
			);
		}
		return null;
	});
}
