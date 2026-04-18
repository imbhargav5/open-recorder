/**
 * File I/O IPC handlers.
 */

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import type { AppState, RecordingSession } from "../state.js";

function getRecordingsDir(state: AppState, defaultDir: string): string {
	return state.customRecordingsDir ?? defaultDir;
}

/** Validate the path is within allowed directories (temp dir, user data/home). */
function isWithinAllowedDirs(filePath: string): boolean {
	const resolvedPath = (() => {
		try {
			if (fs.existsSync(filePath)) {
				return fs.realpathSync(filePath);
			}
			// File not created yet — resolve parent
			const parent = path.dirname(filePath);
			if (fs.existsSync(parent)) {
				return path.join(fs.realpathSync(parent), path.basename(filePath));
			}
			return filePath;
		} catch {
			return filePath;
		}
	})();

	const allowed = [os.tmpdir(), os.homedir()];
	// Also allow XDG data dirs on Linux
	if (process.env.XDG_DATA_HOME) allowed.push(process.env.XDG_DATA_HOME);
	if (process.env.HOME) allowed.push(process.env.HOME);

	return allowed.some((dir) => resolvedPath.startsWith(dir));
}

export function registerFileHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
	getDefaultRecordingsDir: () => string,
): void {
	handle("read_local_file", async (args) => {
		const { path: filePath } = args as { path: string };
		if (!isWithinAllowedDirs(filePath)) {
			throw new Error("Access denied: path is outside allowed directories");
		}
		const data = await fs.promises.readFile(filePath);
		return Array.from(data);
	});

	handle("store_recorded_video", async (args) => {
		const { videoData, fileName } = args as { videoData: number[]; fileName: string };
		const state = getState();
		const dir = getRecordingsDir(state, getDefaultRecordingsDir());
		await fs.promises.mkdir(dir, { recursive: true });
		const filePath = path.join(dir, fileName);
		await fs.promises.writeFile(filePath, Buffer.from(videoData));
		setState((s) => {
			s.currentVideoPath = filePath;
		});
		return filePath;
	});

	handle("prepare_recording_file", async (args) => {
		const { fileName } = args as { fileName: string };
		const state = getState();
		const dir = getRecordingsDir(state, getDefaultRecordingsDir());
		await fs.promises.mkdir(dir, { recursive: true });
		const filePath = path.join(dir, fileName);
		await fs.promises.writeFile(filePath, Buffer.alloc(0));
		return filePath;
	});

	handle("append_recording_data", async (args) => {
		const { path: filePath, data } = args as { path: string; data: number[] };
		if (!isWithinAllowedDirs(filePath)) {
			throw new Error("Access denied: path is outside allowed directories");
		}
		await fs.promises.appendFile(filePath, Buffer.from(data));
		return null;
	});

	handle("replace_recording_data", async (args) => {
		const { path: filePath, data } = args as { path: string; data: number[] };
		await fs.promises.writeFile(filePath, Buffer.from(data));
		return filePath;
	});

	handle("delete_recording_file", async (args) => {
		const { path: filePath } = args as { path: string };
		try {
			await fs.promises.unlink(filePath);
		} catch (err: unknown) {
			if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
		}
		return null;
	});

	handle("store_recording_asset", async (args) => {
		const { assetData, fileName } = args as { assetData: number[]; fileName: string };
		const state = getState();
		const dir = getRecordingsDir(state, getDefaultRecordingsDir());
		await fs.promises.mkdir(dir, { recursive: true });
		const filePath = path.join(dir, fileName);
		await fs.promises.writeFile(filePath, Buffer.from(assetData));
		return filePath;
	});

	handle("get_recorded_video_path", () => {
		return getState().currentVideoPath;
	});

	handle("set_current_video_path", (args) => {
		const { path: filePath } = args as { path: string };
		setState((s) => {
			s.currentVideoPath = filePath;
		});
		return null;
	});

	handle("get_current_video_path", () => {
		return getState().currentVideoPath;
	});

	handle("clear_current_video_path", () => {
		setState((s) => {
			s.currentVideoPath = null;
		});
		return null;
	});

	handle("get_current_recording_session", () => {
		return getState().currentRecordingSession;
	});

	handle("set_current_recording_session", (args) => {
		const { session } = args as { session: RecordingSession };
		setState((s) => {
			s.currentRecordingSession = session;
		});
		return null;
	});
}
