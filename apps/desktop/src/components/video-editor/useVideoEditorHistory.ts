import { useCallback, useEffect, useRef } from "react";
import type { EditorHistorySnapshot } from "./videoEditorHistory";
import {
	cloneEditorHistorySnapshot,
	createEditorHistorySnapshot,
	deriveEditorHistoryCounters,
} from "./videoEditorHistory";
import type { AnnotationRegion, SpeedRegion, TrimRegion, ZoomRegion } from "./types";

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
	const historyPastRef = useRef<EditorHistorySnapshot[]>([]);
	const historyFutureRef = useRef<EditorHistorySnapshot[]>([]);
	const historyCurrentRef = useRef<EditorHistorySnapshot | null>(null);
	const applyingHistoryRef = useRef(false);

	const buildHistorySnapshot = useCallback(
		() =>
			createEditorHistorySnapshot({
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
			applyingHistoryRef.current = true;
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
		if (historyPastRef.current.length === 0) {
			return;
		}

		const current = historyCurrentRef.current ?? cloneEditorHistorySnapshot(buildHistorySnapshot());
		const previous = historyPastRef.current.pop();
		if (!previous) {
			return;
		}

		historyFutureRef.current.push(cloneEditorHistorySnapshot(current));
		historyCurrentRef.current = cloneEditorHistorySnapshot(previous);
		applyHistorySnapshot(previous);
	}, [applyHistorySnapshot, buildHistorySnapshot]);

	const handleRedo = useCallback(() => {
		if (historyFutureRef.current.length === 0) {
			return;
		}

		const current = historyCurrentRef.current ?? cloneEditorHistorySnapshot(buildHistorySnapshot());
		const next = historyFutureRef.current.pop();
		if (!next) {
			return;
		}

		historyPastRef.current.push(cloneEditorHistorySnapshot(current));
		historyCurrentRef.current = cloneEditorHistorySnapshot(next);
		applyHistorySnapshot(next);
	}, [applyHistorySnapshot, buildHistorySnapshot]);

	useEffect(() => {
		const snapshot = cloneEditorHistorySnapshot(buildHistorySnapshot());

		if (!historyCurrentRef.current) {
			historyCurrentRef.current = snapshot;
			return;
		}

		if (applyingHistoryRef.current) {
			historyCurrentRef.current = snapshot;
			applyingHistoryRef.current = false;
			return;
		}

		if (historyCurrentRef.current.signature === snapshot.signature) {
			return;
		}

		historyPastRef.current.push(cloneEditorHistorySnapshot(historyCurrentRef.current));
		if (historyPastRef.current.length > 100) {
			historyPastRef.current.shift();
		}
		historyCurrentRef.current = snapshot;
		historyFutureRef.current = [];
	}, [buildHistorySnapshot]);

	return {
		handleUndo,
		handleRedo,
	};
}
