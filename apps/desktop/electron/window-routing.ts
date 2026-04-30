import { BrowserWindow, type WebContents } from "electron";

type LabeledWindow = BrowserWindow & { windowLabel?: string };

function asLabeledWindow(window: BrowserWindow): LabeledWindow {
	return window as LabeledWindow;
}

export function getWindowLabel(window?: BrowserWindow | null): string {
	if (!window || window.isDestroyed()) return "";
	return asLabeledWindow(window).windowLabel ?? "";
}

export function getWindowByLabel(label: string): BrowserWindow | undefined {
	return BrowserWindow.getAllWindows().find((window) => getWindowLabel(window) === label);
}

export function getWindowFromWebContents(webContents: WebContents): BrowserWindow | null {
	return BrowserWindow.fromWebContents(webContents);
}

export function isEditorWindowLabel(label: string): boolean {
	return label === "editor" || label.startsWith("editor-");
}

export function sendToWindow(
	window: BrowserWindow | null | undefined,
	channel: string,
	payload: unknown,
): boolean {
	if (!window || window.isDestroyed()) return false;
	window.webContents.send(channel, payload);
	return true;
}

function firstWindow(
	predicate: (window: BrowserWindow, label: string) => boolean,
): BrowserWindow | undefined {
	for (const window of BrowserWindow.getAllWindows()) {
		if (window.isDestroyed()) continue;
		const label = getWindowLabel(window);
		if (predicate(window, label)) {
			return window;
		}
	}
	return undefined;
}

export function resolveEditorWindow(sourceWindow?: BrowserWindow | null): BrowserWindow | undefined {
	if (sourceWindow && isEditorWindowLabel(getWindowLabel(sourceWindow))) {
		return sourceWindow;
	}

	const focusedWindow = BrowserWindow.getFocusedWindow();
	if (focusedWindow && isEditorWindowLabel(getWindowLabel(focusedWindow))) {
		return focusedWindow;
	}

	return firstWindow((_window, label) => isEditorWindowLabel(label));
}

export function resolveHudWindow(): BrowserWindow | undefined {
	return getWindowByLabel("hud-overlay");
}

export function resolveProjectLoadWindow(
	sourceWindow?: BrowserWindow | null,
): BrowserWindow | undefined {
	return resolveEditorWindow(sourceWindow) ?? resolveHudWindow();
}

export function resolveUpdateWindow(
	sourceWindow?: BrowserWindow | null,
): BrowserWindow | undefined {
	const sourceLabel = getWindowLabel(sourceWindow);
	if (sourceWindow && sourceLabel !== "hud-overlay" && sourceLabel !== "source-selector") {
		return sourceWindow;
	}

	const focusedWindow = BrowserWindow.getFocusedWindow();
	const focusedLabel = getWindowLabel(focusedWindow);
	if (focusedWindow && focusedLabel !== "hud-overlay" && focusedLabel !== "source-selector") {
		return focusedWindow;
	}

	return firstWindow((_window, label) => label !== "hud-overlay" && label !== "source-selector");
}
