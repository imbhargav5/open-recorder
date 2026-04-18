/**
 * Window management IPC handlers.
 */

import { BrowserWindow, app, screen } from "electron";
import path from "node:path";
import type { AppState } from "../state.js";

/** Returns a BrowserWindow by its custom windowLabel property. */
function getWindowByLabel(label: string): BrowserWindow | undefined {
	return BrowserWindow.getAllWindows().find(
		(w) => (w as BrowserWindow & { windowLabel?: string }).windowLabel === label,
	);
}

/** Returns true for editor window labels (editor, editor-1, editor-2, …). */
export function isEditorWindowLabel(label: string): boolean {
	return label === "editor" || label.startsWith("editor-");
}

function nextEditorWindowLabel(): string {
	let index = 1;
	while (true) {
		const label = `editor-${index}`;
		if (!getWindowByLabel(label)) return label;
		index++;
	}
}

function buildEditorWindowUrl(baseUrl: string, query?: string): string {
	const normalized = query
		?.trim()
		.replace(/^\?+/, "");

	if (!normalized) return `${baseUrl}?windowType=editor`;
	return `${baseUrl}?${normalized}`;
}

interface CreateWindowOpts {
	label: string;
	url: string;
	width: number;
	height: number;
	minWidth?: number;
	minHeight?: number;
	resizable?: boolean;
	transparent?: boolean;
	alwaysOnTop?: boolean;
	skipTaskbar?: boolean;
	frame?: boolean;
	preloadPath: string;
}

function createWindow(opts: CreateWindowOpts): BrowserWindow {
	const win = new BrowserWindow({
		width: opts.width,
		height: opts.height,
		minWidth: opts.minWidth,
		minHeight: opts.minHeight,
		resizable: opts.resizable ?? true,
		transparent: opts.transparent ?? false,
		alwaysOnTop: opts.alwaysOnTop ?? false,
		skipTaskbar: opts.skipTaskbar ?? false,
		frame: opts.frame ?? true,
		backgroundColor: "#000000",
		webPreferences: {
			nodeIntegration: false,
			contextIsolation: true,
			sandbox: false,
			preload: opts.preloadPath,
		},
	});

	(win as BrowserWindow & { windowLabel: string }).windowLabel = opts.label;
	win.loadURL(opts.url);
	return win;
}

export function registerWindowMgmtHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
	getRendererUrl: () => string,
	preloadPath: string,
): void {
	handle("switch_to_editor", async (args) => {
		const { query } = (args as { query?: string }) ?? {};

		// Hide HUD
		const hud = getWindowByLabel("hud-overlay");
		if (hud) hud.hide();

		// Close source selector
		const selector = getWindowByLabel("source-selector");
		if (selector) selector.close();

		const label = nextEditorWindowLabel();
		const url = buildEditorWindowUrl(getRendererUrl(), query);

		createWindow({
			label,
			url,
			width: 1200,
			height: 800,
			minWidth: 800,
			minHeight: 600,
			resizable: true,
			preloadPath,
		});

		return null;
	});

	handle("switch_to_image_editor", async () => {
		const hud = getWindowByLabel("hud-overlay");
		if (hud) hud.hide();

		const selector = getWindowByLabel("source-selector");
		if (selector) selector.close();

		const existing = getWindowByLabel("image-editor");
		if (existing) {
			existing.show();
			existing.focus();
		} else {
			const url = `${getRendererUrl()}?windowType=image-editor`;
			createWindow({
				label: "image-editor",
				url,
				width: 1100,
				height: 750,
				minWidth: 800,
				minHeight: 550,
				preloadPath,
			});
		}

		return null;
	});

	handle("open_source_selector", async (args) => {
		const { tab } = (args as { tab?: string }) ?? {};

		// Close existing to reopen with new tab param
		const existing = getWindowByLabel("source-selector");
		if (existing) existing.destroy();

		const tabParam = tab ?? "";
		const url = `${getRendererUrl()}?windowType=source-selector&tab=${tabParam}`;

		createWindow({
			label: "source-selector",
			url,
			width: 660,
			height: 820,
			minWidth: 400,
			minHeight: 300,
			transparent: false,
			alwaysOnTop: true,
			skipTaskbar: true,
			frame: true,
			preloadPath,
		});

		return null;
	});

	handle("close_source_selector", () => {
		const selector = getWindowByLabel("source-selector");
		if (selector) selector.destroy();
		return null;
	});

	handle("hud_overlay_show", () => {
		const hud = getWindowByLabel("hud-overlay");
		if (hud) {
			hud.show();
			hud.focus();
		}
		return null;
	});

	handle("hud_overlay_hide", () => {
		const hud = getWindowByLabel("hud-overlay");
		if (hud) hud.hide();
		return null;
	});

	handle("hud_overlay_close", () => {
		BrowserWindow.getAllWindows().forEach((w) => w.close());
		return null;
	});

	handle("start_hud_overlay_drag", () => {
		// The renderer handles drag via CSS -webkit-app-region: drag
		// For non-frameless windows or as a fallback, we'd call startDrag on the focused window.
		return null;
	});

	const HUD_WIDTH = 780;
	const HUD_HEIGHT = 155;
	const ONBOARDING_WIDTH = 480;
	const ONBOARDING_HEIGHT = 360;

	handle("resize_hud_to_onboarding", () => {
		const hud = getWindowByLabel("hud-overlay");
		if (hud) {
			hud.setSize(ONBOARDING_WIDTH, ONBOARDING_HEIGHT);
			hud.center();
		}
		return null;
	});

	handle("restore_hud_size", () => {
		const hud = getWindowByLabel("hud-overlay");
		if (hud) {
			hud.setSize(HUD_WIDTH, HUD_HEIGHT);
			const primary = screen.getPrimaryDisplay();
			const { width, height } = primary.workAreaSize;
			const x = Math.round((width - HUD_WIDTH) / 2);
			const y = Math.round(height - HUD_HEIGHT - 5);
			hud.setPosition(x, y);
		}
		return null;
	});

	handle("set_has_unsaved_changes", (args) => {
		const { hasChanges } = args as { hasChanges: boolean };
		// We track this per-window using the sender's window label.
		// For simplicity, update global state — the caller must pass the label.
		const { windowLabel } = (args as { hasChanges: boolean; windowLabel?: string });
		if (windowLabel && isEditorWindowLabel(windowLabel)) {
			setState((s) => {
				if (hasChanges) {
					s.unsavedEditorWindows.add(windowLabel);
				} else {
					s.unsavedEditorWindows.delete(windowLabel);
				}
				s.hasUnsavedChanges = s.unsavedEditorWindows.size > 0;
			});
		}
		return null;
	});
}
