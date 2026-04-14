export function getSelectedSourceName(source: unknown) {
	if (!source || typeof source !== "object") {
		return undefined;
	}

	const candidate = source as {
		name?: unknown;
		windowTitle?: unknown;
		window_title?: unknown;
	};
	if (typeof candidate.name === "string" && candidate.name.trim()) {
		return candidate.name;
	}
	if (typeof candidate.windowTitle === "string" && candidate.windowTitle.trim()) {
		return candidate.windowTitle;
	}
	if (typeof candidate.window_title === "string" && candidate.window_title.trim()) {
		return candidate.window_title;
	}
	return undefined;
}

export function resolveSelectedSourceState(source: unknown) {
	const selectedSourceName = getSelectedSourceName(source) ?? "Main Display";

	return {
		selectedSource: selectedSourceName,
		hasSelectedSource: true,
	};
}
