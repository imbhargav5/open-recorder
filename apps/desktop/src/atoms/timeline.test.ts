import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
	timelineCustomAspectHeightAtom,
	timelineCustomAspectWidthAtom,
	timelineDraggingKeyframeIdAtom,
	timelineKeyframesAtom,
	timelinePlaybackCursorDraggingAtom,
	timelineRangeAtom,
	timelineScrollLabelsAtom,
	timelineSelectedKeyframeIdAtom,
} from "./timeline";

describe("timeline atoms – write / read", () => {
	it("timelineRangeAtom can be set to a non-zero range", () => {
		const store = createStore();
		store.set(timelineRangeAtom, { start: 1000, end: 5000 });
		expect(store.get(timelineRangeAtom)).toEqual({ start: 1000, end: 5000 });
	});

	it("timelineRangeAtom can be reset to zero", () => {
		const store = createStore();
		store.set(timelineRangeAtom, { start: 1000, end: 5000 });
		store.set(timelineRangeAtom, { start: 0, end: 0 });
		expect(store.get(timelineRangeAtom)).toEqual({ start: 0, end: 0 });
	});

	it("timelineRangeAtom start and end are independent fields", () => {
		const store = createStore();
		store.set(timelineRangeAtom, { start: 500, end: 3000 });
		const range = store.get(timelineRangeAtom);
		expect(range.start).toBe(500);
		expect(range.end).toBe(3000);
	});

	it("timelineKeyframesAtom can have keyframes added", () => {
		const store = createStore();
		store.set(timelineKeyframesAtom, [{ id: "kf1", time: 1000 }]);
		expect(store.get(timelineKeyframesAtom)).toHaveLength(1);
		expect(store.get(timelineKeyframesAtom)[0]).toEqual({ id: "kf1", time: 1000 });
	});

	it("timelineKeyframesAtom can hold multiple keyframes", () => {
		const store = createStore();
		const keyframes = [
			{ id: "kf1", time: 0 },
			{ id: "kf2", time: 500 },
			{ id: "kf3", time: 1000 },
		];
		store.set(timelineKeyframesAtom, keyframes);
		expect(store.get(timelineKeyframesAtom)).toHaveLength(3);
	});

	it("timelineKeyframesAtom can be cleared back to empty array", () => {
		const store = createStore();
		store.set(timelineKeyframesAtom, [{ id: "kf1", time: 500 }]);
		store.set(timelineKeyframesAtom, []);
		expect(store.get(timelineKeyframesAtom)).toEqual([]);
	});

	it("timelineKeyframesAtom allows multiple keyframes at the same time", () => {
		const store = createStore();
		store.set(timelineKeyframesAtom, [
			{ id: "kf1", time: 100 },
			{ id: "kf2", time: 100 },
		]);
		expect(store.get(timelineKeyframesAtom)).toHaveLength(2);
	});

	it("timelineSelectedKeyframeIdAtom can be set to a keyframe ID", () => {
		const store = createStore();
		store.set(timelineSelectedKeyframeIdAtom, "kf-selected");
		expect(store.get(timelineSelectedKeyframeIdAtom)).toBe("kf-selected");
	});

	it("timelineSelectedKeyframeIdAtom can be deselected (set to null)", () => {
		const store = createStore();
		store.set(timelineSelectedKeyframeIdAtom, "kf-1");
		store.set(timelineSelectedKeyframeIdAtom, null);
		expect(store.get(timelineSelectedKeyframeIdAtom)).toBeNull();
	});

	it("timelineCustomAspectWidthAtom can be updated", () => {
		const store = createStore();
		store.set(timelineCustomAspectWidthAtom, "4");
		expect(store.get(timelineCustomAspectWidthAtom)).toBe("4");
	});

	it("timelineCustomAspectHeightAtom can be updated", () => {
		const store = createStore();
		store.set(timelineCustomAspectHeightAtom, "3");
		expect(store.get(timelineCustomAspectHeightAtom)).toBe("3");
	});

	it("timelineScrollLabelsAtom can be customised", () => {
		const store = createStore();
		store.set(timelineScrollLabelsAtom, { pan: "Alt + Scroll", zoom: "Scroll" });
		expect(store.get(timelineScrollLabelsAtom)).toEqual({
			pan: "Alt + Scroll",
			zoom: "Scroll",
		});
	});

	it("timelinePlaybackCursorDraggingAtom can track active playhead dragging", () => {
		const store = createStore();
		store.set(timelinePlaybackCursorDraggingAtom, true);
		expect(store.get(timelinePlaybackCursorDraggingAtom)).toBe(true);
		store.set(timelinePlaybackCursorDraggingAtom, false);
		expect(store.get(timelinePlaybackCursorDraggingAtom)).toBe(false);
	});

	it("timelineDraggingKeyframeIdAtom can track the active keyframe drag", () => {
		const store = createStore();
		store.set(timelineDraggingKeyframeIdAtom, "kf-1");
		expect(store.get(timelineDraggingKeyframeIdAtom)).toBe("kf-1");
		store.set(timelineDraggingKeyframeIdAtom, null);
		expect(store.get(timelineDraggingKeyframeIdAtom)).toBeNull();
	});

	it("writes to one store do not affect another store", () => {
		const storeA = createStore();
		const storeB = createStore();

		storeA.set(timelineRangeAtom, { start: 0, end: 9999 });
		storeA.set(timelineKeyframesAtom, [{ id: "kf1", time: 0 }]);
		storeA.set(timelineSelectedKeyframeIdAtom, "kf1");
		storeA.set(timelinePlaybackCursorDraggingAtom, true);
		storeA.set(timelineDraggingKeyframeIdAtom, "kf1");

		expect(storeB.get(timelineRangeAtom)).toEqual({ start: 0, end: 0 });
		expect(storeB.get(timelineKeyframesAtom)).toEqual([]);
		expect(storeB.get(timelineSelectedKeyframeIdAtom)).toBeNull();
		expect(storeB.get(timelinePlaybackCursorDraggingAtom)).toBe(false);
		expect(storeB.get(timelineDraggingKeyframeIdAtom)).toBeNull();
	});
});
