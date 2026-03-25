import type { CursorTelemetryPoint } from "./types";

type CursorInteractionType = NonNullable<CursorTelemetryPoint["interactionType"]>;
type CursorType = NonNullable<CursorTelemetryPoint["cursorType"]>;

type NormalizeCursorTelemetryPayloadOptions = {
	videoWidth?: number;
	videoHeight?: number;
	durationMs?: number;
};

type JsonRecord = Record<string, unknown>;

const CURSOR_TYPE_ALIASES: Record<string, CursorType> = {
	arrow: "arrow",
	default: "arrow",
	beam: "text",
	ibeam: "text",
	"i-beam": "text",
	text: "text",
	pointer: "pointer",
	hand: "pointer",
	pointinghand: "pointer",
	"pointing-hand": "pointer",
	pointing: "pointer",
	cross: "crosshair",
	crosshair: "crosshair",
	grab: "open-hand",
	openhand: "open-hand",
	"open-hand": "open-hand",
	grabbing: "closed-hand",
	closedhand: "closed-hand",
	"closed-hand": "closed-hand",
	"resize-ew": "resize-ew",
	"ew-resize": "resize-ew",
	ewresize: "resize-ew",
	colresize: "resize-ew",
	"col-resize": "resize-ew",
	"left-right": "resize-ew",
	"resize-left-right": "resize-ew",
	"resize-west-east": "resize-ew",
	"resize-ns": "resize-ns",
	"ns-resize": "resize-ns",
	nsresize: "resize-ns",
	rowresize: "resize-ns",
	"row-resize": "resize-ns",
	"up-down": "resize-ns",
	"resize-up-down": "resize-ns",
	"resize-north-south": "resize-ns",
	notallowed: "not-allowed",
	"not-allowed": "not-allowed",
	forbidden: "not-allowed",
	nodrop: "not-allowed",
	"no-drop": "not-allowed",
};

const INTERACTION_TYPE_ALIASES: Record<string, CursorInteractionType> = {
	move: "move",
	moved: "move",
	mousemove: "move",
	left: "click",
	click: "click",
	leftclick: "click",
	"left-click": "click",
	double: "double-click",
	doubleclick: "double-click",
	"double-click": "double-click",
	leftdoubleclick: "double-click",
	"left-double-click": "double-click",
	right: "right-click",
	rightclick: "right-click",
	"right-click": "right-click",
	middle: "middle-click",
	middleclick: "middle-click",
	"middle-click": "middle-click",
	mouseup: "mouseup",
	up: "mouseup",
};

function isRecord(value: unknown): value is JsonRecord {
	return typeof value === "object" && value !== null;
}

function getFiniteNumber(value: unknown) {
	return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function clamp01(value: number) {
	return Math.min(1, Math.max(0, value));
}

function getArrayField(record: JsonRecord, key: string) {
	const value = record[key];
	return Array.isArray(value) ? value : [];
}

function getNestedNumber(record: JsonRecord, path: string[]) {
	let current: unknown = record;
	for (const key of path) {
		if (!isRecord(current)) {
			return null;
		}
		current = current[key];
	}
	return getFiniteNumber(current);
}

function getDimensionHint(
	payload: JsonRecord,
	axis: "width" | "height",
	fallback: number | undefined,
	maxObserved: number,
) {
	const candidates = [
		getFiniteNumber(payload[axis]),
		getFiniteNumber(payload[axis === "width" ? "videoWidth" : "videoHeight"]),
		getFiniteNumber(payload[axis === "width" ? "viewportWidth" : "viewportHeight"]),
		getFiniteNumber(payload[axis === "width" ? "screenWidth" : "screenHeight"]),
		getFiniteNumber(payload[axis === "width" ? "captureWidth" : "captureHeight"]),
		getNestedNumber(payload, ["bounds", axis]),
		getNestedNumber(payload, ["viewport", axis]),
		getNestedNumber(payload, ["screen", axis]),
		getNestedNumber(payload, ["recordingBounds", axis]),
		getNestedNumber(payload, ["metadata", axis]),
	].filter((value): value is number => value !== null && value > 1);

	if (candidates.length > 0) {
		return Math.max(...candidates);
	}

	if (typeof fallback === "number" && Number.isFinite(fallback) && fallback > 1) {
		return fallback;
	}

	return maxObserved > 1 ? maxObserved : 1;
}

function getRawTime(entry: JsonRecord) {
	return (
		getFiniteNumber(entry.timeMs) ??
		getFiniteNumber(entry.timestampMs) ??
		getFiniteNumber(entry.time_ms) ??
		getFiniteNumber(entry.timestamp) ??
		getFiniteNumber(entry.t) ??
		getFiniteNumber(entry.time)
	);
}

function normalizeCursorType(value: unknown): CursorType | undefined {
	if (typeof value !== "string" || value.trim().length === 0) {
		return undefined;
	}

	const normalizedKey = value
		.trim()
		.toLowerCase()
		.replace(/_/g, "-")
		.replace(/\s+/g, "")
		.replace(/cursor/g, "");

	return CURSOR_TYPE_ALIASES[normalizedKey] ?? undefined;
}

function normalizeInteractionType(value: unknown, defaultValue?: CursorInteractionType) {
	if (typeof value !== "string" || value.trim().length === 0) {
		return defaultValue;
	}

	const normalizedKey = value.trim().toLowerCase().replace(/_/g, "-").replace(/\s+/g, "");

	return INTERACTION_TYPE_ALIASES[normalizedKey] ?? defaultValue;
}

type NormalizationContext = {
	durationMs?: number;
	height: number;
	scaleTimeToMs: boolean;
	timeOffsetMs: number;
	width: number;
};

function normalizeCoordinate(value: number, scale: number) {
	if (value >= 0 && value <= 1) {
		return clamp01(value);
	}

	if (scale <= 1) {
		return null;
	}

	return clamp01(value / scale);
}

function normalizeEntry(
	entry: unknown,
	context: NormalizationContext,
	defaultInteractionType?: CursorInteractionType,
) {
	if (!isRecord(entry)) {
		return null;
	}

	const rawX = getFiniteNumber(entry.cx) ?? getFiniteNumber(entry.x);
	const rawY = getFiniteNumber(entry.cy) ?? getFiniteNumber(entry.y);
	const rawTime = getRawTime(entry);

	if (rawX === null || rawY === null || rawTime === null) {
		return null;
	}

	const cx = normalizeCoordinate(rawX, context.width);
	const cy = normalizeCoordinate(rawY, context.height);
	if (cx === null || cy === null) {
		return null;
	}

	const adjustedTimeMs = rawTime * (context.scaleTimeToMs ? 1000 : 1) - context.timeOffsetMs;
	const safeDurationMs = context.durationMs ?? Number.MAX_SAFE_INTEGER;

	return {
		timeMs: Math.max(0, Math.min(adjustedTimeMs, safeDurationMs)),
		cx,
		cy,
		interactionType: normalizeInteractionType(
			entry.interactionType ??
				entry.interaction_type ??
				entry.clickType ??
				entry.click_type ??
				entry.type,
			defaultInteractionType,
		),
		cursorType: normalizeCursorType(entry.cursorType ?? entry.cursor_type ?? entry.cursor),
	} satisfies CursorTelemetryPoint;
}

function getMaxObservedCoordinate(entries: unknown[], axis: "x" | "y" | "cx" | "cy") {
	let max = 0;
	for (const entry of entries) {
		if (!isRecord(entry)) {
			continue;
		}
		const value = getFiniteNumber(entry[axis]);
		if (value !== null) {
			max = Math.max(max, value);
		}
	}
	return max;
}

function getTimeNormalization(entries: unknown[], durationMs?: number) {
	const rawTimes = entries
		.map((entry) => (isRecord(entry) ? getRawTime(entry) : null))
		.filter((value): value is number => value !== null);

	if (rawTimes.length === 0) {
		return { scaleTimeToMs: false, timeOffsetMs: 0 };
	}

	const minTime = Math.min(...rawTimes);
	const maxTime = Math.max(...rawTimes);
	const safeDurationMs =
		typeof durationMs === "number" && Number.isFinite(durationMs) && durationMs > 0
			? durationMs
			: undefined;

	const scaleTimeToMs = Boolean(
		safeDurationMs && maxTime > 0 && maxTime <= 600 && safeDurationMs / Math.max(1, maxTime) >= 10,
	);
	const scaledMinTime = minTime * (scaleTimeToMs ? 1000 : 1);
	const scaledMaxTime = maxTime * (scaleTimeToMs ? 1000 : 1);
	const shouldRebase =
		scaledMinTime >= 1000 &&
		((safeDurationMs && scaledMaxTime > safeDurationMs * 1.5) || scaledMinTime > 100_000);

	return {
		scaleTimeToMs,
		timeOffsetMs: shouldRebase ? scaledMinTime : 0,
	};
}

export function normalizeCursorTelemetryPayload(
	payload: unknown,
	options: NormalizeCursorTelemetryPayloadOptions = {},
): CursorTelemetryPoint[] {
	const root = isRecord(payload) ? payload : {};
	const sampleEntries = Array.isArray(payload) ? payload : getArrayField(root, "samples");
	const clickEntries = getArrayField(root, "clicks");
	const allEntries = [...sampleEntries, ...clickEntries];

	if (allEntries.length === 0) {
		return [];
	}

	const rawWidth = Math.max(
		getMaxObservedCoordinate(allEntries, "cx"),
		getMaxObservedCoordinate(allEntries, "x"),
	);
	const rawHeight = Math.max(
		getMaxObservedCoordinate(allEntries, "cy"),
		getMaxObservedCoordinate(allEntries, "y"),
	);
	const width = getDimensionHint(root, "width", options.videoWidth, rawWidth);
	const height = getDimensionHint(root, "height", options.videoHeight, rawHeight);
	const { scaleTimeToMs, timeOffsetMs } = getTimeNormalization(allEntries, options.durationMs);
	const normalizationContext: NormalizationContext = {
		width,
		height,
		durationMs: options.durationMs,
		scaleTimeToMs,
		timeOffsetMs,
	};

	const normalized = [
		...sampleEntries.map((entry) => normalizeEntry(entry, normalizationContext, "move")),
		...clickEntries.map((entry) => normalizeEntry(entry, normalizationContext)),
	]
		.filter((entry): entry is CursorTelemetryPoint => entry !== null)
		.sort((a, b) => a.timeMs - b.timeMs);

	if (normalized.length === 0) {
		return [];
	}

	const unique = new Map<string, CursorTelemetryPoint>();
	for (const sample of normalized) {
		const dedupeKey = [
			sample.timeMs,
			sample.cx.toFixed(5),
			sample.cy.toFixed(5),
			sample.interactionType ?? "",
			sample.cursorType ?? "",
		].join(":");
		if (!unique.has(dedupeKey)) {
			unique.set(dedupeKey, sample);
		}
	}

	return [...unique.values()];
}
