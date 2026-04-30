/**
 * Screenshot IPC handlers.
 * Mirrors src-tauri/src/commands/screenshot.rs.
 */

import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { AppState } from "../state.js";

const execFileAsync = promisify(execFile);

export function registerScreenshotHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
	getDefaultScreenshotsDir: () => string,
): void {
	handle("take_screenshot", async (args) => {
		const { captureType, windowId } = args as {
			captureType: string;
			windowId?: number;
		};

		const dir = getDefaultScreenshotsDir();
		await fs.promises.mkdir(dir, { recursive: true });

		const timestamp = Math.floor(Date.now() / 1000);
		const filename = `screenshot-${timestamp}.png`;
		const screenshotPath = path.join(dir, filename);

		if (process.platform === "darwin") {
			const cmdArgs = ["-x"];

			if (captureType === "window" && windowId !== undefined) {
				cmdArgs.push(`-l${windowId}`);
			} else if (captureType === "area") {
				cmdArgs.push("-i");
			}

			cmdArgs.push(screenshotPath);

			try {
				await execFileAsync("screencapture", cmdArgs);
			} catch {
				throw new Error("Screenshot capture failed or was cancelled");
			}

			if (!fs.existsSync(screenshotPath)) {
				throw new Error("Screenshot was cancelled");
			}
		} else {
			throw new Error("Screenshot capture is only supported on macOS in this build");
		}

		setState((s) => {
			s.currentScreenshotPath = screenshotPath;
		});

		return screenshotPath;
	});

	handle("get_current_screenshot_path", () => {
		return getState().currentScreenshotPath;
	});

	handle("set_current_screenshot_path", (args) => {
		const { path: screenshotPath } = args as { path: string | null };
		setState((s) => {
			s.currentScreenshotPath = screenshotPath;
		});
		return null;
	});
}
