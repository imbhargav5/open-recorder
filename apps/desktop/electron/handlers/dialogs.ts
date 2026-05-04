/**
 * File dialog IPC handlers.
 * Mirrors src-tauri/src/commands/dialogs.rs.
 */

import fs from "node:fs";
import path from "node:path";
import { dialog } from "electron";
import {
	deriveProjectMetadata,
	ProjectLibrary,
	resolveAutomaticProjectPath,
} from "../project-library.js";
import type { AppState } from "../state.js";

function getRecordingsDir(state: AppState, defaultDir: string): string {
	return state.customRecordingsDir ?? defaultDir;
}

function ensureProjectExtension(filePath: string): string {
	return path.extname(filePath) ? filePath : `${filePath}.openrecorder`;
}

export function registerDialogHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
	getDefaultRecordingsDir: () => string,
	getConfigDir: () => string,
): { close: () => void } {
	let projectLibrary: ProjectLibrary | null = null;
	const getProjectLibrary = () => {
		projectLibrary ??= new ProjectLibrary(getConfigDir());
		return projectLibrary;
	};

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
		const { data, suggestedName, existingPath, forceSaveAs } = args as {
			data: string;
			suggestedName?: string;
			existingPath?: string;
			forceSaveAs?: boolean;
		};

		let projectData: unknown;
		try {
			projectData = JSON.parse(data);
		} catch {
			projectData = null;
		}

		let savePath: string | null = !forceSaveAs ? (existingPath ?? null) : null;

		if (forceSaveAs) {
			const fileName = suggestedName ?? "Untitled.openrecorder";
			const result = await dialog.showSaveDialog({
				defaultPath: fileName,
				filters: [{ name: "Open Recorder Project", extensions: ["openrecorder"] }],
			});
			if (result.canceled || !result.filePath) return null;
			savePath = ensureProjectExtension(result.filePath);
		} else if (!savePath) {
			savePath = await resolveAutomaticProjectPath(
				getRecordingsDir(getState(), getDefaultRecordingsDir()),
				suggestedName,
			);
		}

		await fs.promises.mkdir(path.dirname(savePath), { recursive: true });
		await fs.promises.writeFile(savePath, data, "utf-8");
		getProjectLibrary().upsertProject(savePath, deriveProjectMetadata(projectData, savePath));
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
		getProjectLibrary().markOpened(filePath, deriveProjectMetadata(projectData, filePath));

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
			getProjectLibrary().markOpened(filePath, deriveProjectMetadata(projectData, filePath));
			return { data: projectData, filePath };
		} catch {
			return null;
		}
	});

	handle("list_projects", () => {
		return getProjectLibrary().listProjects();
	});

	handle("open_project_at_path", async (args) => {
		const { path: filePath } = args as { path: string };
		const raw = await fs.promises.readFile(filePath, "utf-8");
		const projectData = JSON.parse(raw);
		getProjectLibrary().markOpened(filePath, deriveProjectMetadata(projectData, filePath));

		setState((s) => {
			s.currentProjectPath = filePath;
			s.hasUnsavedChanges = false;
		});

		return { data: projectData, filePath };
	});

	handle("remove_project_from_recents", (args) => {
		const { path: filePath } = args as { path: string };
		getProjectLibrary().removeProject(filePath);
		return null;
	});

	return {
		close: () => {
			projectLibrary?.close();
			projectLibrary = null;
		},
	};
}
