/**
 * Platform IPC handlers.
 * Mirrors src-tauri/src/commands/platform.rs.
 */

import { app, shell } from "electron";
import path from "node:path";
import { defaultRecordingsDir } from "../app-paths.js";
import type { AppState } from "../state.js";

export function registerPlatformHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	appResourcesPath: string,
): void {
	handle("get_app_name", () => {
		return app.getName();
	});

	handle("get_platform", () => {
		if (process.platform === "darwin") return "darwin";
		if (process.platform === "win32") return "win32";
		return "linux";
	});

	handle("open_external_url", (args) => {
		const { url } = args as { url: string };
		return shell.openExternal(url);
	});

	handle("reveal_in_folder", (args) => {
		const { path: filePath } = args as { path: string };
		shell.showItemInFolder(filePath);
	});

	handle("open_recordings_folder", () => {
		const state = getState();
		const dir = state.customRecordingsDir ?? defaultRecordingsDir();
		return shell.openPath(dir);
	});

	handle("get_asset_base_path", () => {
		return appResourcesPath;
	});

	handle("hide_cursor", () => {
		// On macOS, we could use native APIs. For now this is a no-op in Electron.
		return null;
	});

	handle("is_wgc_available", () => {
		return process.platform === "win32";
	});

	handle("mux_wgc_recording", () => {
		throw new Error("WGC muxing not yet implemented in Electron backend");
	});
}
