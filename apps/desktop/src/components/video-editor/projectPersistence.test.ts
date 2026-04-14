import * as fc from "fast-check";
import { describe, expect, it } from "vitest";
import { WALLPAPER_PATHS } from "@/lib/wallpapers";
import {
	createProjectData,
	deriveNextId,
	normalizeProjectEditor,
	PROJECT_VERSION,
	validateProjectData,
} from "./projectPersistence";
import {
	DEFAULT_AUDIO_MUTED,
	DEFAULT_AUDIO_VOLUME,
	DEFAULT_CROP_REGION,
	DEFAULT_CURSOR_CLICK_BOUNCE,
	DEFAULT_CURSOR_MOTION_BLUR,
	DEFAULT_CURSOR_SIZE,
	DEFAULT_CURSOR_SMOOTHING,
	DEFAULT_ZOOM_MOTION_BLUR,
} from "./types";

describe("projectPersistence", () => {
	it("derives the next numeric id from the highest matching suffix", () => {
		expect(deriveNextId("zoom", ["zoom-1", "trim-3", "zoom-9", "zoom-nope"])).toBe(10);
		expect(deriveNextId("annotation", ["speed-2", "zoom-7"])).toBe(1);
	});

	it.each([
		[
			"accepts the minimal persisted shape",
			{ version: PROJECT_VERSION, videoPath: "file:///demo.mp4", editor: {} },
			true,
		],
		["rejects empty payloads", null, false],
		["rejects payloads without a video path", { version: PROJECT_VERSION, editor: {} }, false],
		[
			"rejects payloads with a non-object editor",
			{ version: PROJECT_VERSION, videoPath: "file:///demo.mp4", editor: null },
			false,
		],
	])("validateProjectData %s", (_label, candidate, expected) => {
		expect(validateProjectData(candidate)).toBe(expected);
	});

	it("fills in defaults for legacy editor snapshots", () => {
		const normalized = normalizeProjectEditor({});

		expect(normalized).toMatchObject({
			wallpaper: WALLPAPER_PATHS[0],
			audioMuted: DEFAULT_AUDIO_MUTED,
			audioVolume: DEFAULT_AUDIO_VOLUME,
			zoomMotionBlur: DEFAULT_ZOOM_MOTION_BLUR,
			cursorSize: DEFAULT_CURSOR_SIZE,
			cursorSmoothing: DEFAULT_CURSOR_SMOOTHING,
			cursorMotionBlur: DEFAULT_CURSOR_MOTION_BLUR,
			cursorClickBounce: DEFAULT_CURSOR_CLICK_BOUNCE,
			cropRegion: DEFAULT_CROP_REGION,
			aspectRatio: "16:9",
			exportQuality: "good",
			exportFormat: "mp4",
			gifFrameRate: 15,
			gifLoop: true,
			gifSizePreset: "medium",
		});
	});

	it("normalizes legacy blur flags, clamps numeric ranges, and sanitizes editor metadata", () => {
		const normalized = normalizeProjectEditor({
			wallpaper: "#111111",
			motionBlurEnabled: true,
			showBlur: true,
			audioMuted: true,
			audioVolume: -1,
			shadowIntensity: 0.42,
			backgroundBlur: 99,
			zoomMotionBlur: -10,
			connectZooms: false,
			showCursor: false,
			loopCursor: true,
			cursorSize: 99,
			cursorSmoothing: -4,
			cursorMotionBlur: 5,
			cursorClickBounce: 99,
			borderRadius: 8,
			padding: -10,
			cropRegion: { x: -2, y: 0.4, width: 3, height: 2 },
			aspectRatio: "broken",
			exportQuality: "invalid" as never,
			exportFormat: "webm" as never,
			gifFrameRate: 12 as never,
			gifLoop: false,
			gifSizePreset: "tiny" as never,
			zoomRegions: [
				{
					id: "zoom-1",
					startMs: 1000.4,
					endMs: 1000.1,
					depth: 9 as never,
					focus: { cx: -3, cy: 4 },
				},
			],
			trimRegions: [
				{
					id: "trim-1",
					startMs: 2000.8,
					endMs: 1000.2,
				},
			],
			speedRegions: [
				{
					id: "speed-1",
					startMs: -10,
					endMs: 0,
					speed: 9 as never,
				},
			],
			annotationRegions: [
				{
					id: "annotation-1",
					startMs: 0,
					endMs: 100,
					type: "figure",
					content: "legacy text",
					position: { x: 999, y: -10 },
					size: { width: 0, height: 999 },
					style: { color: "#000" },
					zIndex: Number.NaN,
					figureData: {
						arrowDirection: "up-left",
						color: "#fff",
						strokeWidth: 6,
					},
				},
			],
			facecamSettings: {
				enabled: true,
				shape: "square",
				size: 100,
				cornerRadius: -10,
				borderWidth: -2,
				borderColor: "",
				margin: 999,
				anchor: "custom",
				customX: 2,
				customY: -2,
			},
		});

		expect(normalized).toMatchObject({
			wallpaper: "#111111",
			audioMuted: true,
			audioVolume: 0,
			shadowIntensity: 0.42,
			backgroundBlur: 8,
			zoomMotionBlur: 0,
			connectZooms: false,
			showCursor: false,
			loopCursor: true,
			cursorSize: 10,
			cursorSmoothing: 0,
			cursorMotionBlur: 2,
			cursorClickBounce: 5,
			padding: 0,
			cropRegion: { x: 0, y: 0.4, width: 1, height: 0.6 },
			aspectRatio: "16:9",
			exportQuality: "good",
			exportFormat: "mp4",
			gifFrameRate: 15,
			gifLoop: false,
			gifSizePreset: "medium",
		});

		expect(normalized.zoomRegions).toEqual([
			{
				id: "zoom-1",
				startMs: 1000,
				endMs: 1001,
				depth: 3,
				focus: { cx: 0, cy: 1 },
			},
		]);
		expect(normalized.trimRegions).toEqual([
			{
				id: "trim-1",
				startMs: 1000,
				endMs: 1001,
			},
		]);
		expect(normalized.speedRegions).toEqual([
			{
				id: "speed-1",
				startMs: 0,
				endMs: 1,
				speed: 1.5,
			},
		]);
		expect(normalized.annotationRegions).toEqual([
			{
				id: "annotation-1",
				startMs: 0,
				endMs: 100,
				type: "figure",
				content: "legacy text",
				textContent: undefined,
				imageContent: undefined,
				position: { x: 100, y: 0 },
				size: { width: 1, height: 200 },
				style: {
					color: "#000",
					backgroundColor: "transparent",
					fontSize: 32,
					fontFamily: expect.any(String),
					fontWeight: "bold",
					fontStyle: "normal",
					textDecoration: "none",
					textAlign: "center",
				},
				zIndex: 1,
				figureData: {
					arrowDirection: "up-left",
					color: "#fff",
					strokeWidth: 6,
				},
			},
		]);
		expect(normalized.facecamSettings).toEqual({
			enabled: true,
			shape: "square",
			size: 40,
			cornerRadius: 0,
			borderWidth: 0,
			borderColor: "#FFFFFF",
			margin: 12,
			anchor: "custom",
			customX: 1,
			customY: 0,
		});

		expect(normalized.annotationRegions[0]?.style.color).toBe("#000");
	});

	it("keeps numeric editor state within bounds for a wide range of inputs", () => {
		fc.assert(
			fc.property(
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				fc.double({ min: -10_000, max: 10_000, noDefaultInfinity: true, noNaN: true }),
				(
					audioVolume,
					cursorSize,
					cursorSmoothing,
					cursorMotionBlur,
					cursorClickBounce,
					padding,
					cropX,
					cropY,
					cropWidth,
					cropHeight,
					zoomMotionBlur,
					backgroundBlur,
				) => {
					const normalized = normalizeProjectEditor({
						audioVolume,
						cursorSize,
						cursorSmoothing,
						cursorMotionBlur,
						cursorClickBounce,
						padding,
						cropRegion: {
							x: cropX,
							y: cropY,
							width: cropWidth,
							height: cropHeight,
						},
						zoomMotionBlur,
						backgroundBlur,
					});

					expect(normalized.audioVolume).toBeGreaterThanOrEqual(0);
					expect(normalized.audioVolume).toBeLessThanOrEqual(1);
					expect(normalized.cursorSize).toBeGreaterThanOrEqual(0.5);
					expect(normalized.cursorSize).toBeLessThanOrEqual(10);
					expect(normalized.cursorSmoothing).toBeGreaterThanOrEqual(0);
					expect(normalized.cursorSmoothing).toBeLessThanOrEqual(2);
					expect(normalized.cursorMotionBlur).toBeGreaterThanOrEqual(0);
					expect(normalized.cursorMotionBlur).toBeLessThanOrEqual(2);
					expect(normalized.cursorClickBounce).toBeGreaterThanOrEqual(0);
					expect(normalized.cursorClickBounce).toBeLessThanOrEqual(5);
					expect(normalized.padding).toBeGreaterThanOrEqual(0);
					expect(normalized.padding).toBeLessThanOrEqual(100);
					expect(normalized.cropRegion.x).toBeGreaterThanOrEqual(0);
					expect(normalized.cropRegion.x).toBeLessThanOrEqual(1);
					expect(normalized.cropRegion.y).toBeGreaterThanOrEqual(0);
					expect(normalized.cropRegion.y).toBeLessThanOrEqual(1);
					expect(normalized.cropRegion.width).toBeGreaterThanOrEqual(0);
					expect(normalized.cropRegion.height).toBeGreaterThanOrEqual(0);
					expect(normalized.zoomMotionBlur).toBeGreaterThanOrEqual(0);
					expect(normalized.zoomMotionBlur).toBeLessThanOrEqual(2);
					expect(normalized.backgroundBlur).toBeGreaterThanOrEqual(0);
					expect(normalized.backgroundBlur).toBeLessThanOrEqual(8);
				},
			),
			{ numRuns: 500 },
		);
	});

	it("creates persisted project data without blank optional fields", () => {
		const project = createProjectData(
			"/tmp/demo.mp4",
			normalizeProjectEditor({ wallpaper: "#222222" }),
			{
				facecamVideoPath: "   ",
				facecamOffsetMs: Number.NaN,
				sourceName: "  ",
			},
		);

		expect(project).toEqual({
			version: PROJECT_VERSION,
			videoPath: "/tmp/demo.mp4",
			editor: expect.any(Object),
		});
		expect(project.facecamVideoPath).toBeUndefined();
		expect(project.facecamOffsetMs).toBeUndefined();
		expect(project.sourceName).toBeUndefined();
	});

	it("keeps meaningful project metadata intact", () => {
		const editor = normalizeProjectEditor({ wallpaper: "#333333" });
		const project = createProjectData("/tmp/demo.mp4", editor, {
			facecamVideoPath: "/tmp/facecam.webm",
			facecamOffsetMs: 125,
			sourceName: "Display 1",
		});

		expect(project.version).toBe(PROJECT_VERSION);
		expect(project.facecamVideoPath).toBe("/tmp/facecam.webm");
		expect(project.facecamOffsetMs).toBe(125);
		expect(project.sourceName).toBe("Display 1");
		expect(project.editor).toBe(editor);
	});
});
