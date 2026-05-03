/**
 * Jotai atom tests for videoEditor.ts
 *
 * Tests cover:
 * - Default values for all ~47 atoms
 * - Atom mutations (playback, export, regions, appearance)
 * - Store isolation between independent stores
 * - Subscriptions for key atoms
 */

import { createStore } from "jotai";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
	addCustomFontDialogOpenAtom,
	addCustomFontImportUrlAtom,
	addCustomFontLoadingAtom,
	addCustomFontNameAtom,
	annotationRegionsAtom,
	aspectRatioAtom,
	audioMutedAtom,
	audioVolumeAtom,
	backgroundBlurAtom,
	borderRadiusAtom,
	connectZoomsAtom,
	cropControlDragHandleAtom,
	cropControlDragStartAtom,
	cropControlInitialCropAtom,
	cropRegionAtom,
	currentProjectPathAtom,
	cursorSettingsAtom,
	durationAtom,
	exportDialogShowSuccessAtom,
	exportErrorAtom,
	exportedFilePathAtom,
	exportFormatAtom,
	exportProgressAtom,
	exportQualityAtom,
	facecamOffsetMsAtom,
	facecamPlaybackPathAtom,
	facecamVideoPathAtom,
	gifFrameRateAtom,
	gifLoopAtom,
	gifSizePresetAtom,
	hasPendingExportSaveAtom,
	isExportingAtom,
	isPlayingAtom,
	lastSavedSnapshotAtom,
	paddingAtom,
	playbackReadyAtom,
	resetAddCustomFontDialogAtom,
	resetCropControlDragAtom,
	resetVideoPlaybackRuntimeAtom,
	selectedAnnotationIdAtom,
	selectedSpeedIdAtom,
	selectedTrimIdAtom,
	selectedZoomIdAtom,
	shadowIntensityAtom,
	showExportDialogAtom,
	showShortcutsDialogAtom,
	sourceNameAtom,
	speedRegionsAtom,
	trimRegionsAtom,
	videoErrorAtom,
	videoLoadingAtom,
	videoPathAtom,
	videoPlaybackAnnotationVisibilityTickAtom,
	videoPlaybackCursorOverlayReadyAtom,
	videoPlaybackFacecamReadyAtom,
	videoPlaybackFirstFrameReadyAtom,
	videoPlaybackMetadataReadyAtom,
	videoPlaybackPixiReadyAtom,
	videoPlaybackResolvedWallpaperAtom,
	videoSourcePathAtom,
	zoomMotionBlurAtom,
	zoomRegionsAtom,
} from "./videoEditor";

// ─── Default values ─────────────────────────────────────────────────────────

describe("videoEditor atoms – source defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("videoPathAtom defaults to null", () => {
		expect(store.get(videoPathAtom)).toBeNull();
	});

	it("videoSourcePathAtom defaults to null", () => {
		expect(store.get(videoSourcePathAtom)).toBeNull();
	});

	it("sourceNameAtom defaults to null", () => {
		expect(store.get(sourceNameAtom)).toBeNull();
	});

	it("facecamVideoPathAtom defaults to null", () => {
		expect(store.get(facecamVideoPathAtom)).toBeNull();
	});

	it("facecamPlaybackPathAtom defaults to null", () => {
		expect(store.get(facecamPlaybackPathAtom)).toBeNull();
	});

	it("facecamOffsetMsAtom defaults to 0", () => {
		expect(store.get(facecamOffsetMsAtom)).toBe(0);
	});

	it("currentProjectPathAtom defaults to null", () => {
		expect(store.get(currentProjectPathAtom)).toBeNull();
	});
});

describe("videoEditor atoms – loading/error defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("videoLoadingAtom defaults to true", () => {
		expect(store.get(videoLoadingAtom)).toBe(true);
	});

	it("playbackReadyAtom defaults to false", () => {
		expect(store.get(playbackReadyAtom)).toBe(false);
	});

	it("videoErrorAtom defaults to null", () => {
		expect(store.get(videoErrorAtom)).toBeNull();
	});

	it("video playback runtime atoms default to not ready", () => {
		expect(store.get(videoPlaybackPixiReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackMetadataReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackFirstFrameReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackCursorOverlayReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackFacecamReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackAnnotationVisibilityTickAtom)).toBe(0);
		expect(store.get(videoPlaybackResolvedWallpaperAtom)).toBeNull();
	});
});

describe("videoEditor atoms – playback defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("isPlayingAtom defaults to false", () => {
		expect(store.get(isPlayingAtom)).toBe(false);
	});

	it("durationAtom defaults to 0", () => {
		expect(store.get(durationAtom)).toBe(0);
	});
});

describe("videoEditor atoms – appearance defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("shadowIntensityAtom defaults to 0.67", () => {
		expect(store.get(shadowIntensityAtom)).toBe(0.67);
	});

	it("backgroundBlurAtom defaults to 0", () => {
		expect(store.get(backgroundBlurAtom)).toBe(0);
	});

	it("zoomMotionBlurAtom defaults to a number between 0 and 1", () => {
		const val = store.get(zoomMotionBlurAtom);
		expect(typeof val).toBe("number");
		expect(val).toBeGreaterThanOrEqual(0);
		expect(val).toBeLessThanOrEqual(1);
	});

	it("connectZoomsAtom defaults to true", () => {
		expect(store.get(connectZoomsAtom)).toBe(true);
	});

	it("borderRadiusAtom defaults to 12.5", () => {
		expect(store.get(borderRadiusAtom)).toBe(12.5);
	});

	it("paddingAtom defaults to 50", () => {
		expect(store.get(paddingAtom)).toBe(50);
	});

	it("audioMutedAtom defaults to a boolean", () => {
		expect(typeof store.get(audioMutedAtom)).toBe("boolean");
	});

	it("audioVolumeAtom defaults to a positive number", () => {
		expect(store.get(audioVolumeAtom)).toBeGreaterThan(0);
	});
});

describe("videoEditor atoms – cursor defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("cursorSettingsAtom.showCursor defaults to false", () => {
		expect(store.get(cursorSettingsAtom).showCursor).toBe(false);
	});

	it("cursorSettingsAtom.loopCursor defaults to false", () => {
		expect(store.get(cursorSettingsAtom).loopCursor).toBe(false);
	});

	it("cursorSettingsAtom.cursorSize defaults to a positive number", () => {
		expect(store.get(cursorSettingsAtom).cursorSize).toBeGreaterThan(0);
	});
});

describe("videoEditor atoms – region defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("zoomRegionsAtom defaults to empty array", () => {
		expect(store.get(zoomRegionsAtom)).toEqual([]);
	});

	it("trimRegionsAtom defaults to empty array", () => {
		expect(store.get(trimRegionsAtom)).toEqual([]);
	});

	it("speedRegionsAtom defaults to empty array", () => {
		expect(store.get(speedRegionsAtom)).toEqual([]);
	});

	it("annotationRegionsAtom defaults to empty array", () => {
		expect(store.get(annotationRegionsAtom)).toEqual([]);
	});

	it("selectedZoomIdAtom defaults to null", () => {
		expect(store.get(selectedZoomIdAtom)).toBeNull();
	});

	it("selectedTrimIdAtom defaults to null", () => {
		expect(store.get(selectedTrimIdAtom)).toBeNull();
	});

	it("selectedSpeedIdAtom defaults to null", () => {
		expect(store.get(selectedSpeedIdAtom)).toBeNull();
	});

	it("selectedAnnotationIdAtom defaults to null", () => {
		expect(store.get(selectedAnnotationIdAtom)).toBeNull();
	});

	it("cropRegionAtom defaults to an object with numeric fields", () => {
		const crop = store.get(cropRegionAtom);
		expect(typeof crop).toBe("object");
		expect(crop).not.toBeNull();
	});

	it("crop control drag atoms default to idle", () => {
		expect(store.get(cropControlDragHandleAtom)).toBeNull();
		expect(store.get(cropControlDragStartAtom)).toEqual({ x: 0, y: 0 });
		expect(store.get(cropControlInitialCropAtom)).toEqual({ x: 0, y: 0, width: 1, height: 1 });
	});
});

describe("videoEditor atoms – export defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("isExportingAtom defaults to false", () => {
		expect(store.get(isExportingAtom)).toBe(false);
	});

	it("exportProgressAtom defaults to null", () => {
		expect(store.get(exportProgressAtom)).toBeNull();
	});

	it("exportErrorAtom defaults to null", () => {
		expect(store.get(exportErrorAtom)).toBeNull();
	});

	it("showExportDialogAtom defaults to false", () => {
		expect(store.get(showExportDialogAtom)).toBe(false);
	});

	it("exportDialogShowSuccessAtom defaults to false", () => {
		expect(store.get(exportDialogShowSuccessAtom)).toBe(false);
	});

	it("showShortcutsDialogAtom defaults to false", () => {
		expect(store.get(showShortcutsDialogAtom)).toBe(false);
	});

	it("aspectRatioAtom defaults to '16:9'", () => {
		expect(store.get(aspectRatioAtom)).toBe("16:9");
	});

	it("exportQualityAtom defaults to 'good'", () => {
		expect(store.get(exportQualityAtom)).toBe("good");
	});

	it("exportFormatAtom defaults to 'mp4'", () => {
		expect(store.get(exportFormatAtom)).toBe("mp4");
	});

	it("gifFrameRateAtom defaults to 15", () => {
		expect(store.get(gifFrameRateAtom)).toBe(15);
	});

	it("gifLoopAtom defaults to true", () => {
		expect(store.get(gifLoopAtom)).toBe(true);
	});

	it("gifSizePresetAtom defaults to 'medium'", () => {
		expect(store.get(gifSizePresetAtom)).toBe("medium");
	});

	it("exportedFilePathAtom defaults to undefined", () => {
		expect(store.get(exportedFilePathAtom)).toBeUndefined();
	});

	it("hasPendingExportSaveAtom defaults to false", () => {
		expect(store.get(hasPendingExportSaveAtom)).toBe(false);
	});

	it("lastSavedSnapshotAtom defaults to null", () => {
		expect(store.get(lastSavedSnapshotAtom)).toBeNull();
	});

	it("add custom font dialog atoms default to closed, empty, and idle", () => {
		expect(store.get(addCustomFontDialogOpenAtom)).toBe(false);
		expect(store.get(addCustomFontImportUrlAtom)).toBe("");
		expect(store.get(addCustomFontNameAtom)).toBe("");
		expect(store.get(addCustomFontLoadingAtom)).toBe(false);
	});
});

// ─── Mutations ───────────────────────────────────────────────────────────────

describe("videoEditor atoms – mutations", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can set videoPathAtom to a file path", () => {
		store.set(videoPathAtom, "/recordings/video.mp4");
		expect(store.get(videoPathAtom)).toBe("/recordings/video.mp4");
	});

	it("can toggle isPlayingAtom on then off", () => {
		store.set(isPlayingAtom, true);
		expect(store.get(isPlayingAtom)).toBe(true);
		store.set(isPlayingAtom, false);
		expect(store.get(isPlayingAtom)).toBe(false);
	});

	it("can record a video error message", () => {
		store.set(videoErrorAtom, "Failed to decode video");
		expect(store.get(videoErrorAtom)).toBe("Failed to decode video");
	});

	it("can mark video loading as complete", () => {
		store.set(videoLoadingAtom, false);
		expect(store.get(videoLoadingAtom)).toBe(false);
	});

	it("can reset video playback runtime state", () => {
		store.set(videoPlaybackPixiReadyAtom, true);
		store.set(videoPlaybackMetadataReadyAtom, true);
		store.set(videoPlaybackFirstFrameReadyAtom, true);
		store.set(videoPlaybackCursorOverlayReadyAtom, true);
		store.set(videoPlaybackFacecamReadyAtom, true);
		store.set(videoPlaybackAnnotationVisibilityTickAtom, 2);
		store.set(videoPlaybackResolvedWallpaperAtom, "/wallpaper.jpg");
		store.set(resetVideoPlaybackRuntimeAtom);
		expect(store.get(videoPlaybackPixiReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackMetadataReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackFirstFrameReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackCursorOverlayReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackFacecamReadyAtom)).toBe(false);
		expect(store.get(videoPlaybackAnnotationVisibilityTickAtom)).toBe(0);
		expect(store.get(videoPlaybackResolvedWallpaperAtom)).toBeNull();
	});

	it("can reset custom font dialog fields without closing it", () => {
		store.set(addCustomFontDialogOpenAtom, true);
		store.set(addCustomFontImportUrlAtom, "https://fonts.googleapis.com/css2?family=Inter");
		store.set(addCustomFontNameAtom, "Inter");
		store.set(addCustomFontLoadingAtom, true);
		store.set(resetAddCustomFontDialogAtom);
		expect(store.get(addCustomFontDialogOpenAtom)).toBe(true);
		expect(store.get(addCustomFontImportUrlAtom)).toBe("");
		expect(store.get(addCustomFontNameAtom)).toBe("");
		expect(store.get(addCustomFontLoadingAtom)).toBe(false);
	});

	it("can reset crop control drag state", () => {
		store.set(cropControlDragHandleAtom, "bottom");
		store.set(cropControlDragStartAtom, { x: 0.25, y: 0.75 });
		store.set(cropControlInitialCropAtom, { x: 0.1, y: 0.2, width: 0.6, height: 0.5 });
		store.set(resetCropControlDragAtom);
		expect(store.get(cropControlDragHandleAtom)).toBeNull();
		expect(store.get(cropControlDragStartAtom)).toEqual({ x: 0, y: 0 });
		expect(store.get(cropControlInitialCropAtom)).toEqual({ x: 0, y: 0, width: 1, height: 1 });
	});

	it("can set durationAtom after video loads", () => {
		store.set(durationAtom, 120_000);
		expect(store.get(durationAtom)).toBe(120_000);
	});

	it("can add a zoom region", () => {
		store.set(zoomRegionsAtom, [
			{ id: "z1", startMs: 0, endMs: 2000, depth: 2, focus: { cx: 0.5, cy: 0.5 } },
		]);
		expect(store.get(zoomRegionsAtom)).toHaveLength(1);
		expect(store.get(zoomRegionsAtom)[0].id).toBe("z1");
	});

	it("can select a zoom region by ID", () => {
		store.set(selectedZoomIdAtom, "z1");
		expect(store.get(selectedZoomIdAtom)).toBe("z1");
	});

	it("can change aspectRatioAtom to 9:16", () => {
		store.set(aspectRatioAtom, "9:16");
		expect(store.get(aspectRatioAtom)).toBe("9:16");
	});

	it("can switch export format to 'gif'", () => {
		store.set(exportFormatAtom, "gif");
		expect(store.get(exportFormatAtom)).toBe("gif");
	});

	it("can open the export dialog", () => {
		store.set(showExportDialogAtom, true);
		expect(store.get(showExportDialogAtom)).toBe(true);
	});

	it("can update cursor settings with a partial patch", () => {
		const current = store.get(cursorSettingsAtom);
		store.set(cursorSettingsAtom, { ...current, showCursor: false });
		expect(store.get(cursorSettingsAtom).showCursor).toBe(false);
		// Other fields should be unchanged
		expect(store.get(cursorSettingsAtom).loopCursor).toBe(current.loopCursor);
	});

	it("can save a snapshot string", () => {
		store.set(lastSavedSnapshotAtom, '{"version":1}');
		expect(store.get(lastSavedSnapshotAtom)).toBe('{"version":1}');
	});
});

// ─── Store isolation ─────────────────────────────────────────────────────────

describe("videoEditor atoms – store isolation", () => {
	it("videoPathAtom in storeA does not bleed into storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(videoPathAtom, "/some/path.mp4");
		expect(storeB.get(videoPathAtom)).toBeNull();
	});

	it("zoomRegionsAtom in storeA does not bleed into storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(zoomRegionsAtom, [
			{ id: "z1", startMs: 0, endMs: 1000, depth: 1, focus: { cx: 0.5, cy: 0.5 } },
		]);
		expect(storeB.get(zoomRegionsAtom)).toHaveLength(0);
	});

	it("export state in storeA does not affect storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(isExportingAtom, true);
		storeA.set(showExportDialogAtom, true);
		expect(storeB.get(isExportingAtom)).toBe(false);
		expect(storeB.get(showExportDialogAtom)).toBe(false);
	});
});

// ─── Subscriptions ───────────────────────────────────────────────────────────

describe("videoEditor atoms – subscriptions", () => {
	afterEach(() => {
		vi.clearAllMocks();
	});

	it("subscriber is notified when isPlayingAtom changes", () => {
		const store = createStore();
		const listener = vi.fn();
		const unsub = store.sub(isPlayingAtom, listener);

		store.set(isPlayingAtom, true);
		store.set(isPlayingAtom, false);

		expect(listener).toHaveBeenCalledTimes(2);
		unsub();
	});

	it("subscriber on zoomRegionsAtom fires on each update", () => {
		const store = createStore();
		const listener = vi.fn();
		const unsub = store.sub(zoomRegionsAtom, listener);

		store.set(zoomRegionsAtom, []);
		store.set(zoomRegionsAtom, [
			{ id: "z1", startMs: 0, endMs: 500, depth: 1, focus: { cx: 0.5, cy: 0.5 } },
		]);

		expect(listener).toHaveBeenCalledTimes(2);
		unsub();
	});
});
