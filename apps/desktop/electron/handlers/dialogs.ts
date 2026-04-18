/**
 * File dialog IPC handlers.
 */

import fs from "node:fs";
import { dialog } from "electron";
import type { AppState } from "../state.js";

export function registerDialogHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
): void {
	handle("save_exported_video", async (args) => {
		const { videoData, fileName } = args as { videoData: number[]; fileName: string };

		const result = await dialog.showSaveDialog({
			defaultPath: fileName,
			filters: [{ name: "Video", extensions: ["mp4", "mov", "webm"] }],
		});

		if (result.canceled || !result.filePath) return null;

		await fs.promises.writeFile(result.filePath, Buffer.from(videoData));
		return result.filePath;
	});

	handle("save_screenshot_file", async (args) => {
		const { imageData, fileName } = args as { imageData: number[]; fileName: string };

		const result = await dialog.showSaveDialog({
			defaultPath: fileName,
			filters: [{ name: "Image", extensions: ["png", "jpg", "jpeg"] }],
		});

		if (result.canceled || !result.filePath) return null;

		await fs.promises.writeFile(result.filePath, Buffer.from(imageData));
		return result.filePath;
	});

	handle("open_video_file_picker", async () => {
		const result = await dialog.showOpenDialog({
			properties: ["openFile"],
			filters: [{ name: "Video", extensions: ["mp4", "mov", "webm", "mkv"] }],
		});

		if (result.canceled || result.filePaths.length === 0) return null;
		return result.filePaths[0];
	});

	handle("save_project_file", async (args) => {
		const { data, suggestedName, existingPath } = args as {
			data: string;
			suggestedName?: string;
			existingPath?: string;
		};

		let savePath: string | null = existingPath ?? null;

		if (!savePath) {
			const fileName = suggestedName ?? "Untitled.openrecorder";
			const result = await dialog.showSaveDialog({
				defaultPath: fileName,
				filters: [{ name: "Open Recorder Project", extensions: ["openrecorder"] }],
			});
			if (result.canceled || !result.filePath) return null;
			savePath = result.filePath;
		}

		await fs.promises.writeFile(savePath, data, "utf-8");
		setState((s) => {
			s.currentProjectPath = savePath;
			s.hasUnsavedChanges = false;
		});

		return savePath;
	});

	handle("load_project_file", async () => {
		const result = await dialog.showOpenDialog({
			properties: ["openFile"],
			filters: [{ name: "Open Recorder Project", extensions: ["openrecorder"] }],
		});

		if (result.canceled || result.filePaths.length === 0) return null;

		const filePath = result.filePaths[0];
		const raw = await fs.promises.readFile(filePath, "utf-8");
		const projectData = JSON.parse(raw);

		setState((s) => {
			s.currentProjectPath = filePath;
			s.hasUnsavedChanges = false;
		});

		return { data: projectData, filePath };
	});

	handle("load_current_project_file", async () => {
		const state = getState();
		const filePath = state.currentProjectPath;
		if (!filePath) return null;

		try {
			const raw = await fs.promises.readFile(filePath, "utf-8");
			const projectData = JSON.parse(raw);
			return { data: projectData, filePath };
		} catch {
			return null;
		}
	});
}
