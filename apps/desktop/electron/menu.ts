/**
 * Application menu setup.
 * Mirrors src-tauri/src/menu.rs.
 */

import { Menu, app } from "electron";
import type { AppState } from "./state.js";

export function setupMenu(
	emit: (channel: string, payload: unknown) => void,
): void {
	const isMac = process.platform === "darwin";

	const template: Electron.MenuItemConstructorOptions[] = [
		...(isMac
			? [
					{
						label: app.name,
						submenu: [
							{ role: "about" as const },
							{ type: "separator" as const },
							{ role: "services" as const },
							{ type: "separator" as const },
							{ role: "hide" as const },
							{ role: "hideOthers" as const },
							{ role: "unhide" as const },
							{ type: "separator" as const },
							{ role: "quit" as const },
						],
					},
				]
			: []),
		{
			label: "File",
			submenu: [
				{
					label: "Open Video…",
					accelerator: "CmdOrCtrl+O",
					click: () => emit("menu-open-video-file", null),
				},
				{ type: "separator" },
				{
					label: "Load Project…",
					accelerator: "CmdOrCtrl+Shift+O",
					click: () => emit("menu-load-project", null),
				},
				{
					label: "Save Project",
					accelerator: "CmdOrCtrl+S",
					click: () => emit("menu-save-project", null),
				},
				{
					label: "Save Project As…",
					accelerator: "CmdOrCtrl+Shift+S",
					click: () => emit("menu-save-project-as", null),
				},
				{ type: "separator" },
				isMac
					? { role: "close" as const }
					: { role: "quit" as const },
			],
		},
		{
			label: "Edit",
			submenu: [
				{ role: "undo" as const },
				{ role: "redo" as const },
				{ type: "separator" as const },
				{ role: "cut" as const },
				{ role: "copy" as const },
				{ role: "paste" as const },
				...(isMac
					? [{ role: "pasteAndMatchStyle" as const }, { role: "delete" as const }, { role: "selectAll" as const }]
					: [{ role: "delete" as const }, { type: "separator" as const }, { role: "selectAll" as const }]),
			],
		},
		{
			label: "View",
			submenu: [
				{ role: "reload" as const },
				{ role: "forceReload" as const },
				{ role: "toggleDevTools" as const },
				{ type: "separator" as const },
				{ role: "togglefullscreen" as const },
			],
		},
		{
			label: "Help",
			submenu: [
				{
					label: "Check for Updates…",
					click: () => emit("menu-check-updates", null),
				},
			],
		},
	];

	const menu = Menu.buildFromTemplate(template);
	Menu.setApplicationMenu(menu);
}
