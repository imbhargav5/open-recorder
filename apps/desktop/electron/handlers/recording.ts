/**
 * Screen recording IPC handlers.
 * Mirrors src-tauri/src/commands/recording.rs.
 *
 * Note: Actual screen capture is delegated to the renderer via the
 * MediaRecorder/getDisplayMedia APIs. The main process manages file paths
 * and recording state.
 */

import { BrowserWindow, desktopCapturer, ipcMain, screen } from "electron";
import type { AppState } from "../state.js";
import { getWindowByLabel } from "../window-routing.js";

interface AreaSelectionResult {
	x: number;
	y: number;
	width: number;
	height: number;
	displayId: number;
	displayBounds: {
		x: number;
		y: number;
		width: number;
		height: number;
	};
	captureSourceId?: string;
}

type AreaSelectionPayload =
	| {
			type: "complete";
			x: number;
			y: number;
			width: number;
			height: number;
			displayId: number;
	  }
	| { type: "cancel"; displayId: number };

function buildAreaSelectorHtml(channel: string, displayId: number): string {
	const channelLiteral = JSON.stringify(channel);
	return `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<style>
	html, body {
		width: 100%;
		height: 100%;
		margin: 0;
		overflow: hidden;
		cursor: crosshair;
		background: rgba(3, 7, 18, 0.22);
		font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
		user-select: none;
	}
	#hint {
		position: fixed;
		top: 20px;
		left: 50%;
		transform: translateX(-50%);
		padding: 8px 12px;
		border: 1px solid rgba(255,255,255,0.22);
		border-radius: 999px;
		background: rgba(10,10,15,0.72);
		color: white;
		font-size: 13px;
		font-weight: 600;
		backdrop-filter: blur(16px);
	}
	#selection {
		position: fixed;
		display: none;
		border: 2px solid #60a5fa;
		border-radius: 10px;
		background: rgba(96, 165, 250, 0.14);
		box-shadow: 0 0 0 9999px rgba(2, 6, 23, 0.42), 0 0 30px rgba(96, 165, 250, 0.45);
	}
</style>
</head>
<body>
	<div id="hint">Drag to choose recording area · Esc to cancel</div>
	<div id="selection"></div>
	<script>
		const { ipcRenderer } = require("electron");
		const channel = ${channelLiteral};
		const displayId = ${displayId};
		const selection = document.getElementById("selection");
		let start = null;

		function normalizedRect(point) {
			const x = Math.min(start.x, point.x);
			const y = Math.min(start.y, point.y);
			const width = Math.abs(point.x - start.x);
			const height = Math.abs(point.y - start.y);
			return { x, y, width, height };
		}

		function updateSelection(point) {
			const rect = normalizedRect(point);
			selection.style.display = "block";
			selection.style.left = rect.x + "px";
			selection.style.top = rect.y + "px";
			selection.style.width = rect.width + "px";
			selection.style.height = rect.height + "px";
		}

		function sendCancel() {
			ipcRenderer.send(channel, { type: "cancel", displayId });
		}

		window.addEventListener("keydown", (event) => {
			if (event.key === "Escape") sendCancel();
		});

		window.addEventListener("pointerdown", (event) => {
			start = { x: event.clientX, y: event.clientY };
			updateSelection(start);
		});

		window.addEventListener("pointermove", (event) => {
			if (!start) return;
			updateSelection({ x: event.clientX, y: event.clientY });
		});

		window.addEventListener("pointerup", (event) => {
			if (!start) return;
			const rect = normalizedRect({ x: event.clientX, y: event.clientY });
			start = null;
			if (rect.width < 8 || rect.height < 8) {
				sendCancel();
				return;
			}
			ipcRenderer.send(channel, { type: "complete", displayId, ...rect });
		});
	</script>
</body>
</html>`;
}

async function getCaptureSourceId(displayId: number): Promise<string | undefined> {
	const sources = await desktopCapturer.getSources({
		types: ["screen"],
		thumbnailSize: { width: 0, height: 0 },
	});
	const match = sources.find((source) => source.display_id === String(displayId));
	return match?.id ?? sources[0]?.id;
}

function selectScreenArea(): Promise<AreaSelectionResult | null> {
	const hud = getWindowByLabel("hud-overlay");
	const sourceSelector = getWindowByLabel("source-selector");
	hud?.hide();
	sourceSelector?.hide();

	const displays = screen.getAllDisplays();
	const channel = `area-selection-${Date.now()}-${Math.random().toString(36).slice(2)}`;
	const overlayWindows = displays.map((display) => {
		const { bounds } = display;
		const win = new BrowserWindow({
			x: bounds.x,
			y: bounds.y,
			width: bounds.width,
			height: bounds.height,
			frame: false,
			transparent: true,
			resizable: false,
			movable: false,
			alwaysOnTop: true,
			skipTaskbar: true,
			fullscreenable: false,
			hasShadow: false,
			backgroundColor: "#00000000",
			webPreferences: {
				nodeIntegration: true,
				contextIsolation: false,
				sandbox: false,
			},
		});
		win.setAlwaysOnTop(true, "screen-saver");
		win.loadURL(
			`data:text/html;charset=utf-8,${encodeURIComponent(buildAreaSelectorHtml(channel, display.id))}`,
		);
		return win;
	});

	return new Promise((resolve) => {
		let settled = false;

		const cleanup = (result: AreaSelectionResult | null) => {
			if (settled) return;
			settled = true;
			ipcMain.removeListener(channel, handleResult);
			for (const win of overlayWindows) {
				if (!win.isDestroyed()) win.destroy();
			}

			if (result) {
				hud?.show();
				hud?.focus();
			} else {
				hud?.show();
				sourceSelector?.show();
				sourceSelector?.focus();
			}

			resolve(result);
		};

		const handleResult = async (_event: Electron.IpcMainEvent, payload: AreaSelectionPayload) => {
			if (payload.type === "cancel") {
				cleanup(null);
				return;
			}

			const display = displays.find((candidate) => candidate.id === payload.displayId);
			if (!display) {
				cleanup(null);
				return;
			}

			const captureSourceId = await getCaptureSourceId(display.id).catch(() => undefined);
			cleanup({
				x: payload.x,
				y: payload.y,
				width: payload.width,
				height: payload.height,
				displayId: display.id,
				displayBounds: display.bounds,
				captureSourceId,
			});
		};

		ipcMain.on(channel, handleResult);
		for (const win of overlayWindows) {
			win.on("closed", () => {
				if (!settled && overlayWindows.every((overlay) => overlay.isDestroyed())) {
					cleanup(null);
				}
			});
		}
	});
}

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

	handle("select_screen_area", () => selectScreenArea());
}
