// @vitest-environment jsdom

import { beforeEach, describe, expect, it, vi } from "vitest";

const mockState = vi.hoisted(() => {
	const loadMetadata = vi.fn(async () => ({
		width: 1280,
		height: 720,
		duration: 1,
		hasAudio: true,
	}));
	const decodeAll = vi.fn(
		async (
			_frameRate: number,
			_trimRegions: unknown,
			_speedRegions: unknown,
			callback: (
				frame: { close: () => void },
				timestampUs: number,
				sourceTimestampMs: number,
			) => Promise<void>,
		) => {
			await callback({ close: vi.fn() }, 0, 0);
		},
	);
	const getEffectiveDuration = vi.fn(() => 1);
	const getDemuxer = vi.fn(() => ({ demuxer: true }));
	const streamingDestroy = vi.fn();
	const streamingCancel = vi.fn();
	const renderFrame = vi.fn(async () => undefined);
	const rendererInitialize = vi.fn(async () => undefined);
	const rendererDestroy = vi.fn();
	const muxerInitialize = vi.fn(async () => undefined);
	const muxerFinalize = vi.fn(async () => new Blob([]));
	const addVideoChunk = vi.fn(async () => undefined);
	const addAudioChunk = vi.fn(async () => undefined);
	const muxerHasAudioArgs: boolean[] = [];
	const audioProcess = vi.fn(async () => undefined);
	const audioCancel = vi.fn();

	return {
		loadMetadata,
		decodeAll,
		getEffectiveDuration,
		getDemuxer,
		streamingDestroy,
		streamingCancel,
		renderFrame,
		rendererInitialize,
		rendererDestroy,
		muxerInitialize,
		muxerFinalize,
		addVideoChunk,
		addAudioChunk,
		muxerHasAudioArgs,
		audioProcess,
		audioCancel,
	};
});

vi.mock("./streamingDecoder", () => ({
	StreamingVideoDecoder: class {
		loadMetadata = mockState.loadMetadata;
		decodeAll = mockState.decodeAll;
		getEffectiveDuration = mockState.getEffectiveDuration;
		getDemuxer = mockState.getDemuxer;
		destroy = mockState.streamingDestroy;
		cancel = mockState.streamingCancel;
	},
}));

vi.mock("./frameRenderer", () => ({
	FrameRenderer: class {
		initialize = mockState.rendererInitialize;
		renderFrame = mockState.renderFrame;
		getCanvas = () => ({ nodeName: "CANVAS" });
		destroy = mockState.rendererDestroy;
	},
}));

vi.mock("./muxer", () => ({
	VideoMuxer: class {
		constructor(_config: unknown, hasAudio: boolean) {
			mockState.muxerHasAudioArgs.push(hasAudio);
		}

		initialize = mockState.muxerInitialize;
		addVideoChunk = mockState.addVideoChunk;
		addAudioChunk = mockState.addAudioChunk;
		finalize = mockState.muxerFinalize;
	},
}));

vi.mock("./audioEncoder", () => ({
	AudioProcessor: class {
		process = mockState.audioProcess;
		cancel = mockState.audioCancel;
	},
}));

vi.mock("./syncedVideoProvider", () => ({
	SyncedVideoProvider: class {
		initialize = vi.fn(async () => undefined);
		getFrameAt = vi.fn(async () => null);
		destroy = vi.fn();
	},
}));

const { VideoExporter } = await import("./videoExporter");

describe("VideoExporter audio controls", () => {
	beforeEach(() => {
		mockState.loadMetadata.mockClear();
		mockState.decodeAll.mockClear();
		mockState.getEffectiveDuration.mockClear();
		mockState.getDemuxer.mockClear();
		mockState.streamingDestroy.mockClear();
		mockState.streamingCancel.mockClear();
		mockState.renderFrame.mockClear();
		mockState.rendererInitialize.mockClear();
		mockState.rendererDestroy.mockClear();
		mockState.muxerInitialize.mockClear();
		mockState.muxerFinalize.mockClear();
		mockState.addVideoChunk.mockClear();
		mockState.addAudioChunk.mockClear();
		mockState.muxerHasAudioArgs.length = 0;
		mockState.audioProcess.mockClear();
		mockState.audioCancel.mockClear();

		class MockVideoEncoder {
			static isConfigSupported = vi.fn(async (config: VideoEncoderConfig) => ({
				supported: true,
				config,
			}));

			state: "unconfigured" | "configured" | "closed" = "unconfigured";
			encodeQueueSize = 0;
			readonly output: VideoEncoderInit["output"];

			constructor(init: VideoEncoderInit) {
				this.output = init.output;
			}

			configure() {
				this.state = "configured";
			}

			encode() {}

			flush() {
				return Promise.resolve();
			}

			close() {
				this.state = "closed";
			}
		}

		class MockVideoFrame {
			constructor(_source: unknown, _init: VideoFrameInit) {}
			close() {}
		}

		Object.defineProperty(globalThis, "VideoEncoder", {
			configurable: true,
			value: MockVideoEncoder,
		});
		Object.defineProperty(globalThis, "VideoFrame", {
			configurable: true,
			value: MockVideoFrame,
		});
	});

	it("omits audio muxing and processing when export audio is muted", async () => {
		const exporter = new VideoExporter({
			videoUrl: "asset://video.mp4",
			width: 1280,
			height: 720,
			frameRate: 60,
			bitrate: 10_000_000,
			wallpaper: "#000000",
			zoomRegions: [],
			showShadow: false,
			shadowIntensity: 0,
			backgroundBlur: 0,
			cropRegion: { x: 0, y: 0, width: 1, height: 1 },
			audioMuted: true,
			audioVolume: 1,
		});

		const result = await exporter.export();

		expect(result.success).toBe(true);
		expect(mockState.muxerHasAudioArgs).toEqual([false]);
		expect(mockState.audioProcess).not.toHaveBeenCalled();
	});

	it("passes custom audio volume through to audio processing when enabled", async () => {
		const exporter = new VideoExporter({
			videoUrl: "asset://video.mp4",
			width: 1280,
			height: 720,
			frameRate: 60,
			bitrate: 10_000_000,
			wallpaper: "#000000",
			zoomRegions: [],
			showShadow: false,
			shadowIntensity: 0,
			backgroundBlur: 0,
			cropRegion: { x: 0, y: 0, width: 1, height: 1 },
			audioMuted: false,
			audioVolume: 0.4,
		});

		const result = await exporter.export();

		expect(result.success).toBe(true);
		expect(mockState.muxerHasAudioArgs).toEqual([true]);
		expect(mockState.audioProcess).toHaveBeenCalledWith(
			expect.anything(),
			expect.anything(),
			"asset://video.mp4",
			undefined,
			undefined,
			undefined,
			{ audioMuted: false, audioVolume: 0.4 },
		);
	});

	it("preserves current behavior when export volume is left at the default level", async () => {
		const exporter = new VideoExporter({
			videoUrl: "asset://video.mp4",
			width: 1280,
			height: 720,
			frameRate: 60,
			bitrate: 10_000_000,
			wallpaper: "#000000",
			zoomRegions: [],
			showShadow: false,
			shadowIntensity: 0,
			backgroundBlur: 0,
			cropRegion: { x: 0, y: 0, width: 1, height: 1 },
			audioVolume: 1,
		});

		const result = await exporter.export();

		expect(result.success).toBe(true);
		expect(mockState.muxerHasAudioArgs).toEqual([true]);
		expect(mockState.audioProcess).toHaveBeenCalledWith(
			expect.anything(),
			expect.anything(),
			"asset://video.mp4",
			undefined,
			undefined,
			undefined,
			{ audioMuted: undefined, audioVolume: 1 },
		);
	});
});
