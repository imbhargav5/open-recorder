import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
	createDefaultZoomEasing,
	DEFAULT_ANNOTATION_POSITION,
	DEFAULT_ANNOTATION_SIZE,
	DEFAULT_ANNOTATION_STYLE,
	DEFAULT_CROP_REGION,
} from "@/components/video-editor/types";
import { createDefaultFacecamSettings } from "@/lib/recordingSession";
import {
	timelineKeyframesAtom,
	timelinePlaybackCursorDraggingAtom,
	timelineRangeAtom,
	timelineSelectedKeyframeIdAtom,
} from "./timeline";
import {
	annotationRegionsAtom,
	applyLoadedProjectAtom,
	applyLoadedSessionAtom,
	applyLoadedVideoAtom,
	audioMutedAtom,
	currentProjectPathAtom,
	cursorSettingsAtom,
	cursorTelemetryAtom,
	durationAtom,
	exportFormatAtom,
	facecamOffsetMsAtom,
	facecamPlaybackPathAtom,
	facecamSettingsAtom,
	facecamVideoPathAtom,
	isPlayingAtom,
	lastSavedSnapshotAtom,
	playbackReadyAtom,
	resetEditorPlaybackForSourceAtom,
	selectAnnotationAtom,
	selectedAnnotationIdAtom,
	selectedSpeedIdAtom,
	selectedTrimIdAtom,
	selectedZoomIdAtom,
	selectSpeedAtom,
	selectTrimAtom,
	selectZoomAtom,
	sourceNameAtom,
	trimRegionsAtom,
	videoErrorAtom,
	videoPathAtom,
	videoPlaybackFirstFrameReadyAtom,
	videoSourcePathAtom,
	zoomRegionsAtom,
} from "./videoEditor";

function createEditorPayload() {
	return {
		wallpaper: "/wallpaper.jpg",
		audioMuted: true,
		audioVolume: 0.5,
		shadowIntensity: 0.4,
		backgroundBlur: 2,
		zoomMotionBlur: 0.2,
		connectZooms: false,
		cursorSettings: {
			showCursor: true,
			loopCursor: true,
			cursorSize: 2,
			cursorSmoothing: 0.5,
			cursorMotionBlur: 0.1,
			cursorClickBounce: 1,
		},
		borderRadius: 8,
		padding: 24,
		cropRegion: { ...DEFAULT_CROP_REGION, width: 0.8 },
		facecamSettings: createDefaultFacecamSettings(true),
		zoomRegions: [
			{
				id: "zoom-1",
				startMs: 0,
				endMs: 1000,
				depth: 3 as const,
				focus: { cx: 0.4, cy: 0.5 },
				...createDefaultZoomEasing(),
			},
		],
		trimRegions: [{ id: "trim-1", startMs: 100, endMs: 500 }],
		speedRegions: [{ id: "speed-1", startMs: 200, endMs: 800, speed: 1.5 as const }],
		annotationRegions: [
			{
				id: "annotation-1",
				startMs: 0,
				endMs: 1000,
				type: "text" as const,
				content: "Hello",
				textContent: "Hello",
				position: { ...DEFAULT_ANNOTATION_POSITION },
				size: { ...DEFAULT_ANNOTATION_SIZE },
				style: { ...DEFAULT_ANNOTATION_STYLE },
				zIndex: 1,
			},
		],
		aspectRatio: "16:9" as const,
		exportQuality: "source" as const,
		exportFormat: "gif" as const,
		gifFrameRate: 30 as const,
		gifLoop: false,
		gifSizePreset: "small" as const,
	};
}

describe("video editor action atoms", () => {
	it("selection actions keep timeline selection mutually exclusive", () => {
		const store = createStore();

		store.set(selectZoomAtom, "zoom-1");
		expect(store.get(selectedZoomIdAtom)).toBe("zoom-1");

		store.set(selectTrimAtom, "trim-1");
		expect(store.get(selectedZoomIdAtom)).toBeNull();
		expect(store.get(selectedTrimIdAtom)).toBe("trim-1");

		store.set(selectSpeedAtom, "speed-1");
		expect(store.get(selectedTrimIdAtom)).toBeNull();
		expect(store.get(selectedSpeedIdAtom)).toBe("speed-1");

		store.set(selectAnnotationAtom, "annotation-1");
		expect(store.get(selectedSpeedIdAtom)).toBeNull();
		expect(store.get(selectedAnnotationIdAtom)).toBe("annotation-1");
	});

	it("resetEditorPlaybackForSourceAtom resets playback, selections, timeline runtime, and Pixi readiness", () => {
		const store = createStore();
		store.set(isPlayingAtom, true);
		store.set(durationAtom, 120);
		store.set(videoErrorAtom, "boom");
		store.set(playbackReadyAtom, true);
		store.set(cursorTelemetryAtom, [{ timeMs: 1, cx: 0.5, cy: 0.5 }]);
		store.set(videoPlaybackFirstFrameReadyAtom, true);
		store.set(selectZoomAtom, "zoom-1");
		store.set(timelineRangeAtom, { start: 10, end: 20 });
		store.set(timelineKeyframesAtom, [{ id: "kf-1", time: 10 }]);
		store.set(timelineSelectedKeyframeIdAtom, "kf-1");
		store.set(timelinePlaybackCursorDraggingAtom, true);

		store.set(resetEditorPlaybackForSourceAtom);

		expect(store.get(isPlayingAtom)).toBe(false);
		expect(store.get(durationAtom)).toBe(0);
		expect(store.get(videoErrorAtom)).toBeNull();
		expect(store.get(playbackReadyAtom)).toBe(false);
		expect(store.get(cursorTelemetryAtom)).toEqual([]);
		expect(store.get(videoPlaybackFirstFrameReadyAtom)).toBe(false);
		expect(store.get(selectedZoomIdAtom)).toBeNull();
		expect(store.get(timelineRangeAtom)).toEqual({ start: 0, end: 0 });
		expect(store.get(timelineKeyframesAtom)).toEqual([]);
		expect(store.get(timelineSelectedKeyframeIdAtom)).toBeNull();
		expect(store.get(timelinePlaybackCursorDraggingAtom)).toBe(false);
	});

	it("applyLoadedProjectAtom updates source, editor, export, facecam, and dirty snapshot state together", () => {
		const store = createStore();
		const editor = createEditorPayload();

		store.set(applyLoadedProjectAtom, {
			sourcePath: "/source.mov",
			resolvedVideoPath: "asset://source.mov",
			sourceName: "Display 1",
			facecamVideoPath: "/facecam.mov",
			facecamPlaybackPath: "asset://facecam.mov",
			facecamOffsetMs: 42,
			currentProjectPath: "/project.openrecorder",
			editor,
			lastSavedSnapshot: "snapshot",
		});

		expect(store.get(videoSourcePathAtom)).toBe("/source.mov");
		expect(store.get(videoPathAtom)).toBe("asset://source.mov");
		expect(store.get(sourceNameAtom)).toBe("Display 1");
		expect(store.get(facecamVideoPathAtom)).toBe("/facecam.mov");
		expect(store.get(facecamPlaybackPathAtom)).toBe("asset://facecam.mov");
		expect(store.get(facecamOffsetMsAtom)).toBe(42);
		expect(store.get(currentProjectPathAtom)).toBe("/project.openrecorder");
		expect(store.get(audioMutedAtom)).toBe(true);
		expect(store.get(cursorSettingsAtom)).toEqual(editor.cursorSettings);
		expect(store.get(facecamSettingsAtom)).toEqual(editor.facecamSettings);
		expect(store.get(zoomRegionsAtom)).toEqual(editor.zoomRegions);
		expect(store.get(trimRegionsAtom)).toEqual(editor.trimRegions);
		expect(store.get(annotationRegionsAtom)).toEqual(editor.annotationRegions);
		expect(store.get(exportFormatAtom)).toBe("gif");
		expect(store.get(lastSavedSnapshotAtom)).toBe("snapshot");
	});

	it("applyLoadedSessionAtom and applyLoadedVideoAtom reset project snapshot state", () => {
		const store = createStore();
		store.set(currentProjectPathAtom, "/project.openrecorder");
		store.set(lastSavedSnapshotAtom, "snapshot");

		store.set(applyLoadedSessionAtom, {
			sourcePath: "/session.mov",
			resolvedVideoPath: "asset://session.mov",
			sourceName: "Window",
			facecamVideoPath: "/facecam.mov",
			facecamPlaybackPath: "asset://facecam.mov",
			facecamOffsetMs: -12,
			facecamSettings: createDefaultFacecamSettings(true),
			showCursorOverlay: true,
		});

		expect(store.get(currentProjectPathAtom)).toBeNull();
		expect(store.get(lastSavedSnapshotAtom)).toBeNull();
		expect(store.get(cursorSettingsAtom).showCursor).toBe(true);
		expect(store.get(facecamOffsetMsAtom)).toBe(-12);

		store.set(applyLoadedVideoAtom, {
			sourcePath: "/raw.mp4",
			resolvedVideoPath: "asset://raw.mp4",
			sourceName: null,
			facecamSettings: createDefaultFacecamSettings(false),
		});

		expect(store.get(videoSourcePathAtom)).toBe("/raw.mp4");
		expect(store.get(facecamVideoPathAtom)).toBeNull();
		expect(store.get(facecamPlaybackPathAtom)).toBeNull();
		expect(store.get(facecamOffsetMsAtom)).toBe(0);
	});
});
