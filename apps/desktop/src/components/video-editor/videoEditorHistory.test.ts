import { describe, expect, it } from "vitest";
import {
	DEFAULT_ANNOTATION_POSITION,
	DEFAULT_ANNOTATION_SIZE,
	DEFAULT_ANNOTATION_STYLE,
	DEFAULT_FIGURE_DATA,
	createDefaultZoomEasing,
} from "./types";
import {
	cloneEditorHistorySnapshot,
	createEditorHistorySnapshot,
	deriveEditorHistoryCounters,
} from "./videoEditorHistory";

describe("videoEditorHistory", () => {
	it("changes the signature when annotation-specific content changes", () => {
		const baseSnapshot = createEditorHistorySnapshot({
			zoomRegions: [],
			trimRegions: [],
			speedRegions: [],
			annotationRegions: [
				{
					id: "annotation-3",
					startMs: 100,
					endMs: 200,
					type: "figure",
					content: "",
					position: { ...DEFAULT_ANNOTATION_POSITION },
					size: { ...DEFAULT_ANNOTATION_SIZE },
					style: { ...DEFAULT_ANNOTATION_STYLE },
					zIndex: 7,
					figureData: { ...DEFAULT_FIGURE_DATA },
				},
			],
			selectedZoomId: null,
			selectedTrimId: null,
			selectedSpeedId: null,
			selectedAnnotationId: "annotation-3",
		});

		const changedSnapshot = createEditorHistorySnapshot({
			...baseSnapshot,
			annotationRegions: [
				{
					...baseSnapshot.annotationRegions[0],
					figureData: {
						...DEFAULT_FIGURE_DATA,
						arrowDirection: "down-left",
					},
				},
			],
		});

		expect(changedSnapshot.signature).not.toBe(baseSnapshot.signature);
	});

	it("clones region arrays so history snapshots are not structurally shared", () => {
		const original = createEditorHistorySnapshot({
			zoomRegions: [
				{
					id: "zoom-1",
					startMs: 0,
					endMs: 500,
					depth: 3,
					focus: { cx: 0.5, cy: 0.5 },
					...createDefaultZoomEasing(),
				},
			],
			trimRegions: [{ id: "trim-1", startMs: 0, endMs: 500 }],
			speedRegions: [{ id: "speed-1", startMs: 0, endMs: 500, speed: 1.5 }],
			annotationRegions: [],
			selectedZoomId: "zoom-1",
			selectedTrimId: null,
			selectedSpeedId: null,
			selectedAnnotationId: null,
		});

		const cloned = cloneEditorHistorySnapshot(original);

		expect(cloned).toEqual(original);
		expect(cloned.zoomRegions).not.toBe(original.zoomRegions);
		expect(cloned.trimRegions).not.toBe(original.trimRegions);
		expect(cloned.speedRegions).not.toBe(original.speedRegions);
		expect(cloned.annotationRegions).not.toBe(original.annotationRegions);
	});

	it("changes the signature when zoom easing changes", () => {
		const baseSnapshot = createEditorHistorySnapshot({
			zoomRegions: [
				{
					id: "zoom-1",
					startMs: 0,
					endMs: 500,
					depth: 3,
					focus: { cx: 0.5, cy: 0.5 },
					...createDefaultZoomEasing(),
				},
			],
			trimRegions: [],
			speedRegions: [],
			annotationRegions: [],
			selectedZoomId: "zoom-1",
			selectedTrimId: null,
			selectedSpeedId: null,
			selectedAnnotationId: null,
		});

		const changedSnapshot = createEditorHistorySnapshot({
			...baseSnapshot,
			zoomRegions: [
				{
					...baseSnapshot.zoomRegions[0],
					easeOut: {
						durationMs: 250,
						type: "linear",
					},
				},
			],
		});

		expect(changedSnapshot.signature).not.toBe(baseSnapshot.signature);
	});

	it("derives the next region ids and annotation z-index from restored history", () => {
		expect(
			deriveEditorHistoryCounters({
				zoomRegions: [
					{
						id: "zoom-2",
						startMs: 0,
						endMs: 500,
						depth: 3,
						focus: { cx: 0.5, cy: 0.5 },
						...createDefaultZoomEasing(),
					},
					{
						id: "zoom-9",
						startMs: 600,
						endMs: 900,
						depth: 4,
						focus: { cx: 0.4, cy: 0.4 },
						...createDefaultZoomEasing(),
					},
				],
				trimRegions: [{ id: "trim-4", startMs: 0, endMs: 900 }],
				speedRegions: [{ id: "speed-5", startMs: 0, endMs: 900, speed: 2 }],
				annotationRegions: [
					{
						id: "annotation-1",
						startMs: 0,
						endMs: 300,
						type: "text",
						content: "hello",
						textContent: "hello",
						position: { ...DEFAULT_ANNOTATION_POSITION },
						size: { ...DEFAULT_ANNOTATION_SIZE },
						style: { ...DEFAULT_ANNOTATION_STYLE },
						zIndex: 3,
					},
					{
						id: "annotation-7",
						startMs: 400,
						endMs: 700,
						type: "image",
						content: "data:image/png;base64,abc",
						imageContent: "data:image/png;base64,abc",
						position: { ...DEFAULT_ANNOTATION_POSITION },
						size: { ...DEFAULT_ANNOTATION_SIZE },
						style: { ...DEFAULT_ANNOTATION_STYLE },
						zIndex: 9,
					},
				],
			}),
		).toEqual({
			nextZoomId: 10,
			nextTrimId: 5,
			nextSpeedId: 6,
			nextAnnotationId: 8,
			nextAnnotationZIndex: 10,
		});
	});
});
