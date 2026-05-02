/**
 * Screen recording IPC handlers.
 * Mirrors src-tauri/src/commands/recording.rs.
 *
 * Note: Actual screen capture is delegated to the renderer via the
 * MediaRecorder/getDisplayMedia APIs. The main process manages file paths
 * and recording state.
 */

import type { AppState } from "../state.js";

export function registerRecordingHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
	getDefaultRecordingsDir: () => string,
	emit: (channel: string, payload: unknown) => void,
): void {
	handle("set_recording_state", (args) => {
		const { recording } = args as { recording: boolean };
		setState((s) => {
			s.nativeScreenRecordingActive = recording;
		});
		emit("recording-state-changed", recording);
		return null;
	});

	handle("start_native_screen_recording", async () => {
		// Native ScreenCaptureKit/WGC capture is not implemented in the Electron port.
		// Return an empty path so callers can fall back to Chromium capture without
		// surfacing an IPC handler error in dev logs.
		return "";
	});

	handle("stop_native_screen_recording", async () => {
		const state = getState();
		const outputPath = state.currentVideoPath ?? "";

		setState((s) => {
			s.nativeScreenRecordingActive = false;
		});

		emit("recording-state-changed", false);
		return outputPath;
	});

	handle("select_screen_area", () => {
		// Area selection not implemented in this Electron port
		// Could be added via a transparent overlay window
		return null;
	});
}
