/**
 * Screen recording IPC handlers.
 * Mirrors src-tauri/src/commands/recording.rs.
 *
 * Note: Actual screen capture is delegated to the renderer via the
 * MediaRecorder/getDisplayMedia APIs. The main process manages file paths
 * and recording state.
 */

import fs from "node:fs";
import path from "node:path";
import { BrowserWindow } from "electron";
import { randomUUID } from "node:crypto";
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

	handle("start_native_screen_recording", async (args) => {
		const state = getState();
		const recordingsDir = state.customRecordingsDir ?? getDefaultRecordingsDir();

		await fs.promises.mkdir(recordingsDir, { recursive: true });

		const fileName = `recording-${randomUUID()}.webm`;
		const outputPath = path.join(recordingsDir, fileName);

		// Create an empty file to reserve the path
		await fs.promises.writeFile(outputPath, Buffer.alloc(0));

		setState((s) => {
			s.nativeScreenRecordingActive = true;
			s.currentVideoPath = outputPath;
		});

		return outputPath;
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
