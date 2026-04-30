/**
 * Application menu setup.
 * Mirrors src-tauri/src/menu.rs.
 */

import { Menu, app, type BrowserWindow, type MenuItemConstructorOptions } from "electron";
import {
	resolveEditorWindow,
	resolveHudWindow,
	resolveProjectLoadWindow,
	resolveUpdateWindow,
	sendToWindow,
} from "./window-routing.js";

function sendMenuEvent(
	channel: string,
	resolveTarget: (sourceWindow?: BrowserWindow | null) => BrowserWindow | undefined,
	sourceWindow?: BrowserWindow | null,
): void {
	sendToWindow(resolveTarget(sourceWindow), channel, null);
}

export function setupMenu(): void {
	const isMac = process.platform === "darwin";

	const template: MenuItemConstructorOptions[] = [
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
					click: (_item, window) => sendMenuEvent("menu-open-video-file", resolveHudWindow, window),
				},
				{ type: "separator" },
				{
					label: "Load Project…",
					accelerator: "CmdOrCtrl+Shift+O",
					click: (_item, window) =>
						sendMenuEvent("menu-load-project", resolveProjectLoadWindow, window),
				},
				{
					label: "Save Project",
					accelerator: "CmdOrCtrl+S",
					click: (_item, window) =>
						sendMenuEvent("menu-save-project", resolveEditorWindow, window),
				},
				{
					label: "Save Project As…",
					accelerator: "CmdOrCtrl+Shift+S",
					click: (_item, window) =>
						sendMenuEvent("menu-save-project-as", resolveEditorWindow, window),
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
					click: (_item, window) =>
						sendMenuEvent("menu-check-updates", resolveUpdateWindow, window),
				},
			],
		},
	];

	const menu = Menu.buildFromTemplate(template);
	Menu.setApplicationMenu(menu);
}
