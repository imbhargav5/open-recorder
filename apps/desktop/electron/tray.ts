/**
 * System tray management.
 * Mirrors src-tauri/src/tray.rs.
 */

import { Tray, Menu, nativeImage, app } from "electron";
import path from "node:path";
import type { AppState } from "./state.js";

let tray: Tray | null = null;

export function setupTray(
	iconPath: string,
	getState: () => AppState,
	emit: (channel: string, payload: unknown) => void,
): void {
	const icon = nativeImage.createFromPath(iconPath);
	tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon);
	tray.setToolTip("Open Recorder");

	updateTrayMenu(getState, emit);
}

export function updateTrayMenu(
	getState: () => AppState,
	emit: (channel: string, payload: unknown) => void,
): void {
	if (!tray) return;

	const state = getState();
	const isRecording = state.nativeScreenRecordingActive;

	const contextMenu = Menu.buildFromTemplate([
		{
			label: isRecording ? "Stop Recording" : "New Recording",
			click: () => {
				if (isRecording) {
					emit("stop-recording-from-tray", null);
				} else {
					emit("new-recording-from-tray", null);
				}
			},
		},
		{ type: "separator" },
		{
			label: "Quit Open Recorder",
			click: () => app.quit(),
		},
	]);

	tray.setContextMenu(contextMenu);
}
