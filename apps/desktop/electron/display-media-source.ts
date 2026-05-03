import type { SelectedSource } from "./state.js";

type CapturerSource = Pick<Electron.DesktopCapturerSource, "display_id" | "id" | "name">;

function isScreenSource(source: Pick<CapturerSource, "id">): boolean {
	return source.id.startsWith("screen:");
}

function isWindowSource(source: Pick<CapturerSource, "id">): boolean {
	return source.id.startsWith("window:");
}

function selectedSourceType(source: SelectedSource): "screen" | "window" {
	if (source.sourceType === "window" || source.id.startsWith("window:")) {
		return "window";
	}
	return "screen";
}

function selectedDisplayId(source: SelectedSource): string | undefined {
	const displayId = source.displayId ?? source.display_id;
	if (typeof displayId !== "string") return undefined;

	const trimmed = displayId.trim();
	return trimmed.length > 0 ? trimmed : undefined;
}

export function resolveDisplayMediaSource(
	selectedSource: SelectedSource | null | undefined,
	sources: CapturerSource[],
): CapturerSource | undefined {
	if (selectedSource) {
		if (selectedSourceType(selectedSource) === "screen") {
			const displayId = selectedDisplayId(selectedSource);
			if (displayId) {
				const displayMatch = sources.find(
					(source) => isScreenSource(source) && source.display_id === displayId,
				);
				if (displayMatch) return displayMatch;
			}
		}

		const idMatch = sources.find((source) => source.id === selectedSource.id);
		if (idMatch) return idMatch;

		if (selectedSourceType(selectedSource) === "window" && selectedSource.windowId !== undefined) {
			const windowPrefix = `window:${selectedSource.windowId}:`;
			const windowMatch = sources.find(
				(source) => isWindowSource(source) && source.id.startsWith(windowPrefix),
			);
			if (windowMatch) return windowMatch;
		}
	}

	return sources.find(isScreenSource) ?? sources[0];
}
