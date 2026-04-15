/**
 * Integration tests: Video Editor Workflow
 *
 * Verifies multi-atom workflows for the video editor:
 *   load video → set trim points → change speed → toggle audio → export settings consistent
 */

import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
	annotationRegionsAtom,
	aspectRatioAtom,
	audioMutedAtom,
	audioVolumeAtom,
	backgroundBlurAtom,
	borderRadiusAtom,
	connectZoomsAtom,
	cropRegionAtom,
	cursorSettingsAtom,
	durationAtom,
	exportErrorAtom,
	exportFormatAtom,
	exportProgressAtom,
	exportQualityAtom,
	facecamSettingsAtom,
	gifFrameRateAtom,
	gifLoopAtom,
	gifSizePresetAtom,
	hasPendingExportSaveAtom,
	isExportingAtom,
	isPlayingAtom,
	paddingAtom,
	playbackReadyAtom,
	selectedAnnotationIdAtom,
	selectedSpeedIdAtom,
	selectedTrimIdAtom,
	selectedZoomIdAtom,
	shadowIntensityAtom,
	showExportDialogAtom,
	speedRegionsAtom,
	trimRegionsAtom,
	videoErrorAtom,
	videoLoadingAtom,
	videoPathAtom,
	videoSourcePathAtom,
	zoomRegionsAtom,
} from "@/atoms/videoEditor";

function makeFreshStore() {
	return createStore();
}

// ---------------------------------------------------------------------------
// Video loading
// ---------------------------------------------------------------------------

describe("video editor – video loading", () => {
	it("videoLoading starts as true and becomes false when ready", () => {
		const store = makeFreshStore();
		expect(store.get(videoLoadingAtom)).toBe(true);

		store.set(videoPathAtom, "/recordings/session.mp4");
		store.set(videoLoadingAtom, false);
		store.set(playbackReadyAtom, true);

		expect(store.get(videoLoadingAtom)).toBe(false);
		expect(store.get(playbackReadyAtom)).toBe(true);
	});

	it("videoPath and videoSourcePath are set together on load", () => {
		const store = makeFreshStore();
		store.set(videoPathAtom, "/recordings/output.mp4");
		store.set(videoSourcePathAtom, "/recordings/source.mp4");

		expect(store.get(videoPathAtom)).toBe("/recordings/output.mp4");
		expect(store.get(videoSourcePathAtom)).toBe("/recordings/source.mp4");
	});

	it("duration is updated once the video is decoded", () => {
		const store = makeFreshStore();
		store.set(durationAtom, 120_000); // 2 minutes in ms
		expect(store.get(durationAtom)).toBe(120_000);
	});

	it("videoError is set when loading fails", () => {
		const store = makeFreshStore();
		store.set(videoErrorAtom, "Failed to decode video");
		store.set(videoLoadingAtom, false);

		expect(store.get(videoErrorAtom)).toBe("Failed to decode video");
		expect(store.get(videoLoadingAtom)).toBe(false);
	});

	it("playback can start after loading completes", () => {
		const store = makeFreshStore();
		store.set(videoLoadingAtom, false);
		store.set(playbackReadyAtom, true);
		store.set(isPlayingAtom, true);

		expect(store.get(isPlayingAtom)).toBe(true);
	});
});

// ---------------------------------------------------------------------------
// Trim regions
// ---------------------------------------------------------------------------

describe("video editor – trim workflow", () => {
	it("adding a trim region updates trimRegionsAtom", () => {
		const store = makeFreshStore();
		store.set(trimRegionsAtom, [{ id: "trim-1", startMs: 2000, endMs: 8000 }]);
		expect(store.get(trimRegionsAtom)).toHaveLength(1);
		expect(store.get(trimRegionsAtom)[0].startMs).toBe(2000);
	});

	it("selecting a trim region updates selectedTrimIdAtom", () => {
		const store = makeFreshStore();
		store.set(trimRegionsAtom, [{ id: "trim-1", startMs: 0, endMs: 5000 }]);
		store.set(selectedTrimIdAtom, "trim-1");
		expect(store.get(selectedTrimIdAtom)).toBe("trim-1");
	});

	it("multiple trim regions can be added", () => {
		const store = makeFreshStore();
		store.set(trimRegionsAtom, [
			{ id: "trim-1", startMs: 0, endMs: 3000 },
			{ id: "trim-2", startMs: 10000, endMs: 15000 },
		]);
		expect(store.get(trimRegionsAtom)).toHaveLength(2);
	});

	it("removing a trim region leaves others intact", () => {
		const store = makeFreshStore();
		store.set(trimRegionsAtom, [
			{ id: "trim-1", startMs: 0, endMs: 3000 },
			{ id: "trim-2", startMs: 10000, endMs: 15000 },
		]);
		store.set(
			trimRegionsAtom,
			store.get(trimRegionsAtom).filter((r) => r.id !== "trim-1"),
		);
		expect(store.get(trimRegionsAtom)).toHaveLength(1);
		expect(store.get(trimRegionsAtom)[0].id).toBe("trim-2");
	});
});

// ---------------------------------------------------------------------------
// Speed regions
// ---------------------------------------------------------------------------

describe("video editor – speed change workflow", () => {
	it("adding a speed region updates speedRegionsAtom", () => {
		const store = makeFreshStore();
		store.set(speedRegionsAtom, [{ id: "speed-1", startMs: 5000, endMs: 20000, speed: 2 }]);
		expect(store.get(speedRegionsAtom)).toHaveLength(1);
		expect(store.get(speedRegionsAtom)[0].speed).toBe(2);
	});

	it("selecting a speed region updates selectedSpeedIdAtom", () => {
		const store = makeFreshStore();
		store.set(speedRegionsAtom, [{ id: "speed-1", startMs: 0, endMs: 5000, speed: 1.5 }]);
		store.set(selectedSpeedIdAtom, "speed-1");
		expect(store.get(selectedSpeedIdAtom)).toBe("speed-1");
	});

	it("slow-down speed region (0.5x) is stored correctly", () => {
		const store = makeFreshStore();
		store.set(speedRegionsAtom, [{ id: "slow-1", startMs: 1000, endMs: 4000, speed: 0.5 }]);
		expect(store.get(speedRegionsAtom)[0].speed).toBe(0.5);
	});
});

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------

describe("video editor – audio workflow", () => {
	it("toggling audio mute updates audioMutedAtom", () => {
		const store = makeFreshStore();
		expect(store.get(audioMutedAtom)).toBe(false);

		store.set(audioMutedAtom, true);
		expect(store.get(audioMutedAtom)).toBe(true);

		store.set(audioMutedAtom, false);
		expect(store.get(audioMutedAtom)).toBe(false);
	});

	it("setting volume level updates audioVolumeAtom", () => {
		const store = makeFreshStore();
		store.set(audioVolumeAtom, 0.5);
		expect(store.get(audioVolumeAtom)).toBe(0.5);
	});

	it("muting does not change volume atom value", () => {
		const store = makeFreshStore();
		store.set(audioVolumeAtom, 0.8);
		store.set(audioMutedAtom, true);

		expect(store.get(audioVolumeAtom)).toBe(0.8);
		expect(store.get(audioMutedAtom)).toBe(true);
	});
});

// ---------------------------------------------------------------------------
// Appearance settings
// ---------------------------------------------------------------------------

describe("video editor – appearance settings", () => {
	it("shadow intensity can be adjusted", () => {
		const store = makeFreshStore();
		store.set(shadowIntensityAtom, 0.9);
		expect(store.get(shadowIntensityAtom)).toBe(0.9);
	});

	it("background blur can be increased", () => {
		const store = makeFreshStore();
		store.set(backgroundBlurAtom, 20);
		expect(store.get(backgroundBlurAtom)).toBe(20);
	});

	it("padding can be changed", () => {
		const store = makeFreshStore();
		store.set(paddingAtom, 80);
		expect(store.get(paddingAtom)).toBe(80);
	});

	it("border radius can be changed", () => {
		const store = makeFreshStore();
		store.set(borderRadiusAtom, 24);
		expect(store.get(borderRadiusAtom)).toBe(24);
	});

	it("cursor settings update as a composite object", () => {
		const store = makeFreshStore();
		store.set(cursorSettingsAtom, {
			showCursor: false,
			loopCursor: true,
			cursorSize: 5,
			cursorSmoothing: 0.9,
			cursorMotionBlur: 0.5,
			cursorClickBounce: 3.0,
		});

		const settings = store.get(cursorSettingsAtom);
		expect(settings.showCursor).toBe(false);
		expect(settings.cursorSize).toBe(5);
		expect(settings.loopCursor).toBe(true);
	});

	it("crop region can be updated to a sub-region", () => {
		const store = makeFreshStore();
		store.set(cropRegionAtom, { x: 0.1, y: 0.1, width: 0.8, height: 0.8 });
		const crop = store.get(cropRegionAtom);
		expect(crop.x).toBe(0.1);
		expect(crop.width).toBe(0.8);
	});
});

// ---------------------------------------------------------------------------
// Zoom regions
// ---------------------------------------------------------------------------

describe("video editor – zoom regions", () => {
	it("adding zoom region updates zoomRegionsAtom", () => {
		const store = makeFreshStore();
		store.set(zoomRegionsAtom, [
			{ id: "zoom-1", startMs: 0, endMs: 3000, depth: 3, focus: { cx: 0.5, cy: 0.5 } },
		]);
		expect(store.get(zoomRegionsAtom)).toHaveLength(1);
	});

	it("selecting zoom region updates selectedZoomIdAtom", () => {
		const store = makeFreshStore();
		store.set(selectedZoomIdAtom, "zoom-1");
		expect(store.get(selectedZoomIdAtom)).toBe("zoom-1");
	});

	it("connectZooms toggle works", () => {
		const store = makeFreshStore();
		expect(store.get(connectZoomsAtom)).toBe(true);
		store.set(connectZoomsAtom, false);
		expect(store.get(connectZoomsAtom)).toBe(false);
	});
});

// ---------------------------------------------------------------------------
// Annotation regions
// ---------------------------------------------------------------------------

describe("video editor – annotation workflow", () => {
	it("adding an annotation stores it in annotationRegionsAtom", () => {
		const store = makeFreshStore();
		store.set(annotationRegionsAtom, [
			{
				id: "ann-1",
				startMs: 1000,
				endMs: 5000,
				type: "text",
				text: "Hello World",
				position: { x: 0.5, y: 0.5 },
				size: { width: 200, height: 50 },
				style: {},
			} as never,
		]);
		expect(store.get(annotationRegionsAtom)).toHaveLength(1);
	});

	it("selecting annotation updates selectedAnnotationIdAtom", () => {
		const store = makeFreshStore();
		store.set(selectedAnnotationIdAtom, "ann-1");
		expect(store.get(selectedAnnotationIdAtom)).toBe("ann-1");
	});
});

// ---------------------------------------------------------------------------
// Export settings consistency
// ---------------------------------------------------------------------------

describe("video editor – export settings consistency", () => {
	it("export format mp4 is the default", () => {
		const store = makeFreshStore();
		expect(store.get(exportFormatAtom)).toBe("mp4");
	});

	it("switching to gif format updates exportFormatAtom", () => {
		const store = makeFreshStore();
		store.set(exportFormatAtom, "gif");
		expect(store.get(exportFormatAtom)).toBe("gif");
	});

	it("export quality can be changed to medium", () => {
		const store = makeFreshStore();
		store.set(exportQualityAtom, "medium");
		expect(store.get(exportQualityAtom)).toBe("medium");
	});

	it("aspect ratio can be changed to 4:3", () => {
		const store = makeFreshStore();
		store.set(aspectRatioAtom, "4:3");
		expect(store.get(aspectRatioAtom)).toBe("4:3");
	});

	it("gif frame rate can be set to 30", () => {
		const store = makeFreshStore();
		store.set(gifFrameRateAtom, 30);
		expect(store.get(gifFrameRateAtom)).toBe(30);
	});

	it("gif loop toggle works", () => {
		const store = makeFreshStore();
		store.set(gifLoopAtom, false);
		expect(store.get(gifLoopAtom)).toBe(false);
	});

	it("gif size preset can be changed to large", () => {
		const store = makeFreshStore();
		store.set(gifSizePresetAtom, "large");
		expect(store.get(gifSizePresetAtom)).toBe("large");
	});

	it("opening export dialog sets showExportDialogAtom", () => {
		const store = makeFreshStore();
		store.set(showExportDialogAtom, true);
		expect(store.get(showExportDialogAtom)).toBe(true);
	});

	it("exporting sets isExportingAtom and tracks progress", () => {
		const store = makeFreshStore();
		store.set(isExportingAtom, true);
		store.set(exportProgressAtom, { stage: "encoding", framesTotal: 100, framesEncoded: 50 } as never);

		expect(store.get(isExportingAtom)).toBe(true);
		expect((store.get(exportProgressAtom) as { framesEncoded: number } | null)?.framesEncoded).toBe(50);
	});

	it("export error is stored when export fails", () => {
		const store = makeFreshStore();
		store.set(isExportingAtom, false);
		store.set(exportErrorAtom, "Disk full");
		expect(store.get(exportErrorAtom)).toBe("Disk full");
	});

	it("hasPendingExportSave is true after export if not yet saved", () => {
		const store = makeFreshStore();
		store.set(hasPendingExportSaveAtom, true);
		expect(store.get(hasPendingExportSaveAtom)).toBe(true);
	});

	it("full export workflow: all settings are consistent together", () => {
		const store = makeFreshStore();

		store.set(videoPathAtom, "/output/final.mp4");
		store.set(durationAtom, 60_000);
		store.set(exportFormatAtom, "mp4");
		store.set(exportQualityAtom, "good");
		store.set(aspectRatioAtom, "16:9");
		store.set(audioMutedAtom, false);
		store.set(audioVolumeAtom, 1);
		store.set(trimRegionsAtom, [{ id: "t1", startMs: 5000, endMs: 55000 }]);
		store.set(showExportDialogAtom, true);

		expect(store.get(videoPathAtom)).toBe("/output/final.mp4");
		expect(store.get(exportFormatAtom)).toBe("mp4");
		expect(store.get(exportQualityAtom)).toBe("good");
		expect(store.get(aspectRatioAtom)).toBe("16:9");
		expect(store.get(trimRegionsAtom)).toHaveLength(1);
		expect(store.get(showExportDialogAtom)).toBe(true);
	});

	it("facecam settings can be updated without affecting video export atoms", () => {
		const store = makeFreshStore();
		store.set(facecamSettingsAtom, {
			enabled: true,
			shape: "circle",
			size: 25,
			cornerRadius: 30,
			borderWidth: 2,
			borderColor: "#FF0000",
			margin: 8,
			anchor: "bottom-left",
		});
		store.set(exportFormatAtom, "mp4");

		expect(store.get(facecamSettingsAtom).enabled).toBe(true);
		expect(store.get(facecamSettingsAtom).anchor).toBe("bottom-left");
		expect(store.get(exportFormatAtom)).toBe("mp4");
	});
});
