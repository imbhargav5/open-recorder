export type FacecamShape = "circle" | "square";
export type FacecamAnchor = "bottom-right" | "bottom-left" | "top-right" | "top-left" | "custom";

export interface FacecamSettings {
	enabled: boolean;
	shape: FacecamShape;
	size: number;
	cornerRadius: number;
	borderWidth: number;
	borderColor: string;
	margin: number;
	anchor: FacecamAnchor;
	customX?: number;
	customY?: number;
}

export interface RecordingSession {
	screenVideoPath: string;
	facecamVideoPath?: string;
	facecamOffsetMs?: number;
	facecamSettings?: FacecamSettings;
	sourceName?: string;
	showCursorOverlay?: boolean;
}

export interface PersistedRecordingSession extends RecordingSession {
	version: number;
}

export const RECORDING_SESSION_VERSION = 1;
export const DEFAULT_FACECAM_BORDER_COLOR = "#FFFFFF";

export const FACECAM_ANCHORS: FacecamAnchor[] = [
	"top-left",
	"top-right",
	"bottom-left",
	"bottom-right",
];

export function createDefaultFacecamSettings(enabled = false): FacecamSettings {
	return {
		enabled,
		shape: "circle",
		size: 22,
		cornerRadius: 24,
		borderWidth: 4,
		borderColor: DEFAULT_FACECAM_BORDER_COLOR,
		margin: 4,
		anchor: "bottom-right",
	};
}

export function clampFacecamSetting(value: number, min: number, max: number) {
	if (!Number.isFinite(value)) {
		return min;
	}

	return Math.min(max, Math.max(min, value));
}

const VALID_FACECAM_ANCHORS: ReadonlySet<string> = new Set<FacecamAnchor>([
	"bottom-right",
	"bottom-left",
	"top-right",
	"top-left",
	"custom",
]);

function isValidFacecamAnchor(value: unknown): value is FacecamAnchor {
	return typeof value === "string" && VALID_FACECAM_ANCHORS.has(value);
}

export function normalizeFacecamSettings(
	candidate: Partial<FacecamSettings> | null | undefined,
	options: { defaultEnabled?: boolean } = {},
): FacecamSettings {
	const fallback = createDefaultFacecamSettings(options.defaultEnabled ?? false);

	const anchor = isValidFacecamAnchor(candidate?.anchor) ? candidate.anchor : fallback.anchor;

	const result: FacecamSettings = {
		enabled: typeof candidate?.enabled === "boolean" ? candidate.enabled : fallback.enabled,
		shape: candidate?.shape === "square" ? "square" : fallback.shape,
		size: clampFacecamSetting(
			typeof candidate?.size === "number" ? candidate.size : fallback.size,
			12,
			40,
		),
		cornerRadius: clampFacecamSetting(
			typeof candidate?.cornerRadius === "number" ? candidate.cornerRadius : fallback.cornerRadius,
			0,
			50,
		),
		borderWidth: clampFacecamSetting(
			typeof candidate?.borderWidth === "number" ? candidate.borderWidth : fallback.borderWidth,
			0,
			16,
		),
		borderColor:
			typeof candidate?.borderColor === "string" && candidate.borderColor.trim()
				? candidate.borderColor
				: fallback.borderColor,
		margin: clampFacecamSetting(
			typeof candidate?.margin === "number" ? candidate.margin : fallback.margin,
			0,
			12,
		),
		anchor,
	};

	if (anchor === "custom") {
		result.customX = clampFacecamSetting(
			typeof candidate?.customX === "number" ? candidate.customX : 0.5,
			0,
			1,
		);
		result.customY = clampFacecamSetting(
			typeof candidate?.customY === "number" ? candidate.customY : 0.5,
			0,
			1,
		);
	}

	return result;
}

export function normalizeRecordingSession(
	candidate: Partial<RecordingSession> | null | undefined,
): RecordingSession | null {
	if (
		!candidate ||
		typeof candidate.screenVideoPath !== "string" ||
		!candidate.screenVideoPath.trim()
	) {
		return null;
	}

	const facecamVideoPath =
		typeof candidate.facecamVideoPath === "string" && candidate.facecamVideoPath.trim()
			? candidate.facecamVideoPath
			: undefined;
	const facecamOffsetMs =
		typeof candidate.facecamOffsetMs === "number" && Number.isFinite(candidate.facecamOffsetMs)
			? candidate.facecamOffsetMs
			: undefined;

	return {
		screenVideoPath: candidate.screenVideoPath,
		facecamVideoPath,
		facecamOffsetMs,
		facecamSettings: normalizeFacecamSettings(candidate.facecamSettings, {
			defaultEnabled: Boolean(facecamVideoPath),
		}),
		sourceName:
			typeof candidate.sourceName === "string" && candidate.sourceName.trim()
				? candidate.sourceName
				: undefined,
		showCursorOverlay:
			typeof candidate.showCursorOverlay === "boolean" ? candidate.showCursorOverlay : undefined,
	};
}

export function createPersistedRecordingSession(
	session: RecordingSession,
): PersistedRecordingSession {
	return {
		version: RECORDING_SESSION_VERSION,
		...session,
	};
}

export function getFacecamLayout(
	stageWidth: number,
	stageHeight: number,
	settings: FacecamSettings,
) {
	const minDimension = Math.min(stageWidth, stageHeight);
	const size = minDimension * (settings.size / 100);
	const margin = minDimension * (settings.margin / 100);
	const borderRadius =
		settings.shape === "circle"
			? size / 2
			: Math.min(size / 2, size * (settings.cornerRadius / 100));

	let x: number;
	let y: number;

	switch (settings.anchor) {
		case "top-left":
			x = margin;
			y = margin;
			break;
		case "top-right":
			x = Math.max(0, stageWidth - size - margin);
			y = margin;
			break;
		case "bottom-left":
			x = margin;
			y = Math.max(0, stageHeight - size - margin);
			break;
		case "custom": {
			const cx = settings.customX ?? 0.5;
			const cy = settings.customY ?? 0.5;
			x = Math.max(0, Math.min(cx * stageWidth - size / 2, stageWidth - size));
			y = Math.max(0, Math.min(cy * stageHeight - size / 2, stageHeight - size));
			break;
		}
		case "bottom-right":
		default:
			x = Math.max(0, stageWidth - size - margin);
			y = Math.max(0, stageHeight - size - margin);
			break;
	}

	return {
		x,
		y,
		size,
		borderRadius,
	};
}

/**
 * Determine the closest anchor from absolute pixel coordinates on the stage.
 * If within `snapMargin` (fraction of stage dimension) of a corner, returns
 * that corner anchor; otherwise returns "custom" with normalized coordinates.
 */
export function resolveAnchorFromPosition(
	pixelX: number,
	pixelY: number,
	bubbleSize: number,
	stageWidth: number,
	stageHeight: number,
	snapMargin = 0.15,
): { anchor: FacecamAnchor; customX?: number; customY?: number } {
	const centerX = pixelX + bubbleSize / 2;
	const centerY = pixelY + bubbleSize / 2;
	const normX = centerX / stageWidth;
	const normY = centerY / stageHeight;

	// Corner snap zones
	if (normX <= snapMargin && normY <= snapMargin) return { anchor: "top-left" };
	if (normX >= 1 - snapMargin && normY <= snapMargin) return { anchor: "top-right" };
	if (normX <= snapMargin && normY >= 1 - snapMargin) return { anchor: "bottom-left" };
	if (normX >= 1 - snapMargin && normY >= 1 - snapMargin) return { anchor: "bottom-right" };

	return {
		anchor: "custom",
		customX: Math.max(0, Math.min(1, normX)),
		customY: Math.max(0, Math.min(1, normY)),
	};
}
