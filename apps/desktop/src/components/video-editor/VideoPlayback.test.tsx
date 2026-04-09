// @vitest-environment jsdom

import type { ComponentProps } from "react";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockState = vi.hoisted(() => {
	const appInstances: unknown[] = [];

	class MockContainer {
		children: unknown[] = [];
		visible = true;
		filters: unknown[] = [];
		mask: unknown = null;
		scale = { set: vi.fn() };
		position = { set: vi.fn() };
		addChild = vi.fn((child: unknown) => {
			this.children.push(child);
			return child;
		});
		removeChild = vi.fn((child: unknown) => {
			this.children = this.children.filter((candidate) => candidate !== child);
			return child;
		});
		removeChildren = vi.fn(() => {
			this.children = [];
			return [];
		});
		destroy = vi.fn();
	}

	class MockGraphics extends MockContainer {
		clear = vi.fn(() => this);
		circle = vi.fn(() => this);
		fill = vi.fn(() => this);
		roundRect = vi.fn(() => this);
		stroke = vi.fn(() => this);
	}

	class MockSprite extends MockContainer {
		texture: unknown;

		constructor(texture: unknown) {
			super();
			this.texture = texture;
		}
	}

	class MockBlurFilter {
		quality = 0;
		resolution = 0;
		blur = 0;
		destroy = vi.fn();
	}

	class MockApplication {
		canvas = document.createElement("canvas");
		stage = new MockContainer();
		renderer = { resolution: 1 };
		ticker = {
			maxFPS: 0,
			started: false,
			add: vi.fn(),
			remove: vi.fn(),
			start: vi.fn(() => {
				this.ticker.started = true;
			}),
			stop: vi.fn(() => {
				this.ticker.started = false;
			}),
		};
		init = vi.fn(() => Promise.resolve());
		destroy = vi.fn();

		constructor() {
			appInstances.push(this);
		}
	}

	class MockPixiCursorOverlay {
		container = new MockContainer();
		setDotRadius = vi.fn();
		setSmoothingFactor = vi.fn();
		setMotionBlur = vi.fn();
		setClickBounce = vi.fn();
		reset = vi.fn();
		update = vi.fn();
		destroy = vi.fn();
	}

	return {
		appInstances,
		Application: MockApplication,
		Container: MockContainer,
		Graphics: MockGraphics,
		Sprite: MockSprite,
		BlurFilter: MockBlurFilter,
		MotionBlurFilter: class {
			destroy = vi.fn();
		},
		Assets: {
			load: vi.fn(() => Promise.resolve()),
		},
		Texture: {
			from: vi.fn(() => ({
				destroy: vi.fn(),
			})),
		},
		VideoSource: {
			from: vi.fn(() => ({
				autoPlay: true,
				autoUpdate: false,
			})),
		},
		ensurePixiRuntime: vi.fn(() => Promise.resolve()),
		preloadCursorAssets: vi.fn(() => Promise.resolve()),
		PixiCursorOverlay: MockPixiCursorOverlay,
		layoutVideoContent: vi.fn(
			({
				container,
				videoElement,
			}: {
				container: HTMLDivElement;
				videoElement: HTMLVideoElement;
			}) => ({
				stageSize: {
					width: container.clientWidth || 960,
					height: container.clientHeight || 540,
				},
				videoSize: {
					width: videoElement.videoWidth || 1920,
					height: videoElement.videoHeight || 1080,
				},
				baseScale: 1,
				baseOffset: { x: 0, y: 0 },
				maskRect: {
					x: 0,
					y: 0,
					width: container.clientWidth || 960,
					height: container.clientHeight || 540,
				},
				cropBounds: { startX: 0, endX: 1, startY: 0, endY: 1 },
			}),
		),
		applyZoomTransform: vi.fn(() => ({
			scale: 1,
			x: 0,
			y: 0,
		})),
		computeFocusFromTransform: vi.fn(() => ({
			cx: 0.5,
			cy: 0.5,
		})),
		computeZoomTransform: vi.fn(() => ({
			scale: 1,
			x: 0,
			y: 0,
		})),
		createMotionBlurState: vi.fn(() => ({})),
		createVideoEventHandlers: vi.fn(() => ({
			handlePlay: vi.fn(),
			handlePause: vi.fn(),
			handleSeeked: vi.fn(),
			handleSeeking: vi.fn(),
		})),
		findDominantRegion: vi.fn(() => ({
			region: null,
			strength: 0,
			blendedScale: null,
			transition: null,
		})),
		clampFocusToStage: vi.fn((focus: unknown) => focus),
		updateOverlayIndicator: vi.fn(),
		getAssetPath: vi.fn(async () => "/wallpaper.png"),
		getRenderableAssetUrl: vi.fn(async (value: string) => value),
		isRenderableAssetUrl: vi.fn(
			(value: string) =>
				value.startsWith("data:") ||
				value.startsWith("asset:") ||
				value.startsWith("http") ||
				value.startsWith("file://") ||
				value.startsWith("/"),
		),
	};
});

vi.mock("@/lib/pixi", () => ({
	Application: mockState.Application,
	Assets: mockState.Assets,
	BlurFilter: mockState.BlurFilter,
	Container: mockState.Container,
	Graphics: mockState.Graphics,
	Sprite: mockState.Sprite,
	Texture: mockState.Texture,
	VideoSource: mockState.VideoSource,
}));

vi.mock("pixi-filters/motion-blur", () => ({
	MotionBlurFilter: mockState.MotionBlurFilter,
}));

vi.mock("@/lib/pixiRuntime", () => ({
	ensurePixiRuntime: mockState.ensurePixiRuntime,
}));

vi.mock("./videoPlayback/cursorRenderer", () => ({
	DEFAULT_CURSOR_CONFIG: {
		dotRadius: 28,
	},
	PixiCursorOverlay: mockState.PixiCursorOverlay,
	preloadCursorAssets: mockState.preloadCursorAssets,
}));

vi.mock("./videoPlayback/layoutUtils", () => ({
	layoutVideoContent: mockState.layoutVideoContent,
}));

vi.mock("./videoPlayback/zoomTransform", () => ({
	applyZoomTransform: mockState.applyZoomTransform,
	computeFocusFromTransform: mockState.computeFocusFromTransform,
	computeZoomTransform: mockState.computeZoomTransform,
	createMotionBlurState: mockState.createMotionBlurState,
}));

vi.mock("./videoPlayback/videoEventHandlers", () => ({
	createVideoEventHandlers: mockState.createVideoEventHandlers,
}));

vi.mock("./videoPlayback/zoomRegionUtils", () => ({
	findDominantRegion: mockState.findDominantRegion,
}));

vi.mock("./videoPlayback/focusUtils", () => ({
	clampFocusToStage: mockState.clampFocusToStage,
}));

vi.mock("./videoPlayback/overlayUtils", () => ({
	updateOverlayIndicator: mockState.updateOverlayIndicator,
}));

vi.mock("@/lib/assetPath", () => ({
	getAssetPath: mockState.getAssetPath,
	getRenderableAssetUrl: mockState.getRenderableAssetUrl,
	isRenderableAssetUrl: mockState.isRenderableAssetUrl,
}));

vi.mock("./AnnotationOverlay", () => ({
	AnnotationOverlay: () => null,
}));

const { default: VideoPlayback } = await import("./VideoPlayback");

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

type RenderHarness = {
	container: HTMLDivElement;
	rerender: (overrides?: Partial<ComponentProps<typeof VideoPlayback>>) => Promise<void>;
	unmount: () => Promise<void>;
};

function createDeferred<T>() {
	let resolve!: (value: T) => void;
	let reject!: (reason?: unknown) => void;

	const promise = new Promise<T>((res, rej) => {
		resolve = res;
		reject = rej;
	});

	return { promise, resolve, reject };
}

function defineMediaProperty<T extends keyof HTMLMediaElement>(
	element: HTMLMediaElement,
	key: T,
	value: HTMLMediaElement[T],
) {
	Object.defineProperty(element, key, {
		configurable: true,
		value,
	});
}

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function renderPlayback(
	overrides: Partial<ComponentProps<typeof VideoPlayback>> = {},
): Promise<RenderHarness> {
	const container = document.createElement("div");
	Object.defineProperty(container, "clientWidth", { configurable: true, value: 960 });
	Object.defineProperty(container, "clientHeight", { configurable: true, value: 540 });
	document.body.appendChild(container);

	const root: Root = createRoot(container);
	const baseProps: ComponentProps<typeof VideoPlayback> = {
		videoPath: "asset://localhost/video-a.mp4",
		aspectRatio: "16:9",
		zoomRegions: [],
		selectedZoomId: null,
		onSelectZoom: vi.fn(),
		onZoomFocusChange: vi.fn(),
		onDurationChange: vi.fn(),
		onTimeUpdate: vi.fn(),
		onPlayStateChange: vi.fn(),
		onError: vi.fn(),
		isPlaying: false,
	};

	const render = async (nextOverrides?: Partial<ComponentProps<typeof VideoPlayback>>) => {
		await act(async () => {
			root.render(<VideoPlayback {...baseProps} {...overrides} {...nextOverrides} />);
		});
		await flushEffects();
	};

	await render();

	return {
		container,
		rerender: render,
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
			container.remove();
		},
	};
}

function getPrimaryVideo(container: HTMLDivElement) {
	const video = container.querySelector("video");
	if (!(video instanceof HTMLVideoElement)) {
		throw new Error("Expected a video element");
	}

	return video;
}

beforeEach(() => {
	vi.clearAllMocks();
	mockState.appInstances.length = 0;
	mockState.ensurePixiRuntime.mockResolvedValue(undefined);
	mockState.preloadCursorAssets.mockResolvedValue(undefined);

	class ResizeObserverMock {
		observe = vi.fn();
		disconnect = vi.fn();
	}

	Object.defineProperty(globalThis, "ResizeObserver", {
		configurable: true,
		value: ResizeObserverMock,
	});
	Object.defineProperty(globalThis, "requestAnimationFrame", {
		configurable: true,
		value: (callback: FrameRequestCallback) => window.setTimeout(() => callback(0), 0),
	});
	Object.defineProperty(globalThis, "cancelAnimationFrame", {
		configurable: true,
		value: (handle: number) => window.clearTimeout(handle),
	});
	Object.defineProperty(HTMLMediaElement.prototype, "pause", {
		configurable: true,
		value: vi.fn(),
	});
	Object.defineProperty(HTMLMediaElement.prototype, "play", {
		configurable: true,
		value: vi.fn(() => Promise.resolve()),
	});
});

afterEach(() => {
	vi.restoreAllMocks();
	document.body.innerHTML = "";
});

describe("VideoPlayback", () => {
	it("reports ready once Pixi and the first video frame are ready even if cursor assets are still loading", async () => {
		const cursorAssetsDeferred = createDeferred<void>();
		mockState.preloadCursorAssets.mockImplementation(() => cursorAssetsDeferred.promise);

		const onReadyChange = vi.fn();
		const harness = await renderPlayback({ onReadyChange });
		const video = getPrimaryVideo(harness.container);

		defineMediaProperty(video, "videoWidth", 1920);
		defineMediaProperty(video, "videoHeight", 1080);
		defineMediaProperty(video, "duration", 12);

		let readyState = HTMLMediaElement.HAVE_METADATA;
		Object.defineProperty(video, "readyState", {
			configurable: true,
			get: () => readyState,
		});

		await act(async () => {
			video.dispatchEvent(new Event("loadedmetadata"));
		});
		readyState = HTMLMediaElement.HAVE_CURRENT_DATA;
		await act(async () => {
			video.dispatchEvent(new Event("loadeddata"));
		});
		await flushEffects();

		expect(onReadyChange).toHaveBeenLastCalledWith(true);

		cursorAssetsDeferred.resolve();
		await flushEffects();
		await harness.unmount();
	});

	it("does not block first paint if cursor asset preloading fails", async () => {
		mockState.preloadCursorAssets.mockRejectedValue(new Error("cursor assets unavailable"));
		vi.spyOn(console, "warn").mockImplementation(() => undefined);

		const onReadyChange = vi.fn();
		const harness = await renderPlayback({ onReadyChange });
		const video = getPrimaryVideo(harness.container);

		defineMediaProperty(video, "videoWidth", 1280);
		defineMediaProperty(video, "videoHeight", 720);
		defineMediaProperty(video, "duration", 8);
		defineMediaProperty(video, "readyState", HTMLMediaElement.HAVE_CURRENT_DATA);

		await act(async () => {
			video.dispatchEvent(new Event("loadedmetadata"));
			video.dispatchEvent(new Event("loadeddata"));
		});
		await flushEffects();

		expect(onReadyChange).toHaveBeenLastCalledWith(true);
		await harness.unmount();
	});

	it("reuses the same Pixi application instance when switching videos", async () => {
		const onReadyChange = vi.fn();
		const harness = await renderPlayback({ onReadyChange });
		const firstVideo = getPrimaryVideo(harness.container);

		defineMediaProperty(firstVideo, "videoWidth", 1920);
		defineMediaProperty(firstVideo, "videoHeight", 1080);
		defineMediaProperty(firstVideo, "duration", 10);
		defineMediaProperty(firstVideo, "readyState", HTMLMediaElement.HAVE_CURRENT_DATA);

		await act(async () => {
			firstVideo.dispatchEvent(new Event("loadedmetadata"));
			firstVideo.dispatchEvent(new Event("loadeddata"));
		});
		await flushEffects();

		expect(mockState.appInstances).toHaveLength(1);

		await harness.rerender({
			videoPath: "asset://localhost/video-b.mp4",
		});

		const secondVideo = getPrimaryVideo(harness.container);
		defineMediaProperty(secondVideo, "videoWidth", 1280);
		defineMediaProperty(secondVideo, "videoHeight", 720);
		defineMediaProperty(secondVideo, "duration", 6);
		defineMediaProperty(secondVideo, "readyState", HTMLMediaElement.HAVE_CURRENT_DATA);

		await act(async () => {
			secondVideo.dispatchEvent(new Event("loadedmetadata"));
			secondVideo.dispatchEvent(new Event("loadeddata"));
		});
		await flushEffects();

		expect(mockState.appInstances).toHaveLength(1);
		expect(onReadyChange).toHaveBeenLastCalledWith(true);
		await harness.unmount();
	});

	it("applies mute and volume updates to the primary preview video", async () => {
		const harness = await renderPlayback({
			audioMuted: true,
			audioVolume: 0.35,
		});
		const video = getPrimaryVideo(harness.container);

		expect(video.muted).toBe(true);
		expect(video.volume).toBeCloseTo(0.35);

		await harness.rerender({
			audioMuted: false,
			audioVolume: 0.8,
		});

		expect(video.muted).toBe(false);
		expect(video.volume).toBeCloseTo(0.8);
		await harness.unmount();
	});
});
