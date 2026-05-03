/**
 * Integration tests: Multi-Window State Isolation
 *
 * Verifies that two independent Jotai stores do not share state.
 * This mirrors the Provider-isolation approach used in the desktop app
 * where each window (hud-overlay, source-selector, editor) gets its own store.
 */

import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import { appNameAtom, isMacOSAtom, windowTypeAtom } from "@/atoms/app";
import { createDefaultZoomEasing } from "@/components/video-editor/types";
import {
	imageBackgroundTypeAtom,
	imageBorderRadiusAtom,
	imagePaddingAtom,
	imageShadowIntensityAtom,
} from "@/atoms/imageEditor";
import {
	hasSelectedSourceAtom,
	launchViewAtom,
	recordingElapsedAtom,
	recordingStartAtom,
	selectedSourceAtom,
} from "@/atoms/launch";
import { isCheckingPermissionsAtom, permissionsAtom } from "@/atoms/permissions";
import {
	cameraEnabledAtom,
	microphoneEnabledAtom,
	recordingActiveAtom,
	systemAudioEnabledAtom,
} from "@/atoms/recording";
import {
	settingsActiveTabAtom,
	settingsSelectedColorAtom,
} from "@/atoms/settingsPanel";
import {
	selectedDesktopSourceAtom,
	sourceSelectorTabAtom,
	sourcesAtom,
} from "@/atoms/sourceSelector";
import {
	aspectRatioAtom,
	audioMutedAtom,
	borderRadiusAtom,
	exportFormatAtom,
	exportQualityAtom,
	isExportingAtom,
	isPlayingAtom,
	paddingAtom,
	shadowIntensityAtom,
	trimRegionsAtom,
	videoPathAtom,
	zoomRegionsAtom,
} from "@/atoms/videoEditor";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeTwoStores() {
	return { storeA: createStore(), storeB: createStore() };
}

// ---------------------------------------------------------------------------
// App metadata isolation
// ---------------------------------------------------------------------------

describe("multi-window isolation – app metadata atoms", () => {
	it("appNameAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(appNameAtom, "Open Recorder Alpha");
		expect(storeB.get(appNameAtom)).toBe("Open Recorder");
	});

	it("windowTypeAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(windowTypeAtom, "editor");
		expect(storeB.get(windowTypeAtom)).toBe("");
	});

	it("isMacOSAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(isMacOSAtom, true);
		expect(storeB.get(isMacOSAtom)).toBe(false);
	});
});

// ---------------------------------------------------------------------------
// Recording atom isolation
// ---------------------------------------------------------------------------

describe("multi-window isolation – recording atoms", () => {
	it("recordingActiveAtom change in store A does not affect store B", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(recordingActiveAtom, true);
		expect(storeB.get(recordingActiveAtom)).toBe(false);
	});

	it("microphoneEnabledAtom is isolated between stores", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(microphoneEnabledAtom, true);
		expect(storeB.get(microphoneEnabledAtom)).toBe(false);
	});

	it("cameraEnabledAtom is isolated between stores", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(cameraEnabledAtom, true);
		expect(storeB.get(cameraEnabledAtom)).toBe(false);
	});

	it("systemAudioEnabledAtom is isolated between stores", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(systemAudioEnabledAtom, true);
		expect(storeB.get(systemAudioEnabledAtom)).toBe(false);
	});
});

// ---------------------------------------------------------------------------
// Launch atom isolation
// ---------------------------------------------------------------------------

describe("multi-window isolation – launch atoms", () => {
	it("launchViewAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(launchViewAtom, "recording");
		expect(storeB.get(launchViewAtom)).toBe("choice");
	});

	it("recordingStartAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(recordingStartAtom, 12345678);
		expect(storeB.get(recordingStartAtom)).toBeNull();
	});

	it("recordingElapsedAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(recordingElapsedAtom, 30_000);
		expect(storeB.get(recordingElapsedAtom)).toBe(0);
	});

	it("selectedSourceAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(selectedSourceAtom, "Secondary Display");
		expect(storeB.get(selectedSourceAtom)).toBe("Main Display");
	});

	it("hasSelectedSourceAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(hasSelectedSourceAtom, false);
		expect(storeB.get(hasSelectedSourceAtom)).toBe(true);
	});
});

// ---------------------------------------------------------------------------
// Source selector atom isolation
// ---------------------------------------------------------------------------

describe("multi-window isolation – source selector atoms", () => {
	it("sourcesAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(sourcesAtom, [
			{ id: "screen:0", name: "Main", thumbnail: "", type: "screen" },
		]);
		expect(storeB.get(sourcesAtom)).toHaveLength(0);
	});

	it("selectedDesktopSourceAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(selectedDesktopSourceAtom, {
			id: "screen:0",
			name: "Main",
			thumbnail: "",
			type: "screen",
		});
		expect(storeB.get(selectedDesktopSourceAtom)).toBeNull();
	});

	it("sourceSelectorTabAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(sourceSelectorTabAtom, "windows");
		expect(storeB.get(sourceSelectorTabAtom)).toBe("screens");
	});
});

// ---------------------------------------------------------------------------
// Video editor atom isolation
// ---------------------------------------------------------------------------

describe("multi-window isolation – video editor atoms", () => {
	it("videoPathAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(videoPathAtom, "/recordings/video.mp4");
		expect(storeB.get(videoPathAtom)).toBeNull();
	});

	it("isPlayingAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(isPlayingAtom, true);
		expect(storeB.get(isPlayingAtom)).toBe(false);
	});

	it("audioMutedAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(audioMutedAtom, true);
		expect(storeB.get(audioMutedAtom)).toBe(false);
	});

	it("zoomRegionsAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(zoomRegionsAtom, [
			{
				id: "z1",
				startMs: 0,
				endMs: 2000,
				depth: 2,
				focus: { cx: 0.5, cy: 0.5 },
				...createDefaultZoomEasing(),
			},
		]);
		expect(storeB.get(zoomRegionsAtom)).toHaveLength(0);
	});

	it("trimRegionsAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(trimRegionsAtom, [{ id: "t1", startMs: 0, endMs: 5000 }]);
		expect(storeB.get(trimRegionsAtom)).toHaveLength(0);
	});

	it("exportFormatAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(exportFormatAtom, "gif");
		expect(storeB.get(exportFormatAtom)).toBe("mp4");
	});

	it("exportQualityAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(exportQualityAtom, "medium");
		expect(storeB.get(exportQualityAtom)).toBe("good");
	});

	it("isExportingAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(isExportingAtom, true);
		expect(storeB.get(isExportingAtom)).toBe(false);
	});

	it("paddingAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(paddingAtom, 100);
		expect(storeB.get(paddingAtom)).toBe(50);
	});

	it("shadowIntensityAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(shadowIntensityAtom, 0.1);
		expect(storeB.get(shadowIntensityAtom)).toBe(0.67);
	});

	it("borderRadiusAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(borderRadiusAtom, 0);
		expect(storeB.get(borderRadiusAtom)).toBe(12.5);
	});

	it("aspectRatioAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(aspectRatioAtom, "1:1");
		expect(storeB.get(aspectRatioAtom)).toBe("16:9");
	});
});

// ---------------------------------------------------------------------------
// Settings and permissions isolation
// ---------------------------------------------------------------------------

describe("multi-window isolation – settings and permissions atoms", () => {
	it("settingsActiveTabAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(settingsActiveTabAtom, "audio");
		expect(storeB.get(settingsActiveTabAtom)).toBe("appearance");
	});

	it("settingsSelectedColorAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(settingsSelectedColorAtom, "#000000");
		expect(storeB.get(settingsSelectedColorAtom)).toBe("#ADADAD");
	});

	it("permissionsAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(permissionsAtom, {
			screenRecording: "granted",
			microphone: "granted",
			camera: "granted",
			accessibility: "granted",
		});
		expect(storeB.get(permissionsAtom).screenRecording).toBe("checking");
	});

	it("isCheckingPermissionsAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(isCheckingPermissionsAtom, false);
		expect(storeB.get(isCheckingPermissionsAtom)).toBe(true);
	});

	it("imageBackgroundTypeAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(imageBackgroundTypeAtom, "gradient");
		expect(storeB.get(imageBackgroundTypeAtom)).toBe("wallpaper");
	});

	it("imagePaddingAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(imagePaddingAtom, 80);
		expect(storeB.get(imagePaddingAtom)).toBe(48);
	});

	it("imageBorderRadiusAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(imageBorderRadiusAtom, 0);
		expect(storeB.get(imageBorderRadiusAtom)).toBe(12);
	});

	it("imageShadowIntensityAtom is independent per store", () => {
		const { storeA, storeB } = makeTwoStores();
		storeA.set(imageShadowIntensityAtom, 1.0);
		expect(storeB.get(imageShadowIntensityAtom)).toBe(0.6);
	});
});

// ---------------------------------------------------------------------------
// Bidirectional isolation
// ---------------------------------------------------------------------------

describe("multi-window isolation – bidirectional proof", () => {
	it("modifying store B does not affect store A", () => {
		const { storeA, storeB } = makeTwoStores();

		storeA.set(videoPathAtom, "/recordings/store-a.mp4");
		storeB.set(videoPathAtom, "/recordings/store-b.mp4");

		expect(storeA.get(videoPathAtom)).toBe("/recordings/store-a.mp4");
		expect(storeB.get(videoPathAtom)).toBe("/recordings/store-b.mp4");
	});

	it("three stores are all isolated from each other", () => {
		const storeA = createStore();
		const storeB = createStore();
		const storeC = createStore();

		storeA.set(exportFormatAtom, "mp4");
		storeB.set(exportFormatAtom, "gif");
		storeC.set(exportFormatAtom, "mp4");

		storeB.set(aspectRatioAtom, "4:3");

		expect(storeA.get(exportFormatAtom)).toBe("mp4");
		expect(storeB.get(exportFormatAtom)).toBe("gif");
		expect(storeC.get(exportFormatAtom)).toBe("mp4");
		expect(storeA.get(aspectRatioAtom)).toBe("16:9");
		expect(storeC.get(aspectRatioAtom)).toBe("16:9");
	});
});
