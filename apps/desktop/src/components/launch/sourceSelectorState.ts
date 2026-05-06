export interface AreaSelection {
	x: number;
	y: number;
	width: number;
	height: number;
	displayId: number;
	displayBounds: {
		x: number;
		y: number;
		width: number;
		height: number;
	};
}

export interface DesktopSource {
	id: string;
	name: string;
	thumbnail: string | null;
	display_id: string;
	appIcon: string | null;
	originalName: string;
	sourceType: "screen" | "window" | "area";
	appName?: string;
	windowTitle?: string;
	windowId?: number;
	captureSourceId?: string;
	areaSelection?: AreaSelection;
}

export function parseSourceMetadata(source: ProcessedDesktopSource) {
	const sourceType: "screen" | "window" | "area" =
		source.sourceType ??
		(source.source_type as "screen" | "window" | "area" | undefined) ??
		(source.id.startsWith("window:") ? "window" : "screen");

	const appName = source.appName ?? source.app_name;
	const windowTitle = source.windowTitle ?? source.window_title;

	if (sourceType === "area") {
		return {
			sourceType,
			appName: undefined,
			windowTitle: undefined,
			displayName: source.name,
		};
	}

	if (sourceType === "window" && (appName || windowTitle)) {
		return {
			sourceType,
			appName,
			windowTitle: windowTitle ?? source.name,
			displayName: windowTitle ?? source.name,
		};
	}

	if (sourceType === "window") {
		const [appNamePart, ...windowTitleParts] = source.name.split(" — ");
		const parsedAppName = appNamePart?.trim() || undefined;
		const parsedWindowTitle = windowTitleParts.join(" — ").trim() || source.name.trim();

		return {
			sourceType,
			appName: parsedAppName,
			windowTitle: parsedWindowTitle,
			displayName: parsedWindowTitle,
		};
	}

	return {
		sourceType,
		appName: undefined,
		windowTitle: undefined,
		displayName: source.name,
	};
}

export function mapSources(rawSources: ProcessedDesktopSource[]): DesktopSource[] {
	return rawSources.map((source) => {
		const metadata = parseSourceMetadata(source);

		const desktopSource: DesktopSource = {
			id: source.id,
			name: metadata.displayName,
			thumbnail: source.thumbnail ?? null,
			display_id: source.display_id ?? source.displayId ?? "",
			appIcon: source.appIcon ?? source.app_icon ?? null,
			originalName: source.name,
			sourceType: metadata.sourceType,
			appName: metadata.appName,
			windowTitle: metadata.windowTitle,
			windowId: source.windowId ?? source.window_id,
		};

		if (source.captureSourceId) {
			desktopSource.captureSourceId = source.captureSourceId;
		}

		if (source.areaSelection) {
			desktopSource.areaSelection = source.areaSelection;
		}

		return desktopSource;
	});
}

export function mergeSources(
	existingSources: DesktopSource[],
	incomingSources: DesktopSource[],
): DesktopSource[] {
	const incomingById = new Map(incomingSources.map((source) => [source.id, source]));
	const mergedSources = existingSources.map((source) => {
		const incoming = incomingById.get(source.id);
		if (!incoming) return source;
		return {
			...source,
			...incoming,
			thumbnail: incoming.thumbnail ?? source.thumbnail,
			appIcon: incoming.appIcon ?? source.appIcon,
		};
	});

	for (const source of incomingSources) {
		if (!existingSources.some((existing) => existing.id === source.id)) {
			mergedSources.push(source);
		}
	}

	return mergedSources;
}
