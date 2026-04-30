/**
 * Application path utilities for the Electron main process.
 * Mirrors src-tauri/src/app_paths.rs.
 */

import path from "node:path";
import os from "node:os";
import { app } from "electron";

const APP_DIR_NAME = "Open Recorder";

/** Default directory for saved recordings (~/Movies/Open Recorder on macOS, ~/Videos/Open Recorder on others). */
export function defaultRecordingsDir(): string {
	const home = os.homedir();
	if (process.platform === "darwin") {
		return path.join(home, "Movies", APP_DIR_NAME);
	}
	if (process.platform === "win32") {
		return path.join(home, "Videos", APP_DIR_NAME);
	}
	return path.join(home, "Videos", APP_DIR_NAME);
}

/** Default directory for screenshots (~/Pictures/Open Recorder). */
export function defaultScreenshotsDir(): string {
	const home = os.homedir();
	return path.join(home, "Pictures", APP_DIR_NAME);
}

/** Directory where app config/settings are persisted. */
export function appConfigDir(): string {
	return app.getPath("userData");
}

/** The user-facing app folder name (used for branding in paths). */
export function appDirName(): string {
	return APP_DIR_NAME;
}
