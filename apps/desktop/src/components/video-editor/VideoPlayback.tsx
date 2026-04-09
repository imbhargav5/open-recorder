import { MotionBlurFilter } from "pixi-filters/motion-blur";
import type React from "react";
import {
	forwardRef,
	memo,
	useCallback,
	useEffect,
	useImperativeHandle,
	useMemo,
	useRef,
	useState,
} from "react";
import { getAssetPath, getRenderableAssetUrl, isRenderableAssetUrl } from "@/lib/assetPath";
import {
	Application,
	BlurFilter,
	Container,
	type FederatedPointerEvent,
	Graphics,
	Sprite,
	Texture,
	VideoSource,
} from "@/lib/pixi";
import { ensurePixiRuntime } from "@/lib/pixiRuntime";
import {
	type FacecamAnchor,
	type FacecamSettings,
	getFacecamLayout,
	resolveAnchorFromPosition,
} from "@/lib/recordingSession";
import { DEFAULT_WALLPAPER_PATH, DEFAULT_WALLPAPER_RELATIVE_PATH } from "@/lib/wallpapers";
import { type AspectRatio, formatAspectRatioForCSS } from "@/utils/aspectRatioUtils";
import { AnnotationOverlay } from "./AnnotationOverlay";
import {
	type AnnotationRegion,
	type CursorTelemetryPoint,
	DEFAULT_CURSOR_CLICK_BOUNCE,
	DEFAULT_CURSOR_MOTION_BLUR,
	DEFAULT_CURSOR_SIZE,
	DEFAULT_CURSOR_SMOOTHING,
	type SpeedRegion,
	type TrimRegion,
	ZOOM_DEPTH_SCALES,
	type ZoomDepth,
	type ZoomFocus,
	type ZoomRegion,
} from "./types";
import { markVideoEditorTiming } from "./videoEditorPerf";
import {
	DEFAULT_FOCUS,
	ZOOM_SCALE_DEADZONE,
	ZOOM_TRANSLATION_DEADZONE_PX,
} from "./videoPlayback/constants";
import {
	DEFAULT_CURSOR_CONFIG,
	PixiCursorOverlay,
	preloadCursorAssets,
} from "./videoPlayback/cursorRenderer";
import { clampFocusToStage as clampFocusToStageUtil } from "./videoPlayback/focusUtils";
import { layoutVideoContent as layoutVideoContentUtil } from "./videoPlayback/layoutUtils";
import { clamp01 } from "./videoPlayback/mathUtils";
import { updateOverlayIndicator } from "./videoPlayback/overlayUtils";
import { createVideoEventHandlers } from "./videoPlayback/videoEventHandlers";
import { findDominantRegion } from "./videoPlayback/zoomRegionUtils";
import {
	applyZoomTransform,
	computeFocusFromTransform,
	computeZoomTransform,
	createMotionBlurState,
	type MotionBlurState,
} from "./videoPlayback/zoomTransform";

type PlaybackAnimationState = {
	scale: number;
	appliedScale: number;
	focusX: number;
	focusY: number;
	progress: number;
	x: number;
	y: number;
};

function createPlaybackAnimationState(): PlaybackAnimationState {
	return {
		scale: 1,
		appliedScale: 1,
		focusX: DEFAULT_FOCUS.cx,
		focusY: DEFAULT_FOCUS.cy,
		progress: 0,
		x: 0,
		y: 0,
	};
}

function isDirectlyRenderableWallpaper(wallpaper: string): boolean {
	return (
		wallpaper.startsWith("#") ||
		wallpaper.startsWith("linear-gradient") ||
		wallpaper.startsWith("radial-gradient") ||
		isRenderableAssetUrl(wallpaper)
	);
}

const FIRST_FRAME_TIMEOUT_MS = 3_000;
const OFFSCREEN_MEDIA_SOURCE_STYLE: React.CSSProperties = {
	position: "absolute",
	left: 0,
	top: 0,
	width: 1,
	height: 1,
	opacity: 0,
	pointerEvents: "none",
};

interface VideoPlaybackProps {
	videoPath: string;
	facecamVideoPath?: string;
	facecamOffsetMs?: number;
	facecamSettings?: FacecamSettings;
	onDurationChange: (duration: number) => void;
	onTimeUpdate: (time: number) => void;
	onPlayStateChange: (playing: boolean) => void;
	onError: (error: string) => void;
	wallpaper?: string;
	audioMuted?: boolean;
	audioVolume?: number;
	zoomRegions: ZoomRegion[];
	selectedZoomId: string | null;
	onSelectZoom: (id: string | null) => void;
	onZoomFocusChange: (id: string, focus: ZoomFocus) => void;
	isPlaying: boolean;
	showShadow?: boolean;
	shadowIntensity?: number;
	backgroundBlur?: number;
	zoomMotionBlur?: number;
	connectZooms?: boolean;
	borderRadius?: number;
	padding?: number;
	cropRegion?: import("./types").CropRegion;
	trimRegions?: TrimRegion[];
	speedRegions?: SpeedRegion[];
	aspectRatio: AspectRatio;
	annotationRegions?: AnnotationRegion[];
	selectedAnnotationId?: string | null;
	onSelectAnnotation?: (id: string | null) => void;
	onAnnotationPositionChange?: (id: string, position: { x: number; y: number }) => void;
	onAnnotationSizeChange?: (id: string, size: { width: number; height: number }) => void;
	cursorTelemetry?: CursorTelemetryPoint[];
	showCursor?: boolean;
	cursorSize?: number;
	cursorSmoothing?: number;
	cursorMotionBlur?: number;
	cursorClickBounce?: number;
	onReadyChange?: (ready: boolean) => void;
	onFacecamPositionChange?: (position: {
		anchor: FacecamAnchor;
		customX?: number;
		customY?: number;
	}) => void;
}

export interface VideoPlaybackRef {
	video: HTMLVideoElement | null;
	app: Application | null;
	videoSprite: Sprite | null;
	videoContainer: Container | null;
	containerRef: React.RefObject<HTMLDivElement>;
	play: () => Promise<void>;
	pause: () => void;
	refreshFrame: () => Promise<void>;
}

const VideoPlayback = memo(
	forwardRef<VideoPlaybackRef, VideoPlaybackProps>(
		(
			{
				videoPath,
				facecamVideoPath,
				facecamOffsetMs = 0,
				facecamSettings,
				onDurationChange,
				onTimeUpdate,
				onPlayStateChange,
				onError,
				wallpaper,
				audioMuted = false,
				audioVolume = 1,
				zoomRegions,
				selectedZoomId,
				onSelectZoom,
				onZoomFocusChange,
				isPlaying,
				showShadow,
				shadowIntensity = 0,
				backgroundBlur = 0,
				zoomMotionBlur = 0,
				connectZooms = true,
				borderRadius = 0,
				padding = 50,
				cropRegion,
				trimRegions = [],
				speedRegions = [],
				aspectRatio,
				annotationRegions = [],
				selectedAnnotationId,
				onSelectAnnotation,
				onAnnotationPositionChange,
				onAnnotationSizeChange,
				cursorTelemetry = [],
				showCursor = false,
				cursorSize = DEFAULT_CURSOR_SIZE,
				cursorSmoothing = DEFAULT_CURSOR_SMOOTHING,
				cursorMotionBlur = DEFAULT_CURSOR_MOTION_BLUR,
				cursorClickBounce = DEFAULT_CURSOR_CLICK_BOUNCE,
				onReadyChange,
				onFacecamPositionChange,
			},
			ref,
		) => {
			const videoRef = useRef<HTMLVideoElement | null>(null);
			const facecamVideoRef = useRef<HTMLVideoElement | null>(null);
			const containerRef = useRef<HTMLDivElement | null>(null);
			const appRef = useRef<Application | null>(null);
			const videoSpriteRef = useRef<Sprite | null>(null);
			const videoContainerRef = useRef<Container | null>(null);
			const cursorContainerRef = useRef<Container | null>(null);
			const cameraContainerRef = useRef<Container | null>(null);
			const facecamContainerRef = useRef<Container | null>(null);
			const facecamSpriteRef = useRef<Sprite | null>(null);
			const facecamMaskRef = useRef<Graphics | null>(null);
			const facecamBorderRef = useRef<Graphics | null>(null);
			const timeUpdateAnimationRef = useRef<number | null>(null);
			const [pixiReady, setPixiReady] = useState(false);
			const [metadataReady, setMetadataReady] = useState(false);
			const [firstFrameReady, setFirstFrameReady] = useState(false);
			const [cursorOverlayReady, setCursorOverlayReady] = useState(false);
			const [facecamReady, setFacecamReady] = useState(false);
			const [, setAnnotationVisibilityTick] = useState(0);
			const annotationRegionsRef = useRef(annotationRegions);
			const selectedAnnotationIdRef = useRef(selectedAnnotationId);
			const overlayRef = useRef<HTMLDivElement | null>(null);
			const focusIndicatorRef = useRef<HTMLDivElement | null>(null);
			const currentTimeRef = useRef(0);
			const zoomRegionsRef = useRef<ZoomRegion[]>([]);
			const selectedZoomIdRef = useRef<string | null>(null);
			const animationStateRef = useRef<PlaybackAnimationState>(createPlaybackAnimationState());
			const blurFilterRef = useRef<BlurFilter | null>(null);
			const motionBlurFilterRef = useRef<MotionBlurFilter | null>(null);
			const isDraggingFocusRef = useRef(false);
			const stageSizeRef = useRef({ width: 0, height: 0 });
			const videoSizeRef = useRef({ width: 0, height: 0 });
			const baseScaleRef = useRef(1);
			const baseOffsetRef = useRef({ x: 0, y: 0 });
			const baseMaskRef = useRef({ x: 0, y: 0, width: 0, height: 0 });
			const cropBoundsRef = useRef({ startX: 0, endX: 0, startY: 0, endY: 0 });
			const maskGraphicsRef = useRef<Graphics | null>(null);
			const isPlayingRef = useRef(isPlaying);
			const isSeekingRef = useRef(false);
			const allowPlaybackRef = useRef(false);
			const lockedVideoDimensionsRef = useRef<{ width: number; height: number } | null>(null);
			const layoutVideoContentRef = useRef<(() => void) | null>(null);
			const layoutFacecamOverlayRef = useRef<(() => void) | null>(null);
			const trimRegionsRef = useRef<TrimRegion[]>([]);

			useEffect(() => {
				const video = videoRef.current;
				if (!video) return;
				video.muted = audioMuted;
			}, [audioMuted, videoPath]);

			useEffect(() => {
				const video = videoRef.current;
				if (!video) return;
				video.volume = clamp01(audioVolume);
			}, [audioVolume, videoPath]);
			const speedRegionsRef = useRef<SpeedRegion[]>([]);
			const zoomMotionBlurRef = useRef(zoomMotionBlur);
			const connectZoomsRef = useRef(connectZooms);
			const firstFrameTimeoutRef = useRef<number | null>(null);
			const cursorOverlayRef = useRef<PixiCursorOverlay | null>(null);
			const cursorTelemetryRef = useRef<CursorTelemetryPoint[]>([]);
			const showCursorRef = useRef(showCursor);
			const cursorSizeRef = useRef(cursorSize);
			const cursorSmoothingRef = useRef(cursorSmoothing);
			const cursorMotionBlurRef = useRef(cursorMotionBlur);
			const cursorClickBounceRef = useRef(cursorClickBounce);
			const motionBlurStateRef = useRef<MotionBlurState>(createMotionBlurState());
			const facecamOffsetMsRef = useRef(facecamOffsetMs);
			const facecamSettingsRef = useRef(facecamSettings);
			const prevVisibleAnnotationIdsRef = useRef("");
			const previewSceneReady = pixiReady && metadataReady;
			const corePreviewReady = pixiReady && firstFrameReady;

			const clampFocusToStage = useCallback((focus: ZoomFocus, depth: ZoomDepth) => {
				return clampFocusToStageUtil(focus, depth, stageSizeRef.current);
			}, []);

			const updateOverlayForRegion = useCallback(
				(region: ZoomRegion | null, focusOverride?: ZoomFocus) => {
					const overlayEl = overlayRef.current;
					const indicatorEl = focusIndicatorRef.current;

					if (!overlayEl || !indicatorEl) {
						return;
					}

					// Update stage size from overlay dimensions
					const stageWidth = overlayEl.clientWidth;
					const stageHeight = overlayEl.clientHeight;
					if (stageWidth && stageHeight) {
						stageSizeRef.current = { width: stageWidth, height: stageHeight };
					}

					updateOverlayIndicator({
						overlayEl,
						indicatorEl,
						region,
						focusOverride,
						baseMask: baseMaskRef.current,
						isPlaying: isPlayingRef.current,
					});
				},
				[],
			);

			const layoutFacecamOverlay = useCallback(() => {
				const facecamContainer = facecamContainerRef.current;
				const facecamSprite = facecamSpriteRef.current;
				const facecamMask = facecamMaskRef.current;
				const facecamBorder = facecamBorderRef.current;
				const facecamVideo = facecamVideoRef.current;
				const settings = facecamSettingsRef.current;

				if (
					!facecamContainer ||
					!facecamSprite ||
					!facecamMask ||
					!facecamBorder ||
					!facecamVideo ||
					!settings
				) {
					return;
				}

				const stageWidth = stageSizeRef.current.width || containerRef.current?.clientWidth || 0;
				const stageHeight = stageSizeRef.current.height || containerRef.current?.clientHeight || 0;

				if (!stageWidth || !stageHeight || !settings.enabled || !facecamVideoPath) {
					facecamContainer.visible = false;
					return;
				}

				const { x, y, size, borderRadius } = getFacecamLayout(stageWidth, stageHeight, settings);
				const scale = Math.max(
					size / Math.max(1, facecamVideo.videoWidth),
					size / Math.max(1, facecamVideo.videoHeight),
				);
				const drawWidth = facecamVideo.videoWidth * scale;
				const drawHeight = facecamVideo.videoHeight * scale;
				const centerX = x + size / 2;
				const centerY = y + size / 2;

				facecamSprite.scale.set(scale);
				facecamSprite.position.set(x + (size - drawWidth) / 2, y + (size - drawHeight) / 2);

				facecamMask.clear();
				facecamBorder.clear();

				if (settings.shape === "circle") {
					facecamMask.circle(centerX, centerY, size / 2);
					facecamMask.fill({ color: 0xffffff });
					if (settings.borderWidth > 0) {
						facecamBorder.circle(
							centerX,
							centerY,
							Math.max(0, size / 2 - settings.borderWidth / 2),
						);
						facecamBorder.stroke({
							color: Number.parseInt(settings.borderColor.replace("#", ""), 16),
							width: settings.borderWidth,
						});
					}
				} else {
					facecamMask.roundRect(x, y, size, size, borderRadius);
					facecamMask.fill({ color: 0xffffff });
					if (settings.borderWidth > 0) {
						facecamBorder.roundRect(
							x + settings.borderWidth / 2,
							y + settings.borderWidth / 2,
							Math.max(0, size - settings.borderWidth),
							Math.max(0, size - settings.borderWidth),
							Math.max(0, borderRadius - settings.borderWidth / 2),
						);
						facecamBorder.stroke({
							color: Number.parseInt(settings.borderColor.replace("#", ""), 16),
							width: settings.borderWidth,
						});
					}
				}

				facecamContainer.visible = true;
			}, [facecamVideoPath]);

			const layoutVideoContent = useCallback(() => {
				const container = containerRef.current;
				const app = appRef.current;
				const videoSprite = videoSpriteRef.current;
				const maskGraphics = maskGraphicsRef.current;
				const videoElement = videoRef.current;
				const cameraContainer = cameraContainerRef.current;

				if (
					!container ||
					!app ||
					!videoSprite ||
					!maskGraphics ||
					!videoElement ||
					!cameraContainer
				) {
					return;
				}

				// Lock video dimensions on first layout to prevent resize issues
				if (
					!lockedVideoDimensionsRef.current &&
					videoElement.videoWidth > 0 &&
					videoElement.videoHeight > 0
				) {
					lockedVideoDimensionsRef.current = {
						width: videoElement.videoWidth,
						height: videoElement.videoHeight,
					};
				}

				const result = layoutVideoContentUtil({
					container,
					app,
					videoSprite,
					maskGraphics,
					videoElement,
					cropRegion,
					lockedVideoDimensions: lockedVideoDimensionsRef.current,
					borderRadius,
					padding,
				});

				if (result) {
					stageSizeRef.current = result.stageSize;
					videoSizeRef.current = result.videoSize;
					baseScaleRef.current = result.baseScale;
					baseOffsetRef.current = result.baseOffset;
					baseMaskRef.current = result.maskRect;
					cropBoundsRef.current = result.cropBounds;

					// Reset camera container to identity
					cameraContainer.scale.set(1);
					cameraContainer.position.set(0, 0);

					const selectedId = selectedZoomIdRef.current;
					const activeRegion = selectedId
						? (zoomRegionsRef.current.find((region) => region.id === selectedId) ?? null)
						: null;

					updateOverlayForRegion(activeRegion);
					layoutFacecamOverlayRef.current?.();
				}
			}, [updateOverlayForRegion, cropRegion, borderRadius, padding]);

			useEffect(() => {
				layoutVideoContentRef.current = layoutVideoContent;
			}, [layoutVideoContent]);

			useEffect(() => {
				layoutFacecamOverlayRef.current = layoutFacecamOverlay;
			}, [layoutFacecamOverlay]);

			const selectedZoom = useMemo(() => {
				if (!selectedZoomId) return null;
				return zoomRegions.find((region) => region.id === selectedZoomId) ?? null;
			}, [zoomRegions, selectedZoomId]);

			useImperativeHandle(ref, () => ({
				video: videoRef.current,
				app: appRef.current,
				videoSprite: videoSpriteRef.current,
				videoContainer: videoContainerRef.current,
				containerRef,
				play: async () => {
					const vid = videoRef.current;
					if (!vid) return;
					try {
						allowPlaybackRef.current = true;
						await vid.play();
					} catch (error) {
						allowPlaybackRef.current = false;
						throw error;
					}
				},
				pause: () => {
					const video = videoRef.current;
					allowPlaybackRef.current = false;
					if (!video) {
						return;
					}
					video.pause();
				},
				refreshFrame: async () => {
					const video = videoRef.current;
					if (!video || Number.isNaN(video.currentTime)) {
						return;
					}

					const restoreTime = video.currentTime;
					const duration = Number.isFinite(video.duration) ? video.duration : 0;
					const epsilon = duration > 0 ? Math.min(1 / 120, duration / 1000 || 1 / 120) : 1 / 120;
					const nudgeTarget =
						restoreTime > epsilon
							? restoreTime - epsilon
							: Math.min(duration || restoreTime + epsilon, restoreTime + epsilon);

					if (Math.abs(nudgeTarget - restoreTime) < 0.000001) {
						return;
					}

					await new Promise<void>((resolve) => {
						const handleFirstSeeked = () => {
							video.removeEventListener("seeked", handleFirstSeeked);
							const handleSecondSeeked = () => {
								video.removeEventListener("seeked", handleSecondSeeked);
								video.pause();
								resolve();
							};

							video.addEventListener("seeked", handleSecondSeeked, { once: true });
							video.currentTime = restoreTime;
						};

						video.addEventListener("seeked", handleFirstSeeked, { once: true });
						video.currentTime = nudgeTarget;
					});
				},
			}));

			const updateFocusFromClientPoint = (clientX: number, clientY: number) => {
				const overlayEl = overlayRef.current;
				if (!overlayEl) return;

				const regionId = selectedZoomIdRef.current;
				if (!regionId) return;

				const region = zoomRegionsRef.current.find((r) => r.id === regionId);
				if (!region) return;

				const rect = overlayEl.getBoundingClientRect();
				const stageWidth = rect.width;
				const stageHeight = rect.height;

				if (!stageWidth || !stageHeight) {
					return;
				}

				stageSizeRef.current = { width: stageWidth, height: stageHeight };

				const localX = clientX - rect.left;
				const localY = clientY - rect.top;
				const baseMask = baseMaskRef.current;

				const unclampedFocus: ZoomFocus = {
					cx: clamp01((localX - baseMask.x) / Math.max(1, baseMask.width)),
					cy: clamp01((localY - baseMask.y) / Math.max(1, baseMask.height)),
				};
				const clampedFocus = clampFocusToStage(unclampedFocus, region.depth);

				onZoomFocusChange(region.id, clampedFocus);
				updateOverlayForRegion({ ...region, focus: clampedFocus }, clampedFocus);
			};

			const handleOverlayPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
				if (isPlayingRef.current) return;
				const regionId = selectedZoomIdRef.current;
				if (!regionId) return;
				const region = zoomRegionsRef.current.find((r) => r.id === regionId);
				if (!region) return;
				onSelectZoom(region.id);
				event.preventDefault();
				isDraggingFocusRef.current = true;
				event.currentTarget.setPointerCapture(event.pointerId);
				updateFocusFromClientPoint(event.clientX, event.clientY);
			};

			const handleOverlayPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
				if (!isDraggingFocusRef.current) return;
				event.preventDefault();
				updateFocusFromClientPoint(event.clientX, event.clientY);
			};

			const endFocusDrag = (event: React.PointerEvent<HTMLDivElement>) => {
				if (!isDraggingFocusRef.current) return;
				isDraggingFocusRef.current = false;
				try {
					event.currentTarget.releasePointerCapture(event.pointerId);
				} catch {
					// no-op
				}
			};

			const handleOverlayPointerUp = (event: React.PointerEvent<HTMLDivElement>) => {
				endFocusDrag(event);
			};

			const handleOverlayPointerLeave = (event: React.PointerEvent<HTMLDivElement>) => {
				endFocusDrag(event);
			};

			const clearFirstFrameTimeout = useCallback(() => {
				if (firstFrameTimeoutRef.current !== null) {
					window.clearTimeout(firstFrameTimeoutRef.current);
					firstFrameTimeoutRef.current = null;
				}
			}, []);

			useEffect(() => {
				zoomRegionsRef.current = zoomRegions;
			}, [zoomRegions]);

			useEffect(() => {
				selectedZoomIdRef.current = selectedZoomId;
			}, [selectedZoomId]);

			useEffect(() => {
				isPlayingRef.current = isPlaying;
			}, [isPlaying]);

			useEffect(() => {
				trimRegionsRef.current = trimRegions;
			}, [trimRegions]);

			useEffect(() => {
				speedRegionsRef.current = speedRegions;
			}, [speedRegions]);

			useEffect(() => {
				zoomMotionBlurRef.current = zoomMotionBlur;
			}, [zoomMotionBlur]);

			useEffect(() => {
				connectZoomsRef.current = connectZooms;
			}, [connectZooms]);

			useEffect(() => {
				cursorTelemetryRef.current = cursorTelemetry;
			}, [cursorTelemetry]);

			useEffect(() => {
				showCursorRef.current = showCursor;
			}, [showCursor]);

			useEffect(() => {
				cursorSizeRef.current = cursorSize;
			}, [cursorSize]);

			useEffect(() => {
				cursorSmoothingRef.current = cursorSmoothing;
			}, [cursorSmoothing]);

			useEffect(() => {
				cursorMotionBlurRef.current = cursorMotionBlur;
			}, [cursorMotionBlur]);

			useEffect(() => {
				cursorClickBounceRef.current = cursorClickBounce;
			}, [cursorClickBounce]);

			useEffect(() => {
				facecamOffsetMsRef.current = facecamOffsetMs;
			}, [facecamOffsetMs]);

			useEffect(() => {
				facecamSettingsRef.current = facecamSettings;
			}, [facecamSettings]);

			useEffect(() => {
				annotationRegionsRef.current = annotationRegions;
			}, [annotationRegions]);

			useEffect(() => {
				selectedAnnotationIdRef.current = selectedAnnotationId;
			}, [selectedAnnotationId]);

			useEffect(() => {
				if (!previewSceneReady) return;

				const app = appRef.current;
				const cameraContainer = cameraContainerRef.current;
				const video = videoRef.current;

				if (!app || !cameraContainer || !video) return;

				const tickerWasStarted = app.ticker?.started || false;
				if (tickerWasStarted && app.ticker) {
					app.ticker.stop();
				}

				const wasPlaying = !video.paused;
				if (wasPlaying) {
					video.pause();
				}

				animationStateRef.current = createPlaybackAnimationState();

				// Reset cursor overlay smoothing on layout change
				cursorOverlayRef.current?.reset();

				// Reset motion blur state for clean transitions
				motionBlurStateRef.current = createMotionBlurState();

				if (blurFilterRef.current) {
					blurFilterRef.current.blur = 0;
				}

				requestAnimationFrame(() => {
					const container = cameraContainerRef.current;
					const videoStage = videoContainerRef.current;
					const sprite = videoSpriteRef.current;
					const currentApp = appRef.current;
					if (!container || !videoStage || !sprite || !currentApp) {
						return;
					}

					container.scale.set(1);
					container.position.set(0, 0);
					videoStage.scale.set(1);
					videoStage.position.set(0, 0);
					sprite.scale.set(1);
					sprite.position.set(0, 0);

					layoutVideoContent();

					applyZoomTransform({
						cameraContainer: container,
						blurFilter: blurFilterRef.current,
						stageSize: stageSizeRef.current,
						baseMask: baseMaskRef.current,
						zoomScale: 1,
						focusX: DEFAULT_FOCUS.cx,
						focusY: DEFAULT_FOCUS.cy,
						motionIntensity: 0,
						isPlaying: false,
						motionBlurAmount: zoomMotionBlurRef.current,
					});

					requestAnimationFrame(() => {
						const finalApp = appRef.current;
						if (wasPlaying && video) {
							video.play().catch(() => {
								// no-op
							});
						}
						if (tickerWasStarted && finalApp?.ticker) {
							finalApp.ticker.start();
						}
					});
				});
			}, [layoutVideoContent, previewSceneReady]);

			useEffect(() => {
				if (!previewSceneReady) return;
				const container = containerRef.current;
				if (!container) return;

				if (typeof ResizeObserver === "undefined") {
					return;
				}

				const observer = new ResizeObserver(() => {
					layoutVideoContent();
				});

				observer.observe(container);
				return () => {
					observer.disconnect();
				};
			}, [layoutVideoContent, previewSceneReady]);

			useEffect(() => {
				if (!corePreviewReady) return;
				updateOverlayForRegion(selectedZoom);
			}, [corePreviewReady, selectedZoom, updateOverlayForRegion]);

			useEffect(() => {
				if (!pixiReady) {
					return;
				}

				layoutFacecamOverlay();
			}, [layoutFacecamOverlay, pixiReady]);

			useEffect(() => {
				const overlayEl = overlayRef.current;
				if (!overlayEl) return;
				if (!selectedZoom) {
					overlayEl.style.cursor = "none";
					overlayEl.style.pointerEvents = "none";
					return;
				}
				overlayEl.style.cursor = isPlaying ? "not-allowed" : "grab";
				overlayEl.style.pointerEvents = "auto";
			}, [selectedZoom, isPlaying]);

			useEffect(() => {
				const container = containerRef.current;
				if (!container) return;

				let mounted = true;
				let app: Application | null = null;

				(async () => {
					await ensurePixiRuntime();

					app = new Application();

					await app.init({
						width: container.clientWidth,
						height: container.clientHeight,
						backgroundAlpha: 0,
						antialias: true,
						resolution: window.devicePixelRatio || 1,
						autoDensity: true,
					});

					app.ticker.maxFPS = 60;

					if (!mounted) {
						app.destroy(true, { children: true, texture: false, textureSource: false });
						return;
					}

					appRef.current = app;
					container.appendChild(app.canvas);

					// Camera container - this will be scaled/positioned for zoom
					const cameraContainer = new Container();
					cameraContainerRef.current = cameraContainer;
					app.stage.addChild(cameraContainer);

					const facecamContainer = new Container();
					facecamContainer.visible = false;
					facecamContainer.eventMode = "static";
					facecamContainer.cursor = "grab";
					facecamContainerRef.current = facecamContainer;
					app.stage.addChild(facecamContainer);

					// Video container - holds the masked video sprite
					const videoContainer = new Container();
					videoContainerRef.current = videoContainer;
					cameraContainer.addChild(videoContainer);

					const cursorContainer = new Container();
					cursorContainerRef.current = cursorContainer;
					cameraContainer.addChild(cursorContainer);

					setPixiReady(true);
					markVideoEditorTiming("pixi-init-complete");
				})().catch((error) => {
					console.error("Failed to initialize preview renderer:", error);
					onError(error instanceof Error ? error.message : "Failed to initialize preview renderer");
				});

				return () => {
					mounted = false;
					setPixiReady(false);
					setCursorOverlayReady(false);
					if (app && app.renderer) {
						app.destroy(true, { children: true, texture: false, textureSource: false });
					}
					appRef.current = null;
					cameraContainerRef.current = null;
					facecamContainerRef.current = null;
					facecamSpriteRef.current = null;
					facecamMaskRef.current = null;
					facecamBorderRef.current = null;
					videoContainerRef.current = null;
					cursorContainerRef.current = null;
					videoSpriteRef.current = null;
				};
			}, [onError]);

			useEffect(() => {
				if (!pixiReady) {
					return;
				}

				let cancelled = false;

				preloadCursorAssets()
					.then(() => {
						if (cancelled) {
							return;
						}

						const cursorContainer = cursorContainerRef.current;
						if (!cursorContainer) {
							return;
						}

						if (!cursorOverlayRef.current) {
							const cursorOverlay = new PixiCursorOverlay({
								dotRadius: DEFAULT_CURSOR_CONFIG.dotRadius * cursorSizeRef.current,
								smoothingFactor: cursorSmoothingRef.current,
								motionBlur: cursorMotionBlurRef.current,
								clickBounce: cursorClickBounceRef.current,
							});
							cursorOverlayRef.current = cursorOverlay;
							cursorContainer.addChild(cursorOverlay.container);
						}

						setCursorOverlayReady(true);
					})
					.catch((error) => {
						if (cancelled) {
							return;
						}

						setCursorOverlayReady(false);
						console.warn(
							"Native cursor assets are unavailable in preview; continuing without cursor overlay.",
							error,
						);
					});

				return () => {
					cancelled = true;
					setCursorOverlayReady(false);
					if (cursorOverlayRef.current) {
						cursorOverlayRef.current.destroy();
						cursorOverlayRef.current = null;
					}
				};
			}, [pixiReady]);

			useEffect(() => {
				if (metadataReady) {
					markVideoEditorTiming("metadata-loaded");
				}
			}, [metadataReady]);

			useEffect(() => {
				if (firstFrameReady) {
					markVideoEditorTiming("first-frame-ready");
				}
			}, [firstFrameReady]);

			useEffect(() => {
				if (cursorOverlayReady) {
					markVideoEditorTiming("cursor-assets-ready");
				}
			}, [cursorOverlayReady]);

			useEffect(() => {
				void videoPath;
				const video = videoRef.current;
				if (!video) return;
				video.pause();
				video.currentTime = 0;
				allowPlaybackRef.current = false;
				currentTimeRef.current = 0;
				lockedVideoDimensionsRef.current = null;
				prevVisibleAnnotationIdsRef.current = "";
				setMetadataReady(false);
				setFirstFrameReady(false);
				clearFirstFrameTimeout();
				cursorOverlayRef.current?.reset();
			}, [clearFirstFrameTimeout, videoPath]);

			useEffect(() => {
				void facecamVideoPath;
				const video = facecamVideoRef.current;
				if (!video) {
					return;
				}

				video.pause();
				video.currentTime = 0;
				setFacecamReady(false);
			}, [facecamVideoPath]);

			useEffect(() => {
				if (!previewSceneReady) return;

				const video = videoRef.current;
				const app = appRef.current;
				const videoContainer = videoContainerRef.current;

				if (!video || !app || !videoContainer) return;
				if (video.videoWidth === 0 || video.videoHeight === 0) return;

				const source = VideoSource.from(video);
				if ("autoPlay" in source) {
					(source as { autoPlay?: boolean }).autoPlay = false;
				}
				if ("autoUpdate" in source) {
					(source as { autoUpdate?: boolean }).autoUpdate = true;
				}
				const videoTexture = Texture.from(source);

				const videoSprite = new Sprite(videoTexture);
				videoSpriteRef.current = videoSprite;

				const maskGraphics = new Graphics();
				videoContainer.addChild(videoSprite);
				videoContainer.addChild(maskGraphics);
				videoContainer.mask = maskGraphics;
				maskGraphicsRef.current = maskGraphics;

				animationStateRef.current = createPlaybackAnimationState();

				const blurFilter = new BlurFilter();
				blurFilter.quality = 3;
				blurFilter.resolution = app.renderer.resolution;
				blurFilter.blur = 0;
				const motionBlurFilter = new MotionBlurFilter([0, 0], 5, 0);
				videoContainer.filters = [blurFilter, motionBlurFilter];
				blurFilterRef.current = blurFilter;
				motionBlurFilterRef.current = motionBlurFilter;

				layoutVideoContent();
				video.pause();

				const { handlePlay, handlePause, handleSeeked, handleSeeking } = createVideoEventHandlers({
					video,
					isSeekingRef,
					isPlayingRef,
					allowPlaybackRef,
					currentTimeRef,
					timeUpdateAnimationRef,
					onPlayStateChange,
					onTimeUpdate,
					trimRegionsRef,
					speedRegionsRef,
				});

				video.addEventListener("play", handlePlay);
				video.addEventListener("pause", handlePause);
				video.addEventListener("ended", handlePause);
				video.addEventListener("seeked", handleSeeked);
				video.addEventListener("seeking", handleSeeking);

				return () => {
					video.removeEventListener("play", handlePlay);
					video.removeEventListener("pause", handlePause);
					video.removeEventListener("ended", handlePause);
					video.removeEventListener("seeked", handleSeeked);
					video.removeEventListener("seeking", handleSeeking);

					if (timeUpdateAnimationRef.current) {
						cancelAnimationFrame(timeUpdateAnimationRef.current);
					}

					if (videoSprite) {
						videoContainer.removeChild(videoSprite);
						videoSprite.destroy();
					}
					if (maskGraphics) {
						videoContainer.removeChild(maskGraphics);
						maskGraphics.destroy();
					}
					videoContainer.mask = null;
					maskGraphicsRef.current = null;
					if (blurFilterRef.current) {
						videoContainer.filters = [];
						blurFilterRef.current.destroy();
						blurFilterRef.current = null;
					}
					if (motionBlurFilterRef.current) {
						motionBlurFilterRef.current.destroy();
						motionBlurFilterRef.current = null;
					}
					videoTexture.destroy(false);

					videoSpriteRef.current = null;
				};
			}, [layoutVideoContent, onPlayStateChange, onTimeUpdate, previewSceneReady]);

			useEffect(() => {
				if (!pixiReady || !facecamReady || !facecamVideoPath) {
					const facecamContainer = facecamContainerRef.current;
					if (facecamContainer) {
						facecamContainer.visible = false;
					}
					return;
				}

				const facecamVideo = facecamVideoRef.current;
				const app = appRef.current;
				const facecamContainer = facecamContainerRef.current;

				if (!facecamVideo || !app || !facecamContainer) {
					return;
				}

				const source = VideoSource.from(facecamVideo);
				if ("autoPlay" in source) {
					(source as { autoPlay?: boolean }).autoPlay = false;
				}
				if ("autoUpdate" in source) {
					(source as { autoUpdate?: boolean }).autoUpdate = true;
				}
				const facecamTexture = Texture.from(source);
				const facecamSprite = new Sprite(facecamTexture);
				const facecamMask = new Graphics();
				const facecamBorder = new Graphics();

				facecamSpriteRef.current = facecamSprite;
				facecamMaskRef.current = facecamMask;
				facecamBorderRef.current = facecamBorder;

				facecamContainer.addChild(facecamSprite);
				facecamContainer.addChild(facecamMask);
				facecamContainer.addChild(facecamBorder);
				facecamContainer.mask = facecamMask;

				layoutFacecamOverlay();

				return () => {
					facecamContainer.visible = false;
					facecamContainer.mask = null;
					facecamContainer.removeChildren();

					facecamBorder.destroy();
					facecamMask.destroy();
					facecamSprite.destroy();
					facecamTexture.destroy(false);

					facecamSpriteRef.current = null;
					facecamMaskRef.current = null;
					facecamBorderRef.current = null;
				};
			}, [pixiReady, facecamReady, facecamVideoPath, layoutFacecamOverlay]);

			// Facecam drag interaction
			useEffect(() => {
				const facecamContainer = facecamContainerRef.current;
				if (!facecamContainer || !onFacecamPositionChange) return;

				let isDragging = false;
				let dragOffsetX = 0;
				let dragOffsetY = 0;

				const onPointerDown = (event: FederatedPointerEvent) => {
					if (!facecamContainer.parent) return;
					isDragging = true;
					const localPos = facecamContainer.parent.toLocal(event.global);
					dragOffsetX = localPos.x - facecamContainer.x;
					dragOffsetY = localPos.y - facecamContainer.y;
					facecamContainer.cursor = "grabbing";
					facecamContainer.alpha = 0.85;
				};

				const onPointerMove = (event: FederatedPointerEvent) => {
					if (!isDragging || !facecamContainer.parent) return;

					const stageWidth = stageSizeRef.current.width;
					const stageHeight = stageSizeRef.current.height;
					if (!stageWidth || !stageHeight) return;

					const localPos = facecamContainer.parent.toLocal(event.global);
					const settings = facecamSettingsRef.current;
					if (!settings) return;

					const minDim = Math.min(stageWidth, stageHeight);
					const size = minDim * (settings.size / 100);

					const newX = Math.max(0, Math.min(localPos.x - dragOffsetX, stageWidth - size));
					const newY = Math.max(0, Math.min(localPos.y - dragOffsetY, stageHeight - size));

					// Update position directly for immediate visual feedback
					facecamContainer.x = newX - (facecamContainer.x !== 0 ? 0 : facecamContainer.x);
					// We need to move all children rather than the container when layout sets absolute positions
					const facecamSprite = facecamSpriteRef.current;
					const facecamMask = facecamMaskRef.current;
					const facecamBorder = facecamBorderRef.current;
					if (facecamSprite && facecamMask && facecamBorder && settings) {
						const layout = getFacecamLayout(stageWidth, stageHeight, settings);
						const dx = newX - layout.x;
						const dy = newY - layout.y;
						facecamContainer.position.set(dx, dy);
					}
				};

				const onPointerUp = () => {
					if (!isDragging) return;
					isDragging = false;
					facecamContainer.cursor = "grab";
					facecamContainer.alpha = 1;

					const stageWidth = stageSizeRef.current.width;
					const stageHeight = stageSizeRef.current.height;
					const settings = facecamSettingsRef.current;
					if (!stageWidth || !stageHeight || !settings) return;

					const minDim = Math.min(stageWidth, stageHeight);
					const size = minDim * (settings.size / 100);
					const layout = getFacecamLayout(stageWidth, stageHeight, settings);

					// Compute actual pixel position from container offset
					const pixelX = layout.x + facecamContainer.x;
					const pixelY = layout.y + facecamContainer.y;

					const newPosition = resolveAnchorFromPosition(
						pixelX,
						pixelY,
						size,
						stageWidth,
						stageHeight,
					);

					// Reset container offset - the layout will handle positioning
					facecamContainer.position.set(0, 0);
					onFacecamPositionChange(newPosition);
				};

				facecamContainer.on("pointerdown", onPointerDown);
				facecamContainer.on("globalpointermove", onPointerMove);
				facecamContainer.on("pointerup", onPointerUp);
				facecamContainer.on("pointerupoutside", onPointerUp);

				return () => {
					facecamContainer.off("pointerdown", onPointerDown);
					facecamContainer.off("globalpointermove", onPointerMove);
					facecamContainer.off("pointerup", onPointerUp);
					facecamContainer.off("pointerupoutside", onPointerUp);
				};
			}, [onFacecamPositionChange]);

			useEffect(() => {
				if (!previewSceneReady) return;

				const app = appRef.current;
				const videoSprite = videoSpriteRef.current;
				const videoContainer = videoContainerRef.current;
				const primaryVideo = videoRef.current;
				if (!app || !videoSprite || !videoContainer || !primaryVideo) return;

				const applyTransform = (
					transform: { scale: number; x: number; y: number },
					focus: ZoomFocus,
					motionIntensity: number,
					motionVector: { x: number; y: number },
				) => {
					const cameraContainer = cameraContainerRef.current;
					if (!cameraContainer) return;

					const state = animationStateRef.current;

					const appliedTransform = applyZoomTransform({
						cameraContainer,
						blurFilter: blurFilterRef.current,
						stageSize: stageSizeRef.current,
						baseMask: baseMaskRef.current,
						zoomScale: state.scale,
						zoomProgress: state.progress,
						focusX: focus.cx,
						focusY: focus.cy,
						motionIntensity,
						motionVector,
						isPlaying: isPlayingRef.current,
						motionBlurAmount: zoomMotionBlurRef.current,
						motionBlurFilter: motionBlurFilterRef.current,
						transformOverride: transform,
						motionBlurState: motionBlurStateRef.current,
						frameTimeMs: performance.now(),
					});

					state.x = appliedTransform.x;
					state.y = appliedTransform.y;
					state.appliedScale = appliedTransform.scale;
				};

				const ticker = () => {
					const { region, strength, blendedScale, transition } = findDominantRegion(
						zoomRegionsRef.current,
						currentTimeRef.current,
						{
							connectZooms: connectZoomsRef.current,
						},
					);

					const defaultFocus = DEFAULT_FOCUS;
					let targetScaleFactor = 1;
					let targetFocus = defaultFocus;
					let targetProgress = 0;

					// If a zoom is selected but video is not playing, show default unzoomed view
					// (the overlay will show where the zoom will be)
					const selectedId = selectedZoomIdRef.current;
					const hasSelectedZoom = selectedId !== null;
					const shouldShowUnzoomedView = hasSelectedZoom && !isPlayingRef.current;

					if (region && strength > 0 && !shouldShowUnzoomedView) {
						const zoomScale = blendedScale ?? ZOOM_DEPTH_SCALES[region.depth];
						const regionFocus = region.focus;

						targetScaleFactor = zoomScale;
						targetFocus = regionFocus;
						targetProgress = strength;

						if (transition) {
							const startTransform = computeZoomTransform({
								stageSize: stageSizeRef.current,
								baseMask: baseMaskRef.current,
								zoomScale: transition.startScale,
								zoomProgress: 1,
								focusX: transition.startFocus.cx,
								focusY: transition.startFocus.cy,
							});
							const endTransform = computeZoomTransform({
								stageSize: stageSizeRef.current,
								baseMask: baseMaskRef.current,
								zoomScale: transition.endScale,
								zoomProgress: 1,
								focusX: transition.endFocus.cx,
								focusY: transition.endFocus.cy,
							});

							const interpolatedTransform = {
								scale:
									startTransform.scale +
									(endTransform.scale - startTransform.scale) * transition.progress,
								x: startTransform.x + (endTransform.x - startTransform.x) * transition.progress,
								y: startTransform.y + (endTransform.y - startTransform.y) * transition.progress,
							};

							targetScaleFactor = interpolatedTransform.scale;
							targetFocus = computeFocusFromTransform({
								stageSize: stageSizeRef.current,
								baseMask: baseMaskRef.current,
								zoomScale: interpolatedTransform.scale,
								x: interpolatedTransform.x,
								y: interpolatedTransform.y,
							});
							targetProgress = 1;
						}
					}

					const state = animationStateRef.current;
					const prevScale = state.appliedScale;
					const prevX = state.x;
					const prevY = state.y;

					state.scale = targetScaleFactor;
					state.focusX = targetFocus.cx;
					state.focusY = targetFocus.cy;
					state.progress = targetProgress;

					const projectedTransform = computeZoomTransform({
						stageSize: stageSizeRef.current,
						baseMask: baseMaskRef.current,
						zoomScale: state.scale,
						zoomProgress: state.progress,
						focusX: state.focusX,
						focusY: state.focusY,
					});

					const appliedScale =
						Math.abs(projectedTransform.scale - prevScale) < ZOOM_SCALE_DEADZONE
							? projectedTransform.scale
							: projectedTransform.scale;
					const appliedX =
						Math.abs(projectedTransform.x - prevX) < ZOOM_TRANSLATION_DEADZONE_PX
							? projectedTransform.x
							: projectedTransform.x;
					const appliedY =
						Math.abs(projectedTransform.y - prevY) < ZOOM_TRANSLATION_DEADZONE_PX
							? projectedTransform.y
							: projectedTransform.y;

					const motionIntensity = Math.max(
						Math.abs(appliedScale - prevScale),
						Math.abs(appliedX - prevX) / Math.max(1, stageSizeRef.current.width),
						Math.abs(appliedY - prevY) / Math.max(1, stageSizeRef.current.height),
					);

					const motionVector = {
						x: appliedX - prevX,
						y: appliedY - prevY,
					};

					applyTransform(
						{ scale: appliedScale, x: appliedX, y: appliedY },
						targetFocus,
						motionIntensity,
						motionVector,
					);

					const facecamVideo = facecamVideoRef.current;
					const activeFacecamSettings = facecamSettingsRef.current;
					if (
						facecamVideo &&
						facecamVideo.readyState >= HTMLMediaElement.HAVE_METADATA &&
						facecamVideoPath &&
						activeFacecamSettings?.enabled
					) {
						const targetTime = Math.max(
							0,
							currentTimeRef.current / 1000 - facecamOffsetMsRef.current / 1000,
						);
						const withinDuration =
							!Number.isFinite(facecamVideo.duration) || targetTime <= facecamVideo.duration;

						facecamVideo.playbackRate = primaryVideo.playbackRate;

						if (!isPlayingRef.current || !withinDuration) {
							if (!facecamVideo.paused) {
								facecamVideo.pause();
							}
							if (withinDuration && Math.abs(facecamVideo.currentTime - targetTime) > 0.06) {
								facecamVideo.currentTime = targetTime;
							}
						} else {
							if (Math.abs(facecamVideo.currentTime - targetTime) > 0.12) {
								facecamVideo.currentTime = targetTime;
							}
							if (facecamVideo.paused) {
								facecamVideo.play().catch(() => {
									// no-op
								});
							}
						}
					}

					// Update cursor overlay
					const cursorOverlay = cursorOverlayRef.current;
					if (cursorOverlay) {
						const timeMs = currentTimeRef.current;
						cursorOverlay.update(
							cursorTelemetryRef.current,
							timeMs,
							baseMaskRef.current,
							showCursorRef.current,
							!isPlayingRef.current || isSeekingRef.current,
						);
					}

					// Track annotation visibility changes to trigger re-renders only when needed
					const annotations = annotationRegionsRef.current;
					if (annotations.length > 0) {
						const nowMs = currentTimeRef.current;
						const selId = selectedAnnotationIdRef.current;
						const visibleIds = annotations
							.filter((a) => a.id === selId || (nowMs >= a.startMs && nowMs <= a.endMs))
							.map((a) => a.id)
							.join(",");
						if (visibleIds !== prevVisibleAnnotationIdsRef.current) {
							prevVisibleAnnotationIdsRef.current = visibleIds;
							setAnnotationVisibilityTick((t) => t + 1);
						}
					}
				};

				app.ticker.add(ticker);
				return () => {
					if (app && app.ticker) {
						app.ticker.remove(ticker);
					}
				};
			}, [facecamVideoPath, previewSceneReady]);

			useEffect(() => {
				onReadyChange?.(corePreviewReady);
			}, [corePreviewReady, onReadyChange]);

			useEffect(() => {
				return () => {
					onReadyChange?.(false);
				};
			}, [onReadyChange]);

			useEffect(() => {
				const overlay = cursorOverlayRef.current;
				if (!overlay) {
					return;
				}

				overlay.setDotRadius(DEFAULT_CURSOR_CONFIG.dotRadius * cursorSize);
				overlay.setSmoothingFactor(cursorSmoothing);
				overlay.setMotionBlur(cursorMotionBlur);
				overlay.setClickBounce(cursorClickBounce);
				overlay.reset();
			}, [cursorSize, cursorSmoothing, cursorMotionBlur, cursorClickBounce]);

			const handleLoadedMetadata = (e: React.SyntheticEvent<HTMLVideoElement, Event>) => {
				const video = e.currentTarget;
				onDurationChange(video.duration);
				video.currentTime = 0;
				video.pause();
				allowPlaybackRef.current = false;
				currentTimeRef.current = 0;
				setMetadataReady(video.videoWidth > 0 && video.videoHeight > 0);
				clearFirstFrameTimeout();

				if (
					video.videoWidth > 0 &&
					video.videoHeight > 0 &&
					video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA
				) {
					setFirstFrameReady(true);
					return;
				}

				firstFrameTimeoutRef.current = window.setTimeout(() => {
					if (video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
						onError("Timed out while loading the first video frame");
					}
				}, FIRST_FRAME_TIMEOUT_MS);
			};

			const handleLoadedData = (e: React.SyntheticEvent<HTMLVideoElement, Event>) => {
				const video = e.currentTarget;
				clearFirstFrameTimeout();
				if (video.videoWidth > 0 && video.videoHeight > 0) {
					setMetadataReady(true);
				}
				if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
					setFirstFrameReady(true);
				}
			};

			const handleFacecamLoadedMetadata = () => {
				const video = facecamVideoRef.current;
				if (!video) {
					return;
				}

				video.currentTime = 0;
				video.pause();
				setFacecamReady(true);
			};

			const [resolvedWallpaper, setResolvedWallpaper] = useState<string | null>(null);
			const wallpaperResolutionIdRef = useRef(0);

			useEffect(() => {
				const resolutionId = wallpaperResolutionIdRef.current + 1;
				wallpaperResolutionIdRef.current = resolutionId;
				let mounted = true;
				(async () => {
					try {
						if (!wallpaper) {
							const def = await getAssetPath(DEFAULT_WALLPAPER_RELATIVE_PATH);
							if (mounted && wallpaperResolutionIdRef.current === resolutionId) {
								setResolvedWallpaper(def);
							}
							return;
						}

						if (isDirectlyRenderableWallpaper(wallpaper)) {
							if (mounted && wallpaperResolutionIdRef.current === resolutionId) {
								setResolvedWallpaper(wallpaper);
							}
							return;
						}

						const p = await getRenderableAssetUrl(await getAssetPath(wallpaper.replace(/^\//, "")));
						if (mounted && wallpaperResolutionIdRef.current === resolutionId) {
							setResolvedWallpaper(p);
						}
					} catch {
						if (mounted && wallpaperResolutionIdRef.current === resolutionId) {
							setResolvedWallpaper(wallpaper || DEFAULT_WALLPAPER_PATH);
						}
					}
				})();
				return () => {
					mounted = false;
				};
			}, [wallpaper]);

			useEffect(() => {
				return () => {
					clearFirstFrameTimeout();
				};
			}, [clearFirstFrameTimeout]);

			const isImageUrl = Boolean(resolvedWallpaper && isRenderableAssetUrl(resolvedWallpaper));
			const backgroundStyle = isImageUrl
				? { backgroundImage: `url(${resolvedWallpaper || ""})` }
				: { background: resolvedWallpaper || "" };

			const nativeAspectRatio = (() => {
				const locked = lockedVideoDimensionsRef.current;
				if (locked && locked.height > 0) {
					return locked.width / locked.height;
				}
				const video = videoRef.current;
				if (video && video.videoHeight > 0) {
					return video.videoWidth / video.videoHeight;
				}
				return 16 / 9;
			})();

			return (
				<div
					className="relative rounded-sm overflow-hidden"
					style={{
						width: "100%",
						aspectRatio: formatAspectRatioForCSS(aspectRatio, nativeAspectRatio),
					}}
				>
					{/* Background layer */}
					<div
						className="absolute inset-0 bg-cover bg-center"
						style={{
							...backgroundStyle,
							filter: backgroundBlur > 0 ? `blur(${backgroundBlur}px)` : "none",
						}}
					/>
					<div
						ref={containerRef}
						className="absolute inset-0"
						style={{
							cursor: "none",
							filter:
								showShadow && shadowIntensity > 0
									? `drop-shadow(0 ${shadowIntensity * 12}px ${shadowIntensity * 48}px rgba(0,0,0,${shadowIntensity * 0.7})) drop-shadow(0 ${shadowIntensity * 4}px ${shadowIntensity * 16}px rgba(0,0,0,${shadowIntensity * 0.5})) drop-shadow(0 ${shadowIntensity * 2}px ${shadowIntensity * 8}px rgba(0,0,0,${shadowIntensity * 0.3}))`
									: "none",
						}}
					/>
					{/* Only render overlay after the first video frame is ready */}
					{corePreviewReady && (
						<div
							ref={overlayRef}
							className="absolute inset-0 select-none"
							style={{ pointerEvents: "none" }}
							onPointerDown={handleOverlayPointerDown}
							onPointerMove={handleOverlayPointerMove}
							onPointerUp={handleOverlayPointerUp}
							onPointerLeave={handleOverlayPointerLeave}
						>
							<div
								ref={focusIndicatorRef}
								className="absolute rounded-md border border-[#2563EB]/80 bg-[#2563EB]/20 shadow-[0_0_0_1px_rgba(37,99,235,0.35)]"
								style={{ display: "none", pointerEvents: "none" }}
							/>
							{(() => {
								const filtered = (annotationRegions || []).filter((annotation) => {
									if (
										typeof annotation.startMs !== "number" ||
										typeof annotation.endMs !== "number"
									)
										return false;

									if (annotation.id === selectedAnnotationId) return true;

									const timeMs = Math.round(currentTimeRef.current);
									return timeMs >= annotation.startMs && timeMs <= annotation.endMs;
								});

								// Sort by z-index (lowest to highest) so higher z-index renders on top
								const sorted = [...filtered].sort((a, b) => a.zIndex - b.zIndex);

								// Handle click-through cycling: when clicking same annotation, cycle to next
								const handleAnnotationClick = (clickedId: string) => {
									if (!onSelectAnnotation) return;

									// If clicking on already selected annotation and there are multiple overlapping
									if (clickedId === selectedAnnotationId && sorted.length > 1) {
										// Find current index and cycle to next
										const currentIndex = sorted.findIndex((a) => a.id === clickedId);
										const nextIndex = (currentIndex + 1) % sorted.length;
										onSelectAnnotation(sorted[nextIndex].id);
									} else {
										// First click or clicking different annotation
										onSelectAnnotation(clickedId);
									}
								};

								return sorted.map((annotation) => (
									<AnnotationOverlay
										key={annotation.id}
										annotation={annotation}
										isSelected={annotation.id === selectedAnnotationId}
										containerWidth={overlayRef.current?.clientWidth || 800}
										containerHeight={overlayRef.current?.clientHeight || 600}
										onPositionChange={(id, position) => onAnnotationPositionChange?.(id, position)}
										onSizeChange={(id, size) => onAnnotationSizeChange?.(id, size)}
										onClick={handleAnnotationClick}
										zIndex={annotation.zIndex}
										isSelectedBoost={annotation.id === selectedAnnotationId}
									/>
								));
							})()}
						</div>
					)}
					<video
						ref={videoRef}
						src={videoPath}
						preload="auto"
						muted={audioMuted}
						playsInline
						style={OFFSCREEN_MEDIA_SOURCE_STYLE}
						onLoadedMetadata={handleLoadedMetadata}
						onLoadedData={handleLoadedData}
						onDurationChange={(e) => {
							onDurationChange(e.currentTarget.duration);
						}}
						onError={() => {
							clearFirstFrameTimeout();
							onError("Failed to load video");
						}}
					/>
					{facecamVideoPath && (
						<video
							ref={facecamVideoRef}
							src={facecamVideoPath}
							preload="auto"
							muted
							playsInline
							style={OFFSCREEN_MEDIA_SOURCE_STYLE}
							onLoadedMetadata={handleFacecamLoadedMetadata}
							onError={() => setFacecamReady(false)}
						/>
					)}
				</div>
			);
		},
	),
);

VideoPlayback.displayName = "VideoPlayback";

export default VideoPlayback;
