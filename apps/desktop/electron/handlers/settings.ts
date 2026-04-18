/**
 * Settings IPC handlers.
 */

import fs from "node:fs";
import path from "node:path";
import { dialog } from "electron";
import type { AppState, ShortcutConfig } from "../state.js";

export function registerSettingsHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
	getDefaultRecordingsDir: () => string,
	getConfigDir: () => string,
): void {
	handle("get_recordings_directory", () => {
		const state = getState();
		return state.customRecordingsDir ?? getDefaultRecordingsDir();
	});

	handle("choose_recordings_directory", async () => {
		const result = await dialog.showOpenDialog({
			properties: ["openDirectory"],
		});
		if (result.canceled || result.filePaths.length === 0) return null;

		const chosen = result.filePaths[0];
		setState((s) => {
			s.customRecordingsDir = chosen;
		});

		// Persist to settings.json
		const configDir = getConfigDir();
		await fs.promises.mkdir(configDir, { recursive: true });
		const settingsPath = path.join(configDir, "settings.json");
		const settings = { recordingsDirectory: chosen };
		await fs.promises.writeFile(settingsPath, JSON.stringify(settings, null, 2));

		return chosen;
	});

	handle("get_shortcuts", async () => {
		// Return cached value if available
		const cached = getState().shortcuts;
		if (cached !== null) return cached;

		const configDir = getConfigDir();
		const shortcutsPath = path.join(configDir, "shortcuts.json");

		try {
			const data = await fs.promises.readFile(shortcutsPath, "utf-8");
			const shortcuts: ShortcutConfig = JSON.parse(data);
			setState((s) => {
				s.shortcuts = shortcuts;
			});
			return shortcuts;
		} catch {
			return null;
		}
	});

	handle("save_shortcuts", async (args) => {
		const { shortcuts } = args as { shortcuts: ShortcutConfig };
		const configDir = getConfigDir();
		await fs.promises.mkdir(configDir, { recursive: true });
		const shortcutsPath = path.join(configDir, "shortcuts.json");
		await fs.promises.writeFile(shortcutsPath, JSON.stringify(shortcuts, null, 2));
		setState((s) => {
			s.shortcuts = shortcuts;
		});
		return null;
	});
}
