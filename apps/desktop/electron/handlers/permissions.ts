/**
 * Permission check IPC handlers.
 * Mirrors src-tauri/src/commands/permissions.rs.
 *
 * On macOS, permissions are checked via systemPreferences.
 * On Linux/Windows, permissions are always "granted".
 */

import { app, desktopCapturer, shell, systemPreferences } from "electron";

/**
 * Probe actual screen-recording permission by asking the OS for a thumbnail.
 *
 * macOS caches `CGPreflightScreenCaptureAccess()` inside the process once it
 * has been called — so `systemPreferences.getMediaAccessStatus("screen")` can
 * stay `"denied"` for the rest of the main process's lifetime even after the
 * user flips the toggle in System Settings.
 *
 * `desktopCapturer.getSources` on macOS calls into Chromium's capture path
 * (`CGDisplayStream` / `CGWindowListCreateImage`), which re-checks TCC on each
 * invocation and returns a thumbnail with real pixel data when screen recording
 * is actually allowed.  If the thumbnail is missing / empty / all-black the
 * permission is effectively denied regardless of what the cached status says.
 *
 * Returns `"granted" | "denied" | "unknown"`:
 *  - `"granted"` — at least one screen source has a non-empty thumbnail with
 *    visible pixels.
 *  - `"denied"` — sources came back without usable thumbnails.
 *  - `"unknown"` — the probe itself threw or isn't available on this platform.
 */
async function probeScreenRecordingEffectiveStatus(): Promise<"granted" | "denied" | "unknown"> {
	if (process.platform !== "darwin") {
		return "granted";
	}
	try {
		const sources = await desktopCapturer.getSources({
			types: ["screen"],
			thumbnailSize: { width: 64, height: 64 },
		});
		if (sources.length === 0) {
			return "denied";
		}
		for (const source of sources) {
			const thumb = source.thumbnail;
			if (!thumb || thumb.isEmpty()) {
				continue;
			}
			const size = thumb.getSize();
			if (size.width === 0 || size.height === 0) {
				continue;
			}
			const bitmap = thumb.toBitmap();
			for (let i = 0; i < bitmap.length; i += 4) {
				// BGRA on macOS; any non-zero colour channel means real pixels.
				if (bitmap[i] !== 0 || bitmap[i + 1] !== 0 || bitmap[i + 2] !== 0) {
					return "granted";
				}
			}
		}
		return "denied";
	} catch {
		return "unknown";
	}
}

export function registerPermissionHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
): void {
	// ─── Screen Recording ────────────────────────────────────────────────────

	handle("get_screen_recording_permission_status", async () => {
		if (process.platform !== "darwin") {
			return "granted";
		}
		// Return the raw status so the UI can distinguish `not-determined` from
		// a real `denied`.  The previous behaviour collapsed every non-granted
		// value (including `not-determined`, `restricted`, and `unknown`) to
		// `"denied"`, which made first-run always look like an explicit denial.
		//
		// If the cached status says we are denied we also run the
		// desktopCapturer probe below to detect the "user just granted in
		// System Settings but macOS still caches denied in-process" case.
		const cachedStatus = systemPreferences.getMediaAccessStatus("screen");
		if (cachedStatus !== "granted") {
			const effective = await probeScreenRecordingEffectiveStatus();
			if (effective === "granted") {
				return "granted";
			}
		}
		return cachedStatus;
	});

	handle("probe_screen_recording_effective_status", async () => {
		return probeScreenRecordingEffectiveStatus();
	});

	handle("request_screen_recording_permission", async () => {
		if (process.platform === "darwin") {
			// Trigger a screen capture attempt so macOS registers this app in
			// System Preferences > Privacy > Screen Recording.  Without this
			// the app never appears in the list.
			try {
				await desktopCapturer.getSources({ types: ["screen"], thumbnailSize: { width: 1, height: 1 } });
			} catch {
				// Expected to fail if permission is denied — that's fine,
				// the attempt itself is what registers the app.
			}
			await shell.openExternal(
				"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
			);
			// Re-probe via desktopCapturer to get a fresh answer that bypasses
			// the per-process TCC cache on `getMediaAccessStatus`.
			if (systemPreferences.getMediaAccessStatus("screen") === "granted") {
				return true;
			}
			const effective = await probeScreenRecordingEffectiveStatus();
			return effective === "granted";
		}
		return true;
	});

	// ─── App lifecycle ────────────────────────────────────────────────────────

	handle("relaunch_app", async () => {
		// Required after the user grants screen-recording permission in dev:
		// macOS caches `CGPreflightScreenCaptureAccess` for the lifetime of the
		// process, so the only way to make Chromium pick up the new grant with
		// full fidelity is to restart the app.
		app.relaunch();
		app.exit(0);
		return null;
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
