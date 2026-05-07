import { atom } from "jotai";
import { deriveNextId } from "./projectPersistence";
import type { AnnotationRegion, SpeedRegion, TrimRegion, ZoomRegion } from "./types";

export type EditorHistorySnapshot = {
	zoomRegions: ZoomRegion[];
	trimRegions: TrimRegion[];
	speedRegions: SpeedRegion[];
	annotationRegions: AnnotationRegion[];
	selectedZoomId: string | null;
	selectedTrimId: string | null;
	selectedSpeedId: string | null;
	selectedAnnotationId: string | null;
	signature: string;
};

export type EditorHistorySnapshotInput = Omit<EditorHistorySnapshot, "signature">;

export type EditorHistoryCounters = {
	nextZoomId: number;
	nextTrimId: number;
	nextSpeedId: number;
	nextAnnotationId: number;
	nextAnnotationZIndex: number;
};

export type EditorHistoryState = {
	past: EditorHistorySnapshot[];
	current: EditorHistorySnapshot | null;
	future: EditorHistorySnapshot[];
};

const MAX_HISTORY_SNAPSHOTS = 100;

function getZoomRegionSignature(region: ZoomRegion) {
	return [
		region.id,
		region.startMs,
		region.endMs,
		region.depth,
		region.focus.cx,
		region.focus.cy,
		region.easeIn.durationMs,
		region.easeIn.type,
		region.easeOut.durationMs,
		region.easeOut.type,
	].join(":");
}

function getTrimRegionSignature(region: TrimRegion) {
	return `${region.id}:${region.startMs}:${region.endMs}`;
}

function getSpeedRegionSignature(region: SpeedRegion) {
	return `${region.id}:${region.startMs}:${region.endMs}:${region.speed}`;
}

function getAnnotationRegionSignature(region: AnnotationRegion) {
	return [
		region.id,
		region.startMs,
		region.endMs,
		region.type,
		region.content,
		region.textContent ?? "",
		region.imageContent ?? "",
		region.position.x,
		region.position.y,
		region.size.width,
		region.size.height,
		region.style.fontSize,
		region.style.color,
		region.style.backgroundColor,
		region.style.fontFamily ?? "",
		region.style.fontWeight ?? "",
		region.style.fontStyle,
		region.style.textDecoration,
		region.style.textAlign,
		region.zIndex,
		region.figureData?.arrowDirection ?? "",
		region.figureData?.color ?? "",
		region.figureData?.strokeWidth ?? 0,
	].join(":");
}

export function createHistorySignature(snapshot: EditorHistorySnapshotInput) {
	return [
		snapshot.zoomRegions.map(getZoomRegionSignature).join("|"),
		snapshot.trimRegions.map(getTrimRegionSignature).join("|"),
		snapshot.speedRegions.map(getSpeedRegionSignature).join("|"),
		snapshot.annotationRegions.map(getAnnotationRegionSignature).join("|"),
		snapshot.selectedZoomId ?? "",
		snapshot.selectedTrimId ?? "",
		snapshot.selectedSpeedId ?? "",
		snapshot.selectedAnnotationId ?? "",
	].join("~");
}

export function createEditorHistorySnapshot(
	snapshot: EditorHistorySnapshotInput,
): EditorHistorySnapshot {
	return {
		...snapshot,
		signature: createHistorySignature(snapshot),
	};
}

export function cloneEditorHistorySnapshot(snapshot: EditorHistorySnapshot): EditorHistorySnapshot {
	return {
		zoomRegions: snapshot.zoomRegions.map((region) => structuredClone(region)),
		trimRegions: snapshot.trimRegions.map((region) => structuredClone(region)),
		speedRegions: snapshot.speedRegions.map((region) => structuredClone(region)),
		annotationRegions: snapshot.annotationRegions.map((region) => structuredClone(region)),
		selectedZoomId: snapshot.selectedZoomId,
		selectedTrimId: snapshot.selectedTrimId,
		selectedSpeedId: snapshot.selectedSpeedId,
		selectedAnnotationId: snapshot.selectedAnnotationId,
		signature: snapshot.signature,
	};
}

export const editorHistoryAtom = atom<EditorHistoryState>({
	past: [],
	current: null,
	future: [],
});

export const resetEditorHistoryAtom = atom(null, (_get, set) => {
	set(editorHistoryAtom, {
		past: [],
		current: null,
		future: [],
	});
});

export const recordEditorHistoryAtom = atom(null, (get, set, input: EditorHistorySnapshotInput) => {
	const snapshot = cloneEditorHistorySnapshot(createEditorHistorySnapshot(input));
	const history = get(editorHistoryAtom);

	if (!history.current) {
		set(editorHistoryAtom, {
			...history,
			current: snapshot,
		});
		return;
	}

	if (history.current.signature === snapshot.signature) {
		return;
	}

	const past = [...history.past, cloneEditorHistorySnapshot(history.current)];
	if (past.length > MAX_HISTORY_SNAPSHOTS) {
		past.shift();
	}

	set(editorHistoryAtom, {
		past,
		current: snapshot,
		future: [],
	});
});

export const undoEditorHistoryAtom = atom(null, (get, set): EditorHistorySnapshot | null => {
	const history = get(editorHistoryAtom);
	const previous = history.past[history.past.length - 1];
	if (!previous) {
		return null;
	}

	const current =
		history.current ??
		createEditorHistorySnapshot({
			zoomRegions: [],
			trimRegions: [],
			speedRegions: [],
			annotationRegions: [],
			selectedZoomId: null,
			selectedTrimId: null,
			selectedSpeedId: null,
			selectedAnnotationId: null,
		});

	set(editorHistoryAtom, {
		past: history.past.slice(0, -1),
		current: cloneEditorHistorySnapshot(previous),
		future: [cloneEditorHistorySnapshot(current), ...history.future],
	});

	return cloneEditorHistorySnapshot(previous);
});

export const redoEditorHistoryAtom = atom(null, (get, set): EditorHistorySnapshot | null => {
	const history = get(editorHistoryAtom);
	const next = history.future[0];
	if (!next) {
		return null;
	}

	const current =
		history.current ??
		createEditorHistorySnapshot({
			zoomRegions: [],
			trimRegions: [],
			speedRegions: [],
			annotationRegions: [],
			selectedZoomId: null,
			selectedTrimId: null,
			selectedSpeedId: null,
			selectedAnnotationId: null,
		});

	set(editorHistoryAtom, {
		past: [...history.past, cloneEditorHistorySnapshot(current)],
		current: cloneEditorHistorySnapshot(next),
		future: history.future.slice(1),
	});

	return cloneEditorHistorySnapshot(next);
});

export function deriveEditorHistoryCounters(
	snapshot: Pick<
		EditorHistorySnapshot,
		"zoomRegions" | "trimRegions" | "speedRegions" | "annotationRegions"
	>,
): EditorHistoryCounters {
	return {
		nextZoomId: deriveNextId(
			"zoom",
			snapshot.zoomRegions.map((region) => region.id),
		),
		nextTrimId: deriveNextId(
			"trim",
			snapshot.trimRegions.map((region) => region.id),
		),
		nextSpeedId: deriveNextId(
			"speed",
			snapshot.speedRegions.map((region) => region.id),
		),
		nextAnnotationId: deriveNextId(
			"annotation",
			snapshot.annotationRegions.map((region) => region.id),
		),
		nextAnnotationZIndex:
			snapshot.annotationRegions.reduce((max, region) => Math.max(max, region.zIndex), 0) + 1,
	};
}
