/**
 * Electron main process entry point.
 *
 * Replaces the Tauri (Rust) backend. All IPC handlers that were Tauri commands
 * are registered here via ipcMain.handle().
 */

import { app, BrowserWindow, desktopCapturer, ipcMain, protocol, screen, session, type IpcMainInvokeEvent } from "electron";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
	registerAssetProtocolHandler,
	registerAssetSchemeAsPrivileged,
} from "./asset-protocol.js";

import { createDefaultState } from "./state.js";
import type { AppState } from "./state.js";
import { defaultRecordingsDir, defaultScreenshotsDir, appConfigDir } from "./app-paths.js";
import { setupTray, updateTrayMenu } from "./tray.js";
import { setupMenu } from "./menu.js";
import { registerPlatformHandlers } from "./handlers/platform.js";
import { registerFileHandlers } from "./handlers/files.js";
import { registerSettingsHandlers } from "./handlers/settings.js";
import { registerSourceHandlers } from "./handlers/sources.js";
import { registerRecordingHandlers } from "./handlers/recording.js";
import { registerCursorHandlers } from "./handlers/cursor.js";
import { registerPermissionHandlers } from "./handlers/permissions.js";
import { registerDialogHandlers } from "./handlers/dialogs.js";
import { registerScreenshotHandlers } from "./handlers/screenshot.js";
import { registerWindowMgmtHandlers } from "./handlers/window-mgmt.js";
import { isEditorWindowLabel } from "./window-routing.js";
import { AppUpdaterService } from "./updater.js";

// ─── Constants ───────────────────────────────────────────────────────────────

const HUD_WIDTH = 780;
const HUD_HEIGHT = 155;
const HUD_BOTTOM_MARGIN = 5;
const IS_DEV = !app.isPackaged;
const VITE_DEV_URL = "http://localhost:5789";
const APP_NAME = IS_DEV ? "OpenRecorderDev" : "Open Recorder";

app.name = APP_NAME;

// Must run before app.whenReady() — privileged registration unlocks range requests,
// CORS, and CSP bypass so <video src="asset://..."> can stream large local files.
registerAssetSchemeAsPrivileged(protocol);

// ─── Paths ───────────────────────────────────────────────────────────────────

// ESM doesn't provide __dirname — reconstruct it from import.meta.url
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PRELOAD_PATH = path.join(__dirname, "preload.js");
const RESOURCES_PATH = IS_DEV
	? path.join(__dirname, "..", "public")
	: path.join(process.resourcesPath, "public");

// ─── Application State ───────────────────────────────────────────────────────

const appState = createDefaultState();

function getState(): AppState {
	return appState;
}

function setState(updater: (s: AppState) => void): void {
	updater(appState);
}

// ─── Emit to all renderer windows ────────────────────────────────────────────

function emit(channel: string, payload: unknown): void {
	for (const win of BrowserWindow.getAllWindows()) {
		if (!win.isDestroyed()) {
			win.webContents.send(channel, payload);
		}
	}
}

// ─── URL Resolution ───────────────────────────────────────────────────────────

function getRendererUrl(windowType?: string, extraQuery?: string): string {
	const base = IS_DEV ? VITE_DEV_URL : `file://${path.join(__dirname, "..", "dist", "index.html")}`;
	const params = new URLSearchParams();
	if (windowType) params.set("windowType", windowType);
	if (extraQuery) {
		for (const [k, v] of new URLSearchParams(extraQuery)) {
			params.set(k, v);
		}
	}
	const query = params.toString();
	return query ? `${base}?${query}` : base;
}

// ─── IPC Handler Registration ─────────────────────────────────────────────────

/**
 * Wrap ipcMain.handle to normalise the signature: handlers receive `args` as a
 * plain object (the second argument from ipcRenderer.invoke) and return a value
 * that is sent back to the renderer.
 */
function handle(channel: string, handler: (args: unknown) => unknown): void {
	ipcMain.handle(channel, async (_event, args) => {
		return handler(args ?? {});
	});
}

function handleWithSender(
	channel: string,
	handler: (event: IpcMainInvokeEvent, args: unknown) => unknown,
): void {
	ipcMain.handle(channel, async (event, args) => {
		return handler(event, args ?? {});
	});
}

function registerAllHandlers(): AppUpdaterService {
	registerPlatformHandlers(handle, getState, RESOURCES_PATH);
	registerFileHandlers(handle, getState, setState, defaultRecordingsDir);
	registerSettingsHandlers(handle, getState, setState, defaultRecordingsDir, appConfigDir);
	registerSourceHandlers(handle, getState, setState);
	registerRecordingHandlers(handle, getState, setState, defaultRecordingsDir, emit);
	registerCursorHandlers(handle, getState, setState);
	registerPermissionHandlers(handle);
	registerDialogHandlers(handle, getState, setState);
	registerScreenshotHandlers(handle, getState, setState, defaultScreenshotsDir);

	// Pass a resolver function for the renderer URL
	const rendererUrlResolver = () => IS_DEV ? VITE_DEV_URL : `file://${path.join(__dirname, "..", "dist", "index.html")}`;
	registerWindowMgmtHandlers(
		handle,
		handleWithSender,
		setState,
		rendererUrlResolver,
		PRELOAD_PATH,
	);

	// ─── Additional app-level handlers ─────────────────────────────────────
	handle("get_app_version", () => app.getVersion());
	const updater = new AppUpdaterService(emit);
	handle("get_updater_state", () => updater.getState());
	handle("check_for_updates", async (args) =>
		updater.checkForUpdates(args as { showDialog?: boolean }),
	);
	handle("download_update", () => updater.downloadUpdate());
	handle("dismiss_updater_dialog", () => updater.dismissDialog());
	handle("install_update_and_restart", () => {
		updater.installUpdateAndRestart();
		return null;
	});
	handle("write_clipboard_image", async (args) => {
		const { clipboard, nativeImage } = await import("electron");
		const { data, width, height } = args as { data: number[]; width: number; height: number };
		const buffer = Buffer.from(data);
		// Create a NativeImage from raw RGBA pixel data
		const image = nativeImage.createFromBuffer(buffer, { width, height });
		clipboard.writeImage(image);
		return null;
	});

	return updater;
}

// ─── Window Creation ──────────────────────────────────────────────────────────

function createHudOverlay(): BrowserWindow {
	// Compute position: bottom-center of primary monitor
	const primaryDisplay = screen.getPrimaryDisplay();
	const { width: sw, height: sh } = primaryDisplay.workAreaSize;
	const { x: mx, y: my } = primaryDisplay.bounds;
	const x = Math.round(mx + (sw - HUD_WIDTH) / 2);
	const y = Math.round(my + sh - HUD_HEIGHT - HUD_BOTTOM_MARGIN);

	const win = new BrowserWindow({
		width: HUD_WIDTH,
		height: HUD_HEIGHT,
		x,
		y,
		resizable: false,
		frame: false,
		transparent: true,
		alwaysOnTop: true,
		skipTaskbar: true,
		hasShadow: false,
		webPreferences: {
			nodeIntegration: false,
			contextIsolation: true,
			sandbox: false,
			preload: PRELOAD_PATH,
		},
	});

	(win as BrowserWindow & { windowLabel: string }).windowLabel = "hud-overlay";

	const url = IS_DEV
		? `${VITE_DEV_URL}?windowType=hud-overlay`
		: `file://${path.join(__dirname, "..", "dist", "index.html")}?windowType=hud-overlay`;

	win.loadURL(url);

	if (IS_DEV) {
		win.webContents.openDevTools({ mode: "detach" });
	}

	return win;
}

function getTrackedWindowLabel(win: BrowserWindow): string {
	return (win as BrowserWindow & { windowLabel?: string }).windowLabel ?? "";
}

// ─── App Lifecycle ────────────────────────────────────────────────────────────

// Register the asset:// protocol for serving local media files
app.whenReady().then(() => {
	registerAssetProtocolHandler(protocol);

	const updater = registerAllHandlers();
	setupMenu(() => {
		void updater.checkForUpdates({ showDialog: true });
	});

	// Wire up getDisplayMedia() — without this Electron returns "Not supported".
	// Resolve the source the user already picked via the source-selector and hand it
	// to the WebRTC pipeline. If nothing is selected, fall back to the first screen.
	session.defaultSession.setDisplayMediaRequestHandler(
		async (_request, callback) => {
			const wantedId = appState.selectedSource?.id;
			try {
				const sources = await desktopCapturer.getSources({
					types: ["screen", "window"],
					thumbnailSize: { width: 0, height: 0 },
				});
				const match =
					(wantedId && sources.find((s) => s.id === wantedId)) ??
					sources.find((s) => s.id.startsWith("screen:")) ??
					sources[0];
				if (!match) {
					callback({});
					return;
				}
				callback({ video: match });
			} catch (err) {
				console.error("[setDisplayMediaRequestHandler] failed:", err);
				callback({});
			}
		},
		{ useSystemPicker: false },
	);

	createHudOverlay();

	// Try to set up the system tray
	try {
		const iconPath = path.join(RESOURCES_PATH, "icons", "icon.png");
		setupTray(iconPath, getState);
	} catch (err) {
		console.warn("[main] Could not set up tray:", err);
	}

	// Window close event handling
	app.on("browser-window-created", (_, win) => {
		const trackedLabel = getTrackedWindowLabel(win);

		win.on("close", (event) => {
			if (isEditorWindowLabel(trackedLabel)) {
				const hasUnsaved = appState.unsavedEditorWindows.has(trackedLabel);
				if (hasUnsaved) {
					event.preventDefault();
					win.webContents.send("request-save-before-close", null);
				}
			}
		});

		win.on("closed", () => {
			if (appState.nativeScreenRecordingActive) {
				appState.nativeScreenRecordingActive = false;
				emit("recording-interrupted", null);
			}
			if (isEditorWindowLabel(trackedLabel)) {
				appState.unsavedEditorWindows.delete(trackedLabel);
				appState.hasUnsavedChanges = appState.unsavedEditorWindows.size > 0;
			}
			updateTrayMenu(getState);
		});
	});

	app.on("activate", () => {
		// On macOS re-create the HUD if all windows were closed
		if (BrowserWindow.getAllWindows().length === 0) {
			createHudOverlay();
		}
	});
});

app.on("window-all-closed", () => {
	// On macOS it's conventional to keep the app running until the user quits explicitly.
	if (process.platform !== "darwin") {
		app.quit();
	}
});
