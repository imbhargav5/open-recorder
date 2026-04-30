import { describe, expect, it } from "vitest";
import { buildImmediateExportSettings, buildMp4ExportPlan } from "./videoEditorExportUtils";

describe("videoEditorExportUtils", () => {
	it("builds gif export settings from the current editor defaults", () => {
		expect(
			buildImmediateExportSettings({
				format: "gif",
				exportQuality: "good",
				gifFrameRate: 15,
				gifLoop: false,
				gifSizePreset: "medium",
				sourceWidth: 3840,
				sourceHeight: 2160,
			}),
		).toEqual({
			format: "gif",
			quality: undefined,
			gifConfig: {
				frameRate: 15,
				loop: false,
				sizePreset: "medium",
				width: 1280,
				height: 720,
			},
		});
	});

	it("keeps source-quality native exports even-sized", () => {
		expect(
			buildMp4ExportPlan({
				quality: "source",
				sourceWidth: 1919,
				sourceHeight: 1079,
				aspectRatio: "native",
			}),
		).toEqual({
			width: 1918,
			height: 1078,
			bitrate: 30_000_000,
		});
	});

	it("fits source-quality square exports to the smaller even dimension", () => {
		expect(
			buildMp4ExportPlan({
				quality: "source",
				sourceWidth: 1920,
				sourceHeight: 1080,
				aspectRatio: "1:1",
			}),
		).toEqual({
			width: 1080,
			height: 1080,
			bitrate: 30_000_000,
		});
	});

	it("scales non-source exports to the target height and matching bitrate tier", () => {
		expect(
			buildMp4ExportPlan({
				quality: "medium",
				sourceWidth: 1920,
				sourceHeight: 1080,
				aspectRatio: "9:16",
			}),
		).toEqual({
			width: 404,
			height: 720,
			bitrate: 10_000_000,
		});
	});
});
