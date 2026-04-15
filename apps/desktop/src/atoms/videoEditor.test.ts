import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import type { AnnotationRegion, CropRegion, SpeedRegion, TrimRegion, ZoomRegion } from "@/components/video-editor/types";
import type { ExportProgress } from "@/lib/exporter";
import type { AspectRatio } from "@/utils/aspectRatioUtils";
import {
  annotationRegionsAtom,
  aspectRatioAtom,
  audioMutedAtom,
  audioVolumeAtom,
  backgroundBlurAtom,
  borderRadiusAtom,
  connectZoomsAtom,
  cropRegionAtom,
  currentProjectPathAtom,
  cursorSettingsAtom,
  type CursorSettings,
  durationAtom,
  exportErrorAtom,
  exportFormatAtom,
  exportProgressAtom,
  exportQualityAtom,
  exportedFilePathAtom,
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
  videoSourcePathAtom,
  zoomMotionBlurAtom,
  zoomRegionsAtom,
} from "./videoEditor";

// ─── Video source atoms ────────────────────────────────────────────────────

describe("videoEditor atoms – video source", () => {
  it("videoPathAtom can be set to a file path", () => {
    const store = createStore();
    store.set(videoPathAtom, "/recordings/session.mp4");
    expect(store.get(videoPathAtom)).toBe("/recordings/session.mp4");
  });

  it("videoPathAtom can be cleared to null", () => {
    const store = createStore();
    store.set(videoPathAtom, "/recordings/session.mp4");
    store.set(videoPathAtom, null);
    expect(store.get(videoPathAtom)).toBeNull();
  });

  it("videoSourcePathAtom can be set independently of videoPathAtom", () => {
    const store = createStore();
    store.set(videoPathAtom, "/recordings/session.mp4");
    store.set(videoSourcePathAtom, "/recordings/original.mp4");
    expect(store.get(videoPathAtom)).toBe("/recordings/session.mp4");
    expect(store.get(videoSourcePathAtom)).toBe("/recordings/original.mp4");
  });

  it("sourceNameAtom can be set to a display name", () => {
    const store = createStore();
    store.set(sourceNameAtom, "Zoom Meeting");
    expect(store.get(sourceNameAtom)).toBe("Zoom Meeting");
  });

  it("facecamVideoPathAtom can be set and cleared", () => {
    const store = createStore();
    store.set(facecamVideoPathAtom, "/facecam/face.mp4");
    expect(store.get(facecamVideoPathAtom)).toBe("/facecam/face.mp4");
    store.set(facecamVideoPathAtom, null);
    expect(store.get(facecamVideoPathAtom)).toBeNull();
  });

  it("facecamPlaybackPathAtom can be set independently", () => {
    const store = createStore();
    store.set(facecamPlaybackPathAtom, "/facecam/playback.mp4");
    expect(store.get(facecamPlaybackPathAtom)).toBe("/facecam/playback.mp4");
  });

  it("facecamOffsetMsAtom accepts positive and negative offsets", () => {
    const store = createStore();
    store.set(facecamOffsetMsAtom, 250);
    expect(store.get(facecamOffsetMsAtom)).toBe(250);
    store.set(facecamOffsetMsAtom, -500);
    expect(store.get(facecamOffsetMsAtom)).toBe(-500);
  });

  it("currentProjectPathAtom can be set to a project directory", () => {
    const store = createStore();
    store.set(currentProjectPathAtom, "/projects/my-project");
    expect(store.get(currentProjectPathAtom)).toBe("/projects/my-project");
  });
});

// ─── Loading / error state atoms ──────────────────────────────────────────

describe("videoEditor atoms – loading and error state", () => {
  it("videoLoadingAtom can be set to false once loaded", () => {
    const store = createStore();
    store.set(videoLoadingAtom, false);
    expect(store.get(videoLoadingAtom)).toBe(false);
  });

  it("playbackReadyAtom can be set to true when ready", () => {
    const store = createStore();
    store.set(playbackReadyAtom, true);
    expect(store.get(playbackReadyAtom)).toBe(true);
  });

  it("videoErrorAtom can be set to an error message", () => {
    const store = createStore();
    store.set(videoErrorAtom, "Failed to decode video");
    expect(store.get(videoErrorAtom)).toBe("Failed to decode video");
  });

  it("videoErrorAtom can be cleared after recovery", () => {
    const store = createStore();
    store.set(videoErrorAtom, "Decoding error");
    store.set(videoErrorAtom, null);
    expect(store.get(videoErrorAtom)).toBeNull();
  });
});

// ─── Playback state atoms ─────────────────────────────────────────────────

describe("videoEditor atoms – playback state", () => {
  it("isPlayingAtom can be toggled to true and false", () => {
    const store = createStore();
    store.set(isPlayingAtom, true);
    expect(store.get(isPlayingAtom)).toBe(true);
    store.set(isPlayingAtom, false);
    expect(store.get(isPlayingAtom)).toBe(false);
  });

  it("durationAtom can be set to a positive number of milliseconds", () => {
    const store = createStore();
    store.set(durationAtom, 120_000); // 2 minutes
    expect(store.get(durationAtom)).toBe(120_000);
  });
});

// ─── Appearance setting atoms ─────────────────────────────────────────────

describe("videoEditor atoms – appearance settings", () => {
  it("audioMutedAtom can be toggled", () => {
    const store = createStore();
    store.set(audioMutedAtom, true);
    expect(store.get(audioMutedAtom)).toBe(true);
  });

  it("audioVolumeAtom accepts values from 0 to 1", () => {
    const store = createStore();
    for (const vol of [0, 0.25, 0.5, 0.75, 1]) {
      store.set(audioVolumeAtom, vol);
      expect(store.get(audioVolumeAtom)).toBe(vol);
    }
  });

  it("shadowIntensityAtom can be set to boundary values 0 and 1", () => {
    const store = createStore();
    store.set(shadowIntensityAtom, 0);
    expect(store.get(shadowIntensityAtom)).toBe(0);
    store.set(shadowIntensityAtom, 1);
    expect(store.get(shadowIntensityAtom)).toBe(1);
  });

  it("backgroundBlurAtom can be set to non-zero values", () => {
    const store = createStore();
    store.set(backgroundBlurAtom, 20);
    expect(store.get(backgroundBlurAtom)).toBe(20);
  });

  it("zoomMotionBlurAtom can be adjusted", () => {
    const store = createStore();
    store.set(zoomMotionBlurAtom, 0);
    expect(store.get(zoomMotionBlurAtom)).toBe(0);
    store.set(zoomMotionBlurAtom, 1);
    expect(store.get(zoomMotionBlurAtom)).toBe(1);
  });

  it("borderRadiusAtom can be set to 0 (sharp corners)", () => {
    const store = createStore();
    store.set(borderRadiusAtom, 0);
    expect(store.get(borderRadiusAtom)).toBe(0);
  });

  it("paddingAtom can be set to 0 (no padding)", () => {
    const store = createStore();
    store.set(paddingAtom, 0);
    expect(store.get(paddingAtom)).toBe(0);
  });

  it("connectZoomsAtom can be disabled", () => {
    const store = createStore();
    store.set(connectZoomsAtom, false);
    expect(store.get(connectZoomsAtom)).toBe(false);
  });
});

// ─── Cursor settings atom ─────────────────────────────────────────────────

describe("videoEditor atoms – cursor settings", () => {
  it("cursorSettingsAtom can be updated with partial values", () => {
    const store = createStore();
    const before = store.get(cursorSettingsAtom);
    const updated: CursorSettings = { ...before, showCursor: false };
    store.set(cursorSettingsAtom, updated);
    expect(store.get(cursorSettingsAtom).showCursor).toBe(false);
  });

  it("cursorSettingsAtom can enable loopCursor", () => {
    const store = createStore();
    const before = store.get(cursorSettingsAtom);
    store.set(cursorSettingsAtom, { ...before, loopCursor: true });
    expect(store.get(cursorSettingsAtom).loopCursor).toBe(true);
  });

  it("cursorSettingsAtom preserves unmodified fields when one field changes", () => {
    const store = createStore();
    const before = store.get(cursorSettingsAtom);
    store.set(cursorSettingsAtom, { ...before, cursorSize: 5 });
    const after = store.get(cursorSettingsAtom);
    expect(after.cursorSize).toBe(5);
    expect(after.showCursor).toBe(before.showCursor);
    expect(after.loopCursor).toBe(before.loopCursor);
    expect(after.cursorSmoothing).toBe(before.cursorSmoothing);
  });
});

// ─── Region / selection atoms ─────────────────────────────────────────────

describe("videoEditor atoms – regions and selections", () => {
  it("cropRegionAtom can be updated to a custom crop", () => {
    const crop: CropRegion = { x: 0.1, y: 0.1, width: 0.8, height: 0.8 };
    const store = createStore();
    store.set(cropRegionAtom, crop);
    expect(store.get(cropRegionAtom)).toEqual(crop);
  });

  it("zoomRegionsAtom can have a region added", () => {
    const store = createStore();
    const region: ZoomRegion = {
      id: "z1",
      startMs: 0,
      endMs: 1000,
      depth: 2,
      focus: { cx: 0.5, cy: 0.5 },
    };
    store.set(zoomRegionsAtom, [region]);
    expect(store.get(zoomRegionsAtom)).toHaveLength(1);
    expect(store.get(zoomRegionsAtom)[0].id).toBe("z1");
  });

  it("selectedZoomIdAtom can be set and cleared", () => {
    const store = createStore();
    store.set(selectedZoomIdAtom, "z1");
    expect(store.get(selectedZoomIdAtom)).toBe("z1");
    store.set(selectedZoomIdAtom, null);
    expect(store.get(selectedZoomIdAtom)).toBeNull();
  });

  it("trimRegionsAtom can have a trim region added", () => {
    const store = createStore();
    const trim: TrimRegion = { id: "t1", startMs: 500, endMs: 1500 };
    store.set(trimRegionsAtom, [trim]);
    expect(store.get(trimRegionsAtom)).toHaveLength(1);
    expect(store.get(trimRegionsAtom)[0]).toEqual(trim);
  });

  it("selectedTrimIdAtom can be set and cleared", () => {
    const store = createStore();
    store.set(selectedTrimIdAtom, "t1");
    expect(store.get(selectedTrimIdAtom)).toBe("t1");
    store.set(selectedTrimIdAtom, null);
    expect(store.get(selectedTrimIdAtom)).toBeNull();
  });

  it("speedRegionsAtom can have a speed region added", () => {
    const store = createStore();
    const speed: SpeedRegion = { id: "s1", startMs: 0, endMs: 2000, speed: 2 };
    store.set(speedRegionsAtom, [speed]);
    expect(store.get(speedRegionsAtom)).toHaveLength(1);
  });

  it("annotationRegionsAtom can have multiple annotations added", () => {
    const store = createStore();
    const a1 = { id: "a1" } as AnnotationRegion;
    const a2 = { id: "a2" } as AnnotationRegion;
    store.set(annotationRegionsAtom, [a1, a2]);
    expect(store.get(annotationRegionsAtom)).toHaveLength(2);
  });

  it("selectedAnnotationIdAtom can be set and cleared", () => {
    const store = createStore();
    store.set(selectedAnnotationIdAtom, "a1");
    expect(store.get(selectedAnnotationIdAtom)).toBe("a1");
    store.set(selectedAnnotationIdAtom, null);
    expect(store.get(selectedAnnotationIdAtom)).toBeNull();
  });
});

// ─── Export state atoms ───────────────────────────────────────────────────

describe("videoEditor atoms – export state", () => {
  it("isExportingAtom can be set to true during export", () => {
    const store = createStore();
    store.set(isExportingAtom, true);
    expect(store.get(isExportingAtom)).toBe(true);
  });

  it("exportProgressAtom can be set to a progress object", () => {
    const store = createStore();
    const progress: ExportProgress = { framesRendered: 10, totalFrames: 100 };
    store.set(exportProgressAtom, progress);
    expect(store.get(exportProgressAtom)).toEqual(progress);
  });

  it("exportProgressAtom can be cleared after export finishes", () => {
    const store = createStore();
    store.set(exportProgressAtom, { framesRendered: 100, totalFrames: 100 });
    store.set(exportProgressAtom, null);
    expect(store.get(exportProgressAtom)).toBeNull();
  });

  it("exportErrorAtom can be set and cleared", () => {
    const store = createStore();
    store.set(exportErrorAtom, "Write failed");
    expect(store.get(exportErrorAtom)).toBe("Write failed");
    store.set(exportErrorAtom, null);
    expect(store.get(exportErrorAtom)).toBeNull();
  });

  it("showExportDialogAtom can be opened and closed", () => {
    const store = createStore();
    store.set(showExportDialogAtom, true);
    expect(store.get(showExportDialogAtom)).toBe(true);
    store.set(showExportDialogAtom, false);
    expect(store.get(showExportDialogAtom)).toBe(false);
  });

  it("showShortcutsDialogAtom can be opened and closed", () => {
    const store = createStore();
    store.set(showShortcutsDialogAtom, true);
    expect(store.get(showShortcutsDialogAtom)).toBe(true);
    store.set(showShortcutsDialogAtom, false);
    expect(store.get(showShortcutsDialogAtom)).toBe(false);
  });

  it("aspectRatioAtom accepts all common aspect ratios", () => {
    const ratios: AspectRatio[] = ["16:9", "9:16", "1:1", "4:3", "custom"];
    const store = createStore();
    for (const ratio of ratios) {
      store.set(aspectRatioAtom, ratio);
      expect(store.get(aspectRatioAtom)).toBe(ratio);
    }
  });

  it("exportQualityAtom can be changed to low or high", () => {
    const store = createStore();
    store.set(exportQualityAtom, "low");
    expect(store.get(exportQualityAtom)).toBe("low");
    store.set(exportQualityAtom, "high");
    expect(store.get(exportQualityAtom)).toBe("high");
  });

  it("exportFormatAtom can be set to gif", () => {
    const store = createStore();
    store.set(exportFormatAtom, "gif");
    expect(store.get(exportFormatAtom)).toBe("gif");
  });

  it("gifFrameRateAtom can be set to supported values", () => {
    const store = createStore();
    store.set(gifFrameRateAtom, 10);
    expect(store.get(gifFrameRateAtom)).toBe(10);
    store.set(gifFrameRateAtom, 30);
    expect(store.get(gifFrameRateAtom)).toBe(30);
  });

  it("gifLoopAtom can be disabled", () => {
    const store = createStore();
    store.set(gifLoopAtom, false);
    expect(store.get(gifLoopAtom)).toBe(false);
  });

  it("gifSizePresetAtom can be changed", () => {
    const store = createStore();
    store.set(gifSizePresetAtom, "large");
    expect(store.get(gifSizePresetAtom)).toBe("large");
    store.set(gifSizePresetAtom, "small");
    expect(store.get(gifSizePresetAtom)).toBe("small");
  });

  it("exportedFilePathAtom can be set after a successful export", () => {
    const store = createStore();
    store.set(exportedFilePathAtom, "/exports/output.mp4");
    expect(store.get(exportedFilePathAtom)).toBe("/exports/output.mp4");
  });

  it("hasPendingExportSaveAtom can be toggled", () => {
    const store = createStore();
    store.set(hasPendingExportSaveAtom, true);
    expect(store.get(hasPendingExportSaveAtom)).toBe(true);
  });

  it("lastSavedSnapshotAtom can store a JSON snapshot string", () => {
    const store = createStore();
    const snapshot = JSON.stringify({ version: 1, data: "abc" });
    store.set(lastSavedSnapshotAtom, snapshot);
    expect(store.get(lastSavedSnapshotAtom)).toBe(snapshot);
  });
});

// ─── Store isolation ──────────────────────────────────────────────────────

describe("videoEditor atoms – store isolation", () => {
  it("writes to one store do not bleed into another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    storeA.set(videoPathAtom, "/recordings/a.mp4");
    storeA.set(isPlayingAtom, true);
    storeA.set(durationAtom, 60_000);
    storeA.set(isExportingAtom, true);
    storeA.set(aspectRatioAtom, "1:1");

    expect(storeB.get(videoPathAtom)).toBeNull();
    expect(storeB.get(isPlayingAtom)).toBe(false);
    expect(storeB.get(durationAtom)).toBe(0);
    expect(storeB.get(isExportingAtom)).toBe(false);
    expect(storeB.get(aspectRatioAtom)).toBe("16:9");
  });
});
