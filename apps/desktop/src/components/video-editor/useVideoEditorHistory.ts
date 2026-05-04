import { useSetAtom } from "jotai";
import { useCallback, useEffect } from "react";
import type { AnnotationRegion, SpeedRegion, TrimRegion, ZoomRegion } from "./types";
import type { EditorHistorySnapshot } from "./videoEditorHistory";
import {
	cloneEditorHistorySnapshot,
	deriveEditorHistoryCounters,
	recordEditorHistoryAtom,
	redoEditorHistoryAtom,
	undoEditorHistoryAtom,
} from "./videoEditorHistory";

type HistoryState = {
	zoomRegions: ZoomRegion[];
	trimRegions: TrimRegion[];
	speedRegions: SpeedRegion[];
	annotationRegions: AnnotationRegion[];
	selectedZoomId: string | null;
	selectedTrimId: string | null;
	selectedSpeedId: string | null;
	selectedAnnotationId: string | null;
};

type HistorySetters = {
	setZoomRegions: (regions: ZoomRegion[]) => void;
	setTrimRegions: (regions: TrimRegion[]) => void;
	setSpeedRegions: (regions: SpeedRegion[]) => void;
	setAnnotationRegions: (regions: AnnotationRegion[]) => void;
	setSelectedZoomId: (id: string | null) => void;
	setSelectedTrimId: (id: string | null) => void;
	setSelectedSpeedId: (id: string | null) => void;
	setSelectedAnnotationId: (id: string | null) => void;
};

type HistoryRefs = {
	nextZoomIdRef: { current: number };
	nextTrimIdRef: { current: number };
	nextSpeedIdRef: { current: number };
	nextAnnotationIdRef: { current: number };
	nextAnnotationZIndexRef: { current: number };
};

type UseVideoEditorHistoryParams = HistoryState & HistorySetters & HistoryRefs;

export function useVideoEditorHistory({
	zoomRegions,
	trimRegions,
	speedRegions,
	annotationRegions,
	selectedZoomId,
	selectedTrimId,
	selectedSpeedId,
	selectedAnnotationId,
	setZoomRegions,
	setTrimRegions,
	setSpeedRegions,
	setAnnotationRegions,
	setSelectedZoomId,
	setSelectedTrimId,
	setSelectedSpeedId,
	setSelectedAnnotationId,
	nextZoomIdRef,
	nextTrimIdRef,
	nextSpeedIdRef,
	nextAnnotationIdRef,
	nextAnnotationZIndexRef,
}: UseVideoEditorHistoryParams) {
	const recordEditorHistory = useSetAtom(recordEditorHistoryAtom);
	const undoEditorHistory = useSetAtom(undoEditorHistoryAtom);
	const redoEditorHistory = useSetAtom(redoEditorHistoryAtom);

	const buildHistorySnapshot = useCallback(
		() => ({
			zoomRegions,
			trimRegions,
			speedRegions,
			annotationRegions,
			selectedZoomId,
			selectedTrimId,
			selectedSpeedId,
			selectedAnnotationId,
		}),
		[
			zoomRegions,
			trimRegions,
			speedRegions,
			annotationRegions,
			selectedZoomId,
			selectedTrimId,
			selectedSpeedId,
			selectedAnnotationId,
		],
	);

	const applyHistorySnapshot = useCallback(
		(snapshot: EditorHistorySnapshot) => {
			const cloned = cloneEditorHistorySnapshot(snapshot);
			const counters = deriveEditorHistoryCounters(cloned);

			setZoomRegions(cloned.zoomRegions);
			setTrimRegions(cloned.trimRegions);
			setSpeedRegions(cloned.speedRegions);
			setAnnotationRegions(cloned.annotationRegions);
			setSelectedZoomId(cloned.selectedZoomId);
			setSelectedTrimId(cloned.selectedTrimId);
			setSelectedSpeedId(cloned.selectedSpeedId);
			setSelectedAnnotationId(cloned.selectedAnnotationId);

			nextZoomIdRef.current = counters.nextZoomId;
			nextTrimIdRef.current = counters.nextTrimId;
			nextSpeedIdRef.current = counters.nextSpeedId;
			nextAnnotationIdRef.current = counters.nextAnnotationId;
			nextAnnotationZIndexRef.current = counters.nextAnnotationZIndex;
		},
		[
			nextAnnotationIdRef,
			nextAnnotationZIndexRef,
			nextSpeedIdRef,
			nextTrimIdRef,
			nextZoomIdRef,
			setAnnotationRegions,
			setSelectedAnnotationId,
			setSelectedSpeedId,
			setSelectedTrimId,
			setSelectedZoomId,
			setSpeedRegions,
			setTrimRegions,
			setZoomRegions,
		],
	);

	const handleUndo = useCallback(() => {
		const previous = undoEditorHistory();
		if (!previous) {
			return;
		}
		applyHistorySnapshot(previous);
	}, [applyHistorySnapshot, undoEditorHistory]);

	const handleRedo = useCallback(() => {
		const next = redoEditorHistory();
		if (!next) {
			return;
		}
		applyHistorySnapshot(next);
	}, [applyHistorySnapshot, redoEditorHistory]);

	useEffect(() => {
		recordEditorHistory(buildHistorySnapshot());
	}, [buildHistorySnapshot, recordEditorHistory]);

	return {
		handleUndo,
		handleRedo,
	};
}
