import type { Range } from "dnd-timeline";
import { atom } from "jotai";

export const timelineRangeAtom = atom<Range>({ start: 0, end: 0 });
export const timelineKeyframesAtom = atom<{ id: string; time: number }[]>([]);
export const timelineSelectedKeyframeIdAtom = atom<string | null>(null);
export const timelineCustomAspectWidthAtom = atom<string>("16");
export const timelineCustomAspectHeightAtom = atom<string>("9");
export const timelineScrollLabelsAtom = atom<{ pan: string; zoom: string }>({
	pan: "Shift + Ctrl + Scroll",
	zoom: "Ctrl + Scroll",
});
export const timelinePlaybackCursorDraggingAtom = atom<boolean>(false);
export const timelineDraggingKeyframeIdAtom = atom<string | null>(null);
