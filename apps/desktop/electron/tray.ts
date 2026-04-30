/**
 * System tray management.
 * Mirrors src-tauri/src/tray.rs.
 */

import { Tray, Menu, nativeImage, app } from "electron";
import type { AppState } from "./state.js";
import { resolveHudWindow, sendToWindow } from "./window-routing.js";

let tray: Tray | null = null;

export function setupTray(
	iconPath: string,
	getState: () => AppState,
): void {
	const icon = nativeImage.createFromPath(iconPath);
	tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon);
	tray.setToolTip("Open Recorder");

	updateTrayMenu(getState);
}

export function updateTrayMenu(
	getState: () => AppState,
): void {
	if (!tray) return;

	const state = getState();
	const isRecording = state.nativeScreenRecordingActive;

	const contextMenu = Menu.buildFromTemplate([
		{
			label: isRecording ? "Stop Recording" : "New Recording",
			click: () => {
				if (isRecording) {
					sendToWindow(resolveHudWindow(), "stop-recording-from-tray", null);
				} else {
					sendToWindow(resolveHudWindow(), "new-recording-from-tray", null);
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
