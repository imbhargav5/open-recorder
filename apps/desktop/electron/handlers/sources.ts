/**
 * Screen/window source IPC handlers.
 * Uses Electron's desktopCapturer API for source enumeration.
 */

import { desktopCapturer, BrowserWindow } from "electron";
import type { AppState, SelectedSource } from "../state.js";

interface SourceListOptions {
	types?: string[];
	thumbnailSize?: { width?: number; height?: number };
	withThumbnails?: boolean;
	timeoutMs?: number;
}

function electronSourceToSelectedSource(src: Electron.DesktopCapturerSource): SelectedSource {
	const isScreen = src.id.startsWith("screen:");
	return {
		id: src.id,
		name: src.name,
		sourceType: isScreen ? "screen" : "window",
		thumbnail: src.thumbnail.isEmpty() ? undefined : src.thumbnail.toDataURL(),
		displayId: isScreen ? src.display_id : undefined,
		appIcon: src.appIcon && !src.appIcon.isEmpty() ? src.appIcon.toDataURL() : undefined,
	};
}

function fallbackSource(): SelectedSource {
	return {
		id: "screen:0:0",
		name: "Main Display",
		sourceType: "screen",
		displayId: "0",
	};
}

export function registerSourceHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
): void {
	handle("get_sources", async (args) => {
		const { opts } = (args as { opts?: SourceListOptions }) ?? {};
		const types = opts?.types ?? ["screen", "window"];
		const wantScreens = types.includes("screen");
		const wantWindows = types.includes("window");
		const withThumbnails = opts?.withThumbnails ?? false;
		const thumbWidth = opts?.thumbnailSize?.width ?? 320;
		const thumbHeight = opts?.thumbnailSize?.height ?? 180;

		const captureTypes: ("screen" | "window")[] = [];
		if (wantScreens) captureTypes.push("screen");
		if (wantWindows) captureTypes.push("window");

		if (captureTypes.length === 0) return [];

		try {
			const sources = await desktopCapturer.getSources({
				types: captureTypes,
				thumbnailSize: withThumbnails
					? { width: thumbWidth, height: thumbHeight }
					: { width: 0, height: 0 },
				fetchWindowIcons: wantWindows,
			});

			let result = sources.map(electronSourceToSelectedSource);

			// Apply type filter
			if (types.length > 0) {
				result = result.filter((s) => {
					if (s.sourceType) return types.includes(s.sourceType);
					return true;
				});
			}

			if (wantWindows) {
				const windowSources = result.filter((s) => s.sourceType === "window");
				setState((s) => {
					s.cachedWindowSources = windowSources;
				});
			}

			return result.length > 0 ? result : [fallbackSource()];
		} catch (err) {
			console.error("[get_sources] Failed to enumerate sources:", err);
			return [fallbackSource()];
		}
	});

	handle("get_selected_source", () => {
		return getState().selectedSource ?? fallbackSource();
	});

	handle("select_source", (args) => {
		const { source } = args as { source: SelectedSource };
		setState((s) => {
			s.selectedSource = source;
		});
		// Close source-selector window if open
		const allWindows = BrowserWindow.getAllWindows();
		for (const win of allWindows) {
			if ((win as BrowserWindow & { windowLabel?: string }).windowLabel === "source-selector") {
				win.close();
			}
		}
		return null;
	});

	handle("flash_selected_screen", () => {
		// Screen flash on selection — visual effect, no-op stub
		return null;
	});
}
