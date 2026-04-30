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

function getZoomRegionSignature(region: ZoomRegion) {
	return `${region.id}:${region.startMs}:${region.endMs}:${region.depth}:${region.focus.cx}:${region.focus.cy}`;
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
		zoomRegions: [...snapshot.zoomRegions],
		trimRegions: [...snapshot.trimRegions],
		speedRegions: [...snapshot.speedRegions],
		annotationRegions: [...snapshot.annotationRegions],
		selectedZoomId: snapshot.selectedZoomId,
		selectedTrimId: snapshot.selectedTrimId,
		selectedSpeedId: snapshot.selectedSpeedId,
		selectedAnnotationId: snapshot.selectedAnnotationId,
		signature: snapshot.signature,
	};
}

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
