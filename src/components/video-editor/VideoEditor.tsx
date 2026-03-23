import type { Span } from "dnd-timeline";
import {
	ChevronDown,
	Download,
	Film,
	FolderOpen,
	HelpCircle,
	Image,
	LoaderCircle,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
	Empty,
	EmptyDescription,
	EmptyHeader,
	EmptyMedia,
	EmptyTitle,
} from "@/components/ui/empty";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Switch } from "@/components/ui/switch";
import { Profiler, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Panel, PanelGroup, PanelResizeHandle } from "react-resizable-panels";
import { toast } from "sonner";
import { UpdateNotification } from "@/components/UpdateNotification";
import { Toaster } from "@/components/ui/sonner";
import { useShortcuts } from "@/contexts/ShortcutsContext";
import { getAssetPath } from "@/lib/assetPath";
import * as backend from "@/lib/backend";
import { getSuggestedExportFileName } from "@/lib/exportFileName";
import {
	calculateOutputDimensions,
	type ExportFormat,
	type ExportProgress,
	type ExportQuality,
	type ExportSettings,
	GIF_FRAME_RATES,
	GIF_SIZE_PRESETS,
	GifExporter,
	type GifFrameRate,
	type GifSizePreset,
	VideoExporter,
} from "@/lib/exporter";
import { onRenderProfiler } from "@/lib/perf";
import {
	createDefaultFacecamSettings,
	type FacecamSettings,
	normalizeFacecamSettings,
} from "@/lib/recordingSession";
import { matchesShortcut } from "@/lib/shortcuts";
import { DEFAULT_WALLPAPER_RELATIVE_PATH, WALLPAPER_PATHS } from "@/lib/wallpapers";
import { type AspectRatio, getAspectRatioValue } from "@/utils/aspectRatioUtils";
import { ExportDialog } from "./ExportDialog";
import PlaybackControls from "./PlaybackControls";
import {
	createProjectData,
	deriveNextId,
	fromFileUrl,
	normalizeProjectEditor,
	toFileUrl,
	validateProjectData,
} from "./projectPersistence";
import { SettingsPanel } from "./SettingsPanel";
import { AllShortcutsDialog } from "./AllShortcutsDialog";
import TimelineEditor from "./timeline/TimelineEditor";
import {
	detectInteractionCandidates,
	normalizeCursorTelemetry,
} from "./timeline/zoomSuggestionUtils";
import {
	type AnnotationRegion,
	type CropRegion,
	type CursorTelemetryPoint,
	clampFocusToDepth,
	DEFAULT_ANNOTATION_POSITION,
	DEFAULT_ANNOTATION_SIZE,
	DEFAULT_ANNOTATION_STYLE,
	DEFAULT_CROP_REGION,
	DEFAULT_CURSOR_CLICK_BOUNCE,
	DEFAULT_CURSOR_MOTION_BLUR,
	DEFAULT_CURSOR_SIZE,
	DEFAULT_CURSOR_SMOOTHING,
	DEFAULT_FIGURE_DATA,
	DEFAULT_PLAYBACK_SPEED,
	DEFAULT_ZOOM_DEPTH,
	DEFAULT_ZOOM_MOTION_BLUR,
	type FigureData,
	type PlaybackSpeed,
	type SpeedRegion,
	type TrimRegion,
	type ZoomDepth,
	type ZoomFocus,
	type ZoomRegion,
} from "./types";
import { useTimeStore } from "./useTimeStore";
import VideoPlayback, { VideoPlaybackRef } from "./VideoPlayback";
import {
	buildLoopedCursorTelemetry,
	getDisplayedTimelineWindowMs,
} from "./videoPlayback/cursorLoopTelemetry";
import { findDominantRegion } from "./videoPlayback/zoomRegionUtils";

const LOOP_CURSOR_END_WINDOW_MS = 670;

type EditorHistorySnapshot = {
	zoomRegions: ZoomRegion[];
	trimRegions: TrimRegion[];
	speedRegions: SpeedRegion[];
	annotationRegions: AnnotationRegion[];
	selectedZoomId: string | null;
	selectedTrimId: string | null;
	selectedSpeedId: string | null;
	selectedAnnotationId: string | null;
	signature: string;
};

type PendingExportSave = {
	fileName: string;
	arrayBuffer: ArrayBuffer;
};

function getZoomRegionSignature(region: ZoomRegion) {
	return `${region.id}:${region.startMs}:${region.endMs}:${region.depth}:${region.focus.cx}:${region.focus.cy}`;
}

function getTrimRegionSignature(region: TrimRegion) {
	return `${region.id}:${region.startMs}:${region.endMs}`;
}

function getSpeedRegionSignature(region: SpeedRegion) {
	return `${region.id}:${region.startMs}:${region.endMs}:${region.speed}`;
}

function getAnnotationRegionSignature(region: AnnotationRegion) {
	return [
		region.id,
		region.startMs,
		region.endMs,
		region.type,
		region.content,
		region.textContent ?? "",
		region.imageContent ?? "",
		region.position.x,
		region.position.y,
		region.size.width,
		region.size.height,
		region.style.fontSize,
		region.style.color,
		region.style.backgroundColor,
		region.style.fontFamily ?? "",
		region.style.fontWeight ?? "",
		region.style.fontStyle,
		region.style.textDecoration,
		region.style.textAlign,
		region.zIndex,
		region.figureData?.arrowDirection ?? "",
		region.figureData?.color ?? "",
		region.figureData?.strokeWidth ?? 0,
	].join(":");
}

function createHistorySignature(snapshot: Omit<EditorHistorySnapshot, "signature">) {
	return [
		snapshot.zoomRegions.map(getZoomRegionSignature).join("|"),
		snapshot.trimRegions.map(getTrimRegionSignature).join("|"),
		snapshot.speedRegions.map(getSpeedRegionSignature).join("|"),
		snapshot.annotationRegions.map(getAnnotationRegionSignature).join("|"),
		snapshot.selectedZoomId ?? "",
		snapshot.selectedTrimId ?? "",
		snapshot.selectedSpeedId ?? "",
		snapshot.selectedAnnotationId ?? "",
	].join("~");
}

export default function VideoEditor() {
	console.log("render <VideoEditor>");
	const [videoPath, setVideoPath] = useState<string | null>(null);
	const [videoSourcePath, setVideoSourcePath] = useState<string | null>(null);
	const [facecamVideoPath, setFacecamVideoPath] = useState<string | null>(null);
	const [facecamPlaybackPath, setFacecamPlaybackPath] = useState<string | null>(null);
	const [facecamOffsetMs, setFacecamOffsetMs] = useState(0);
	const [currentProjectPath, setCurrentProjectPath] = useState<string | null>(null);
	const [loading, setLoading] = useState(true);
	const [playbackReady, setPlaybackReady] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const [isPlaying, setIsPlaying] = useState(false);
	const timeStore = useTimeStore();
	const [duration, setDuration] = useState(0);
	const [wallpaper, setWallpaper] = useState<string>(WALLPAPER_PATHS[0]);
	const [shadowIntensity, setShadowIntensity] = useState(0.67);
	const [backgroundBlur, setBackgroundBlur] = useState(0);
	const [zoomMotionBlur, setZoomMotionBlur] = useState(DEFAULT_ZOOM_MOTION_BLUR);
	const [connectZooms, setConnectZooms] = useState(true);
	const [showCursor, setShowCursor] = useState(true);
	const [loopCursor, setLoopCursor] = useState(false);
	const [cursorSize, setCursorSize] = useState(DEFAULT_CURSOR_SIZE);
	const [cursorSmoothing, setCursorSmoothing] = useState(DEFAULT_CURSOR_SMOOTHING);
	const [cursorMotionBlur, setCursorMotionBlur] = useState(DEFAULT_CURSOR_MOTION_BLUR);
	const [cursorClickBounce, setCursorClickBounce] = useState(DEFAULT_CURSOR_CLICK_BOUNCE);
	const [borderRadius, setBorderRadius] = useState(12.5);
	const [padding, setPadding] = useState(50);
	const [cropRegion, setCropRegion] = useState<CropRegion>(DEFAULT_CROP_REGION);
	const [facecamSettings, setFacecamSettings] = useState<FacecamSettings>(
		createDefaultFacecamSettings(false),
	);
	const [zoomRegions, setZoomRegions] = useState<ZoomRegion[]>([]);
	const [cursorTelemetry, setCursorTelemetry] = useState<CursorTelemetryPoint[]>([]);
	const [selectedZoomId, setSelectedZoomId] = useState<string | null>(null);
	const [trimRegions, setTrimRegions] = useState<TrimRegion[]>([]);
	const [selectedTrimId, setSelectedTrimId] = useState<string | null>(null);
	const [speedRegions, setSpeedRegions] = useState<SpeedRegion[]>([]);
	const [selectedSpeedId, setSelectedSpeedId] = useState<string | null>(null);
	const [annotationRegions, setAnnotationRegions] = useState<AnnotationRegion[]>([]);
	const [selectedAnnotationId, setSelectedAnnotationId] = useState<string | null>(null);
	const [isExporting, setIsExporting] = useState(false);
	const [exportProgress, setExportProgress] = useState<ExportProgress | null>(null);
	const [exportError, setExportError] = useState<string | null>(null);
	const [showExportDialog, setShowExportDialog] = useState(false);
	const [showShortcutsDialog, setShowShortcutsDialog] = useState(false);
	const [aspectRatio, setAspectRatio] = useState<AspectRatio>("16:9");
	const [exportQuality, setExportQuality] = useState<ExportQuality>("good");
	const [exportFormat, setExportFormat] = useState<ExportFormat>("mp4");
	const [gifFrameRate, setGifFrameRate] = useState<GifFrameRate>(15);
	const [gifLoop, setGifLoop] = useState(true);
	const [gifSizePreset, setGifSizePreset] = useState<GifSizePreset>("medium");
	const [exportedFilePath, setExportedFilePath] = useState<string | undefined>(undefined);
	const [hasPendingExportSave, setHasPendingExportSave] = useState(false);
	const [lastSavedSnapshot, setLastSavedSnapshot] = useState<string | null>(null);

	const videoPlaybackRef = useRef<VideoPlaybackRef>(null);
	const nextZoomIdRef = useRef(1);
	const nextTrimIdRef = useRef(1);
	const nextSpeedIdRef = useRef(1);

	const { shortcuts, isMac } = useShortcuts();
	const nextAnnotationIdRef = useRef(1);
	const nextAnnotationZIndexRef = useRef(1); // Track z-index for stacking order
	const exporterRef = useRef<VideoExporter | null>(null);
	const autoSuggestedVideoPathRef = useRef<string | null>(null);
	const historyPastRef = useRef<EditorHistorySnapshot[]>([]);
	const historyFutureRef = useRef<EditorHistorySnapshot[]>([]);
	const historyCurrentRef = useRef<EditorHistorySnapshot | null>(null);
	const applyingHistoryRef = useRef(false);
	const pendingExportSaveRef = useRef<PendingExportSave | null>(null);

	const cloneSnapshot = useCallback((snapshot: EditorHistorySnapshot): EditorHistorySnapshot => {
		return {
			zoomRegions: [...snapshot.zoomRegions],
			trimRegions: [...snapshot.trimRegions],
			speedRegions: [...snapshot.speedRegions],
			annotationRegions: [...snapshot.annotationRegions],
			selectedZoomId: snapshot.selectedZoomId,
			selectedTrimId: snapshot.selectedTrimId,
			selectedSpeedId: snapshot.selectedSpeedId,
			selectedAnnotationId: snapshot.selectedAnnotationId,
			signature: snapshot.signature,
		};
	}, []);

	const buildHistorySnapshot = useCallback((): EditorHistorySnapshot => {
		const snapshot = {
			zoomRegions,
			trimRegions,
			speedRegions,
			annotationRegions,
			selectedZoomId,
			selectedTrimId,
			selectedSpeedId,
			selectedAnnotationId,
		};
		return {
			...snapshot,
			signature: createHistorySignature(snapshot),
		};
	}, [
		zoomRegions,
		trimRegions,
		speedRegions,
		annotationRegions,
		selectedZoomId,
		selectedTrimId,
		selectedSpeedId,
		selectedAnnotationId,
	]);

	const applyHistorySnapshot = useCallback(
		(snapshot: EditorHistorySnapshot) => {
			applyingHistoryRef.current = true;
			const cloned = cloneSnapshot(snapshot);
			setZoomRegions(cloned.zoomRegions);
			setTrimRegions(cloned.trimRegions);
			setSpeedRegions(cloned.speedRegions);
			setAnnotationRegions(cloned.annotationRegions);
			setSelectedZoomId(cloned.selectedZoomId);
			setSelectedTrimId(cloned.selectedTrimId);
			setSelectedSpeedId(cloned.selectedSpeedId);
			setSelectedAnnotationId(cloned.selectedAnnotationId);

			nextZoomIdRef.current = deriveNextId(
				"zoom",
				cloned.zoomRegions.map((region) => region.id),
			);
			nextTrimIdRef.current = deriveNextId(
				"trim",
				cloned.trimRegions.map((region) => region.id),
			);
			nextSpeedIdRef.current = deriveNextId(
				"speed",
				cloned.speedRegions.map((region) => region.id),
			);
			nextAnnotationIdRef.current = deriveNextId(
				"annotation",
				cloned.annotationRegions.map((region) => region.id),
			);
			nextAnnotationZIndexRef.current =
				cloned.annotationRegions.reduce((max, region) => Math.max(max, region.zIndex), 0) + 1;
		},
		[cloneSnapshot],
	);

	const handleUndo = useCallback(() => {
		if (historyPastRef.current.length === 0) return;

		const current = historyCurrentRef.current ?? cloneSnapshot(buildHistorySnapshot());
		const previous = historyPastRef.current.pop();
		if (!previous) return;

		historyFutureRef.current.push(cloneSnapshot(current));
		historyCurrentRef.current = cloneSnapshot(previous);
		applyHistorySnapshot(previous);
	}, [applyHistorySnapshot, buildHistorySnapshot, cloneSnapshot]);

	const handleRedo = useCallback(() => {
		if (historyFutureRef.current.length === 0) return;

		const current = historyCurrentRef.current ?? cloneSnapshot(buildHistorySnapshot());
		const next = historyFutureRef.current.pop();
		if (!next) return;

		historyPastRef.current.push(cloneSnapshot(current));
		historyCurrentRef.current = cloneSnapshot(next);
		applyHistorySnapshot(next);
	}, [applyHistorySnapshot, buildHistorySnapshot, cloneSnapshot]);

	const resolvePlaybackPaths = useCallback(
		async (sourcePath: string, nextFacecamPath?: string | null) => {
			const [resolvedVideoPath, resolvedFacecamPath] = await Promise.all([
				backend.resolveMediaPlaybackUrl(sourcePath),
				nextFacecamPath ? backend.resolveMediaPlaybackUrl(nextFacecamPath) : Promise.resolve(null),
			]);

			return {
				resolvedVideoPath,
				resolvedFacecamPath,
			};
		},
		[],
	);

	const applyLoadedProject = useCallback(
		async (candidate: unknown, path?: string | null) => {
			if (!validateProjectData(candidate)) {
				return false;
			}

			const project = candidate;
			const sourcePath = fromFileUrl(project.videoPath);
			const normalizedEditor = normalizeProjectEditor(project.editor);
			const normalizedFacecam = normalizeFacecamSettings(project.editor.facecamSettings, {
				defaultEnabled:
					typeof project.facecamVideoPath === "string" && project.facecamVideoPath.length > 0,
			});
			const normalizedFacecamVideoPath =
				typeof project.facecamVideoPath === "string" && project.facecamVideoPath
					? fromFileUrl(project.facecamVideoPath)
					: null;
			const normalizedFacecamOffsetMs =
				typeof project.facecamOffsetMs === "number" && Number.isFinite(project.facecamOffsetMs)
					? project.facecamOffsetMs
					: 0;
			const { resolvedVideoPath, resolvedFacecamPath } = await resolvePlaybackPaths(
				sourcePath,
				normalizedFacecamVideoPath,
			);

			try {
				videoPlaybackRef.current?.pause();
			} catch {
				// no-op
			}
			setIsPlaying(false);
			timeStore.setTime(0);
			setDuration(0);

			setError(null);
			setVideoSourcePath(sourcePath);
			setVideoPath(resolvedVideoPath);
			setFacecamVideoPath(normalizedFacecamVideoPath);
			setFacecamPlaybackPath(resolvedFacecamPath);
			setFacecamOffsetMs(normalizedFacecamOffsetMs);
			setCurrentProjectPath(path ?? null);

			setWallpaper(normalizedEditor.wallpaper);
			setShadowIntensity(normalizedEditor.shadowIntensity);
			setBackgroundBlur(normalizedEditor.backgroundBlur);
			setZoomMotionBlur(normalizedEditor.zoomMotionBlur);
			setConnectZooms(normalizedEditor.connectZooms);
			setShowCursor(normalizedEditor.showCursor);
			setLoopCursor(normalizedEditor.loopCursor);
			setCursorSize(normalizedEditor.cursorSize);
			setCursorSmoothing(normalizedEditor.cursorSmoothing);
			setCursorMotionBlur(normalizedEditor.cursorMotionBlur);
			setCursorClickBounce(normalizedEditor.cursorClickBounce);
			setBorderRadius(normalizedEditor.borderRadius);
			setPadding(normalizedEditor.padding);
			setCropRegion(normalizedEditor.cropRegion);
			setFacecamSettings(normalizedFacecam);
			setZoomRegions(normalizedEditor.zoomRegions);
			setTrimRegions(normalizedEditor.trimRegions);
			setSpeedRegions(normalizedEditor.speedRegions);
			setAnnotationRegions(normalizedEditor.annotationRegions);
			setAspectRatio(normalizedEditor.aspectRatio);
			setExportQuality(normalizedEditor.exportQuality);
			setExportFormat(normalizedEditor.exportFormat);
			setGifFrameRate(normalizedEditor.gifFrameRate);
			setGifLoop(normalizedEditor.gifLoop);
			setGifSizePreset(normalizedEditor.gifSizePreset);

			setSelectedZoomId(null);
			setSelectedTrimId(null);
			setSelectedSpeedId(null);
			setSelectedAnnotationId(null);

			nextZoomIdRef.current = deriveNextId(
				"zoom",
				normalizedEditor.zoomRegions.map((region) => region.id),
			);
			nextTrimIdRef.current = deriveNextId(
				"trim",
				normalizedEditor.trimRegions.map((region) => region.id),
			);
			nextSpeedIdRef.current = deriveNextId(
				"speed",
				normalizedEditor.speedRegions.map((region) => region.id),
			);
			nextAnnotationIdRef.current = deriveNextId(
				"annotation",
				normalizedEditor.annotationRegions.map((region) => region.id),
			);
			nextAnnotationZIndexRef.current =
				normalizedEditor.annotationRegions.reduce(
					(max, region) => Math.max(max, region.zIndex),
					0,
				) + 1;

			setLastSavedSnapshot(
				JSON.stringify(
					createProjectData(
						sourcePath,
						{
							...normalizedEditor,
							facecamSettings: normalizedFacecam,
						},
						{
							facecamVideoPath: normalizedFacecamVideoPath,
							facecamOffsetMs: normalizedFacecamOffsetMs,
						},
					),
				),
			);
			return true;
		},
		[resolvePlaybackPaths, timeStore],
	);

	const currentProjectSnapshot = useMemo(() => {
		const sourcePath = videoSourcePath;
		if (!sourcePath) {
			return null;
		}
		return JSON.stringify(
			createProjectData(
				sourcePath,
				{
					wallpaper,
					shadowIntensity,
					backgroundBlur,
					zoomMotionBlur,
					connectZooms,
					showCursor,
					loopCursor,
					cursorSize,
					cursorSmoothing,
					cursorMotionBlur,
					cursorClickBounce,
					borderRadius,
					padding,
					cropRegion,
					facecamSettings,
					zoomRegions,
					trimRegions,
					speedRegions,
					annotationRegions,
					aspectRatio,
					exportQuality,
					exportFormat,
					gifFrameRate,
					gifLoop,
					gifSizePreset,
				},
				{
					facecamVideoPath,
					facecamOffsetMs,
				},
			),
		);
	}, [
		videoSourcePath,
		facecamVideoPath,
		facecamOffsetMs,
		wallpaper,
		shadowIntensity,
		backgroundBlur,
		zoomMotionBlur,
		connectZooms,
		showCursor,
		loopCursor,
		cursorSize,
		cursorSmoothing,
		cursorMotionBlur,
		cursorClickBounce,
		borderRadius,
		padding,
		cropRegion,
		facecamSettings,
		zoomRegions,
		trimRegions,
		speedRegions,
		annotationRegions,
		aspectRatio,
		exportQuality,
		exportFormat,
		gifFrameRate,
		gifLoop,
		gifSizePreset,
	]);

	useEffect(() => {
		const snapshot = cloneSnapshot(buildHistorySnapshot());

		if (!historyCurrentRef.current) {
			historyCurrentRef.current = snapshot;
			return;
		}

		if (applyingHistoryRef.current) {
			historyCurrentRef.current = snapshot;
			applyingHistoryRef.current = false;
			return;
		}

		if (historyCurrentRef.current.signature === snapshot.signature) {
			return;
		}

		historyPastRef.current.push(cloneSnapshot(historyCurrentRef.current));
		if (historyPastRef.current.length > 100) {
			historyPastRef.current.shift();
		}
		historyCurrentRef.current = snapshot;
		historyFutureRef.current = [];
	}, [buildHistorySnapshot, cloneSnapshot]);

	const hasUnsavedChanges = Boolean(
		currentProjectPath &&
			currentProjectSnapshot &&
			lastSavedSnapshot &&
			currentProjectSnapshot !== lastSavedSnapshot,
	);

	useEffect(() => {
		async function loadInitialData() {
			try {
				const currentProjectResult = await backend.loadCurrentProjectFile();
				if (currentProjectResult?.data) {
					const restored = await applyLoadedProject(
						currentProjectResult.data,
						currentProjectResult.filePath ?? null,
					);
					if (restored) {
						return;
					}
				}

				const videoPathResult = await backend.getCurrentVideoPath();
				const session = await backend.getCurrentRecordingSession();
				if (session?.screenVideoPath) {
					const sourcePath = fromFileUrl(session.screenVideoPath);
					const nextFacecamPath = session.facecamVideoPath
						? fromFileUrl(session.facecamVideoPath)
						: null;
					const { resolvedVideoPath, resolvedFacecamPath } = await resolvePlaybackPaths(
						sourcePath,
						nextFacecamPath,
					);
					setVideoSourcePath(sourcePath);
					setVideoPath(resolvedVideoPath);
					setFacecamVideoPath(nextFacecamPath);
					setFacecamPlaybackPath(resolvedFacecamPath);
					setFacecamOffsetMs(session.facecamOffsetMs ?? 0);
					setFacecamSettings(
						normalizeFacecamSettings(session.facecamSettings, {
							defaultEnabled: Boolean(nextFacecamPath),
						}),
					);
					setCurrentProjectPath(null);
					setLastSavedSnapshot(null);
				} else if (videoPathResult) {
					const sourcePath = fromFileUrl(videoPathResult);
					const resolvedVideoPath = await backend.resolveMediaPlaybackUrl(sourcePath);
					setVideoSourcePath(sourcePath);
					setVideoPath(resolvedVideoPath);
					setFacecamVideoPath(null);
					setFacecamPlaybackPath(null);
					setFacecamOffsetMs(0);
					setFacecamSettings(createDefaultFacecamSettings(false));
					setCurrentProjectPath(null);
					setLastSavedSnapshot(null);
				} else {
					setError("No video to load. Please record or select a video.");
				}
			} catch (err) {
				setError("Error loading video: " + String(err));
			} finally {
				setLoading(false);
			}
		}

		loadInitialData();
	}, [applyLoadedProject, resolvePlaybackPaths]);

	const saveProject = useCallback(
		async (forceSaveAs: boolean) => {
			if (!videoPath) {
				toast.error("No video loaded");
				return;
			}

			const sourcePath = videoSourcePath;
			if (!sourcePath) {
				toast.error("Unable to determine source video path");
				return;
			}

			const projectData = createProjectData(
				sourcePath,
				{
					wallpaper,
					shadowIntensity,
					backgroundBlur,
					zoomMotionBlur,
					connectZooms,
					showCursor,
					loopCursor,
					cursorSize,
					cursorSmoothing,
					cursorMotionBlur,
					cursorClickBounce,
					borderRadius,
					padding,
					cropRegion,
					facecamSettings,
					zoomRegions,
					trimRegions,
					speedRegions,
					annotationRegions,
					aspectRatio,
					exportQuality,
					exportFormat,
					gifFrameRate,
					gifLoop,
					gifSizePreset,
				},
				{
					facecamVideoPath,
					facecamOffsetMs,
				},
			);

			const fileNameBase =
				sourcePath
					.split(/[\\/]/)
					.pop()
					?.replace(/\.[^.]+$/, "") || `project-${Date.now()}`;
			const projectSnapshot = JSON.stringify(projectData);
			const savedPath = await backend.saveProjectFile(
				JSON.stringify(projectData),
				`${fileNameBase}.openrecorder`,
				forceSaveAs ? undefined : (currentProjectPath ?? undefined),
			);

			if (!savedPath) {
				toast.info("Project save canceled");
				return;
			}

			setCurrentProjectPath(savedPath);
			setLastSavedSnapshot(projectSnapshot);

			toast.success(`Project saved to ${savedPath}`);
		},
		[
			videoPath,
			videoSourcePath,
			facecamVideoPath,
			facecamOffsetMs,
			currentProjectPath,
			wallpaper,
			shadowIntensity,
			backgroundBlur,
			zoomMotionBlur,
			connectZooms,
			showCursor,
			loopCursor,
			cursorSize,
			cursorSmoothing,
			cursorMotionBlur,
			cursorClickBounce,
			borderRadius,
			padding,
			cropRegion,
			facecamSettings,
			zoomRegions,
			trimRegions,
			speedRegions,
			annotationRegions,
			aspectRatio,
			exportQuality,
			exportFormat,
			gifFrameRate,
			gifLoop,
			gifSizePreset,
		],
	);

	useEffect(() => {
		const handleBeforeUnload = (event: BeforeUnloadEvent) => {
			if (!hasUnsavedChanges) {
				return;
			}

			event.preventDefault();
			event.returnValue = "";
		};

		window.addEventListener("beforeunload", handleBeforeUnload);
		return () => window.removeEventListener("beforeunload", handleBeforeUnload);
	}, [hasUnsavedChanges]);

	useEffect(() => {
		backend.setHasUnsavedChanges(hasUnsavedChanges).catch(() => {
			// Best-effort sync with the native close guard.
		});
	}, [hasUnsavedChanges]);

	useEffect(() => {
		let unlisten: (() => void) | undefined;
		backend
			.onRequestSaveBeforeClose(async () => {
				await saveProject(false);
			})
			.then((fn) => {
				unlisten = fn;
			});

		return () => unlisten?.();
	}, [saveProject]);

	const handleSaveProject = useCallback(async () => {
		await saveProject(false);
	}, [saveProject]);

	const handleSaveProjectAs = useCallback(async () => {
		await saveProject(true);
	}, [saveProject]);

	const handleLoadProject = useCallback(async () => {
		try {
			const result = await backend.loadProjectFile();

			if (!result) {
				return;
			}

			const restored = await applyLoadedProject(result.data, result.filePath ?? null);
			if (!restored) {
				toast.error("Invalid project file format");
				return;
			}

			toast.success(`Project loaded from ${result.filePath}`);
		} catch (loadError) {
			toast.error(`Failed to load project: ${String(loadError)}`);
		}
	}, [applyLoadedProject]);

	useEffect(() => {
		let unlistenLoad: (() => void) | undefined;
		let unlistenSave: (() => void) | undefined;
		let unlistenSaveAs: (() => void) | undefined;

		backend.onMenuLoadProject(handleLoadProject).then((fn) => {
			unlistenLoad = fn;
		});
		backend.onMenuSaveProject(handleSaveProject).then((fn) => {
			unlistenSave = fn;
		});
		backend.onMenuSaveProjectAs(handleSaveProjectAs).then((fn) => {
			unlistenSaveAs = fn;
		});

		return () => {
			unlistenLoad?.();
			unlistenSave?.();
			unlistenSaveAs?.();
		};
	}, [handleLoadProject, handleSaveProject, handleSaveProjectAs]);

	useEffect(() => {
		let mounted = true;

		async function loadCursorTelemetry() {
			if (!videoSourcePath) {
				if (mounted) {
					setCursorTelemetry([]);
				}
				return;
			}

			try {
				const result = await backend.getCursorTelemetry(videoSourcePath);
				if (mounted) {
					setCursorTelemetry(result?.samples ?? []);
				}
			} catch (telemetryError) {
				console.warn("Unable to load cursor telemetry:", telemetryError);
				if (mounted) {
					setCursorTelemetry([]);
				}
			}
		}

		loadCursorTelemetry();

		return () => {
			mounted = false;
		};
	}, [videoSourcePath]);

	const normalizedCursorTelemetry = useMemo(() => {
		if (cursorTelemetry.length === 0) {
			return [] as CursorTelemetryPoint[];
		}

		const totalMs = Math.max(0, Math.round(duration * 1000));
		return normalizeCursorTelemetry(
			cursorTelemetry,
			totalMs > 0 ? totalMs : Number.MAX_SAFE_INTEGER,
		);
	}, [cursorTelemetry, duration]);

	const displayedTimelineWindow = useMemo(() => {
		const totalMs = Math.max(0, Math.round(duration * 1000));
		return getDisplayedTimelineWindowMs(totalMs, trimRegions);
	}, [duration, trimRegions]);

	const effectiveCursorTelemetry = useMemo(() => {
		if (!loopCursor) {
			return normalizedCursorTelemetry;
		}

		if (
			normalizedCursorTelemetry.length < 2 ||
			displayedTimelineWindow.endMs <= displayedTimelineWindow.startMs
		) {
			return normalizedCursorTelemetry;
		}

		return buildLoopedCursorTelemetry(
			normalizedCursorTelemetry,
			displayedTimelineWindow.endMs,
			displayedTimelineWindow.startMs,
		);
	}, [loopCursor, normalizedCursorTelemetry, displayedTimelineWindow]);

	const effectiveZoomRegions = useMemo(() => {
		if (!loopCursor || zoomRegions.length === 0) {
			return zoomRegions;
		}

		if (displayedTimelineWindow.endMs <= displayedTimelineWindow.startMs) {
			return zoomRegions;
		}

		const dominantAtStart = findDominantRegion(zoomRegions, displayedTimelineWindow.startMs, {
			connectZooms,
		}).region;
		if (!dominantAtStart) {
			return zoomRegions;
		}

		const endWindowStartMs = Math.max(
			displayedTimelineWindow.startMs,
			displayedTimelineWindow.endMs - LOOP_CURSOR_END_WINDOW_MS,
		);
		const loopEndRegion: ZoomRegion = {
			id: `${dominantAtStart.id}__loop-end-sync`,
			startMs: endWindowStartMs,
			endMs: displayedTimelineWindow.endMs,
			depth: dominantAtStart.depth,
			focus: {
				cx: dominantAtStart.focus.cx,
				cy: dominantAtStart.focus.cy,
			},
		};

		return [...zoomRegions.filter((region) => region.id !== loopEndRegion.id), loopEndRegion];
	}, [loopCursor, zoomRegions, displayedTimelineWindow, connectZooms]);

	useEffect(() => {
		if (
			!videoPath ||
			duration <= 0 ||
			zoomRegions.length > 0 ||
			normalizedCursorTelemetry.length < 2
		) {
			return;
		}

		if (autoSuggestedVideoPathRef.current === videoPath) {
			return;
		}

		const totalMs = Math.max(0, Math.round(duration * 1000));
		if (totalMs <= 0) {
			return;
		}

		const candidates = detectInteractionCandidates(normalizedCursorTelemetry);
		if (candidates.length === 0) {
			autoSuggestedVideoPathRef.current = videoPath;
			return;
		}

		const DEFAULT_DURATION_MS = 1100;
		const MIN_SPACING_MS = 1800;
		const sortedCandidates = [...candidates].sort((a, b) => b.strength - a.strength);
		const acceptedCenters: number[] = [];

		setZoomRegions((prev) => {
			if (prev.length > 0) {
				return prev;
			}

			const reservedSpans: Array<{ start: number; end: number }> = [];
			const additions: ZoomRegion[] = [];
			let nextId = nextZoomIdRef.current;

			sortedCandidates.forEach((candidate) => {
				const tooCloseToAccepted = acceptedCenters.some(
					(center) => Math.abs(center - candidate.centerTimeMs) < MIN_SPACING_MS,
				);
				if (tooCloseToAccepted) {
					return;
				}

				const centeredStart = Math.round(candidate.centerTimeMs - DEFAULT_DURATION_MS / 2);
				const startMs = Math.max(0, Math.min(centeredStart, totalMs - DEFAULT_DURATION_MS));
				const endMs = Math.min(totalMs, startMs + DEFAULT_DURATION_MS);

				const hasOverlap = reservedSpans.some((span) => endMs > span.start && startMs < span.end);
				if (hasOverlap) {
					return;
				}

				additions.push({
					id: `zoom-${nextId++}`,
					startMs,
					endMs,
					depth: DEFAULT_ZOOM_DEPTH,
					focus: clampFocusToDepth(candidate.focus, DEFAULT_ZOOM_DEPTH),
				});
				reservedSpans.push({ start: startMs, end: endMs });
				acceptedCenters.push(candidate.centerTimeMs);
			});

			if (additions.length === 0) {
				return prev;
			}

			nextZoomIdRef.current = nextId;
			return [...prev, ...additions];
		});

		autoSuggestedVideoPathRef.current = videoPath;
	}, [videoPath, duration, normalizedCursorTelemetry, zoomRegions.length]);

	// Initialize default wallpaper with resolved asset path
	useEffect(() => {
		let mounted = true;
		(async () => {
			try {
				const resolvedPath = await getAssetPath(DEFAULT_WALLPAPER_RELATIVE_PATH);
				if (mounted) {
					setWallpaper(resolvedPath);
				}
			} catch (err) {
				// If resolution fails, keep the fallback
				console.warn("Failed to resolve default wallpaper path:", err);
			}
		})();
		return () => {
			mounted = false;
		};
	}, []);

	const togglePlayPause = useCallback(() => {
		const playback = videoPlaybackRef.current;
		const video = playback?.video;
		if (!playback || !video) return;

		if (isPlaying) {
			playback.pause();
		} else {
			playback.play().catch((err) => console.error("Video play failed:", err));
		}
	}, [isPlaying]);

	const handleSeek = useCallback((time: number) => {
		const video = videoPlaybackRef.current?.video;
		if (!video) return;
		video.currentTime = time;
	}, []);

	// Derived values for SettingsPanel — memoized to keep props stable
	const selectedZoomDepth = useMemo(() => {
		if (!selectedZoomId) return null;
		return zoomRegions.find((z) => z.id === selectedZoomId)?.depth ?? null;
	}, [selectedZoomId, zoomRegions]);

	const selectedSpeedValue = useMemo(() => {
		if (!selectedSpeedId) return null;
		return speedRegions.find((r) => r.id === selectedSpeedId)?.speed ?? null;
	}, [selectedSpeedId, speedRegions]);

	const gifOutputDimensions = useMemo(() => {
		const videoWidth = videoPlaybackRef.current?.video?.videoWidth || 1920;
		const videoHeight = videoPlaybackRef.current?.video?.videoHeight || 1080;
		return calculateOutputDimensions(videoWidth, videoHeight, gifSizePreset, GIF_SIZE_PRESETS);
	}, [gifSizePreset]);

	const handleSelectZoom = useCallback((id: string | null) => {
		setSelectedZoomId(id);
		if (id) setSelectedTrimId(null);
	}, []);

	const handleSelectTrim = useCallback((id: string | null) => {
		setSelectedTrimId(id);
		if (id) {
			setSelectedZoomId(null);
			setSelectedAnnotationId(null);
		}
	}, []);

	const handleSelectAnnotation = useCallback((id: string | null) => {
		setSelectedAnnotationId(id);
		if (id) {
			setSelectedZoomId(null);
			setSelectedTrimId(null);
		}
	}, []);

	const handleZoomAdded = useCallback((span: Span) => {
		const id = `zoom-${nextZoomIdRef.current++}`;
		const newRegion: ZoomRegion = {
			id,
			startMs: Math.round(span.start),
			endMs: Math.round(span.end),
			depth: DEFAULT_ZOOM_DEPTH,
			focus: { cx: 0.5, cy: 0.5 },
		};
		setZoomRegions((prev) => [...prev, newRegion]);
		setSelectedZoomId(id);
		setSelectedTrimId(null);
		setSelectedAnnotationId(null);
	}, []);

	const handleZoomSuggested = useCallback((span: Span, focus: ZoomFocus) => {
		const id = `zoom-${nextZoomIdRef.current++}`;
		const newRegion: ZoomRegion = {
			id,
			startMs: Math.round(span.start),
			endMs: Math.round(span.end),
			depth: DEFAULT_ZOOM_DEPTH,
			focus: clampFocusToDepth(focus, DEFAULT_ZOOM_DEPTH),
		};
		setZoomRegions((prev) => [...prev, newRegion]);
		setSelectedZoomId(id);
		setSelectedTrimId(null);
		setSelectedAnnotationId(null);
	}, []);

	const handleTrimAdded = useCallback((span: Span) => {
		const id = `trim-${nextTrimIdRef.current++}`;
		const newRegion: TrimRegion = {
			id,
			startMs: Math.round(span.start),
			endMs: Math.round(span.end),
		};
		setTrimRegions((prev) => [...prev, newRegion]);
		setSelectedTrimId(id);
		setSelectedZoomId(null);
		setSelectedAnnotationId(null);
	}, []);

	const handleZoomSpanChange = useCallback((id: string, span: Span) => {
		setZoomRegions((prev) =>
			prev.map((region) =>
				region.id === id
					? {
							...region,
							startMs: Math.round(span.start),
							endMs: Math.round(span.end),
						}
					: region,
			),
		);
	}, []);

	const handleTrimSpanChange = useCallback((id: string, span: Span) => {
		setTrimRegions((prev) =>
			prev.map((region) =>
				region.id === id
					? {
							...region,
							startMs: Math.round(span.start),
							endMs: Math.round(span.end),
						}
					: region,
			),
		);
	}, []);

	const handleZoomFocusChange = useCallback((id: string, focus: ZoomFocus) => {
		setZoomRegions((prev) =>
			prev.map((region) =>
				region.id === id
					? {
							...region,
							focus: clampFocusToDepth(focus, region.depth),
						}
					: region,
			),
		);
	}, []);

	const handleZoomDepthChange = useCallback(
		(depth: ZoomDepth) => {
			if (!selectedZoomId) return;
			setZoomRegions((prev) =>
				prev.map((region) =>
					region.id === selectedZoomId
						? {
								...region,
								depth,
								focus: clampFocusToDepth(region.focus, depth),
							}
						: region,
				),
			);
		},
		[selectedZoomId],
	);

	const handleZoomDelete = useCallback(
		(id: string) => {
			setZoomRegions((prev) => prev.filter((region) => region.id !== id));
			if (selectedZoomId === id) {
				setSelectedZoomId(null);
			}
		},
		[selectedZoomId],
	);

	const handleTrimDelete = useCallback(
		(id: string) => {
			setTrimRegions((prev) => prev.filter((region) => region.id !== id));
			if (selectedTrimId === id) {
				setSelectedTrimId(null);
			}
		},
		[selectedTrimId],
	);

	const handleSelectSpeed = useCallback((id: string | null) => {
		setSelectedSpeedId(id);
		if (id) {
			setSelectedZoomId(null);
			setSelectedTrimId(null);
			setSelectedAnnotationId(null);
		}
	}, []);

	const handleSpeedAdded = useCallback((span: Span) => {
		const id = `speed-${nextSpeedIdRef.current++}`;
		const newRegion: SpeedRegion = {
			id,
			startMs: Math.round(span.start),
			endMs: Math.round(span.end),
			speed: DEFAULT_PLAYBACK_SPEED,
		};
		setSpeedRegions((prev) => [...prev, newRegion]);
		setSelectedSpeedId(id);
		setSelectedZoomId(null);
		setSelectedTrimId(null);
		setSelectedAnnotationId(null);
	}, []);

	const handleSpeedSpanChange = useCallback((id: string, span: Span) => {
		setSpeedRegions((prev) =>
			prev.map((region) =>
				region.id === id
					? {
							...region,
							startMs: Math.round(span.start),
							endMs: Math.round(span.end),
						}
					: region,
			),
		);
	}, []);

	const handleSpeedDelete = useCallback(
		(id: string) => {
			setSpeedRegions((prev) => prev.filter((region) => region.id !== id));
			if (selectedSpeedId === id) {
				setSelectedSpeedId(null);
			}
		},
		[selectedSpeedId],
	);

	const handleSpeedChange = useCallback(
		(speed: PlaybackSpeed) => {
			if (!selectedSpeedId) return;
			setSpeedRegions((prev) =>
				prev.map((region) => (region.id === selectedSpeedId ? { ...region, speed } : region)),
			);
		},
		[selectedSpeedId],
	);

	const handleAnnotationAdded = useCallback((span: Span) => {
		const id = `annotation-${nextAnnotationIdRef.current++}`;
		const zIndex = nextAnnotationZIndexRef.current++; // Assign z-index based on creation order
		const newRegion: AnnotationRegion = {
			id,
			startMs: Math.round(span.start),
			endMs: Math.round(span.end),
			type: "text",
			content: "Enter text...",
			position: { ...DEFAULT_ANNOTATION_POSITION },
			size: { ...DEFAULT_ANNOTATION_SIZE },
			style: { ...DEFAULT_ANNOTATION_STYLE },
			zIndex,
		};
		setAnnotationRegions((prev) => [...prev, newRegion]);
		setSelectedAnnotationId(id);
		setSelectedZoomId(null);
		setSelectedTrimId(null);
	}, []);

	const handleAnnotationSpanChange = useCallback((id: string, span: Span) => {
		setAnnotationRegions((prev) =>
			prev.map((region) =>
				region.id === id
					? {
							...region,
							startMs: Math.round(span.start),
							endMs: Math.round(span.end),
						}
					: region,
			),
		);
	}, []);

	const handleAnnotationDelete = useCallback(
		(id: string) => {
			setAnnotationRegions((prev) => prev.filter((region) => region.id !== id));
			if (selectedAnnotationId === id) {
				setSelectedAnnotationId(null);
			}
		},
		[selectedAnnotationId],
	);

	const handleAnnotationContentChange = useCallback((id: string, content: string) => {
		setAnnotationRegions((prev) => {
			const updated = prev.map((region) => {
				if (region.id !== id) return region;

				// Store content in type-specific fields
				if (region.type === "text") {
					return { ...region, content, textContent: content };
				} else if (region.type === "image") {
					return { ...region, content, imageContent: content };
				} else {
					return { ...region, content };
				}
			});
			return updated;
		});
	}, []);

	const handleAnnotationTypeChange = useCallback((id: string, type: AnnotationRegion["type"]) => {
		setAnnotationRegions((prev) => {
			const updated = prev.map((region) => {
				if (region.id !== id) return region;

				const updatedRegion = { ...region, type };

				// Restore content from type-specific storage
				if (type === "text") {
					updatedRegion.content = region.textContent || "Enter text...";
				} else if (type === "image") {
					updatedRegion.content = region.imageContent || "";
				} else if (type === "figure") {
					updatedRegion.content = "";
					if (!region.figureData) {
						updatedRegion.figureData = { ...DEFAULT_FIGURE_DATA };
					}
				}

				return updatedRegion;
			});
			return updated;
		});
	}, []);

	const handleAnnotationStyleChange = useCallback(
		(id: string, style: Partial<AnnotationRegion["style"]>) => {
			setAnnotationRegions((prev) =>
				prev.map((region) =>
					region.id === id ? { ...region, style: { ...region.style, ...style } } : region,
				),
			);
		},
		[],
	);

	const handleAnnotationFigureDataChange = useCallback((id: string, figureData: FigureData) => {
		setAnnotationRegions((prev) =>
			prev.map((region) => (region.id === id ? { ...region, figureData } : region)),
		);
	}, []);

	const handleAnnotationPositionChange = useCallback(
		(id: string, position: { x: number; y: number }) => {
			setAnnotationRegions((prev) =>
				prev.map((region) => (region.id === id ? { ...region, position } : region)),
			);
		},
		[],
	);

	const handleAnnotationSizeChange = useCallback(
		(id: string, size: { width: number; height: number }) => {
			setAnnotationRegions((prev) =>
				prev.map((region) => (region.id === id ? { ...region, size } : region)),
			);
		},
		[],
	);

	// Global Tab prevention
	useEffect(() => {
		const handleKeyDown = (e: KeyboardEvent) => {
			const target = e.target as HTMLElement | null;
			const isEditableTarget =
				target instanceof HTMLInputElement ||
				target instanceof HTMLTextAreaElement ||
				target?.isContentEditable;

			const usesPrimaryModifier = isMac ? e.metaKey : e.ctrlKey;
			const key = e.key.toLowerCase();

			if (usesPrimaryModifier && !e.altKey && key === "z") {
				if (!isEditableTarget) {
					e.preventDefault();
					if (e.shiftKey) {
						handleRedo();
					} else {
						handleUndo();
					}
				}
				return;
			}

			if (!isMac && e.ctrlKey && !e.metaKey && !e.altKey && key === "y") {
				if (!isEditableTarget) {
					e.preventDefault();
					handleRedo();
				}
				return;
			}

			// Save project: Cmd+S (Mac) / Ctrl+S (Windows/Linux)
			if (usesPrimaryModifier && !e.altKey && !e.shiftKey && key === "s") {
				e.preventDefault();
				handleSaveProject();
				return;
			}

			if (e.key === "Tab") {
				// Allow tab only in inputs/textareas
				if (isEditableTarget) {
					return;
				}
				e.preventDefault();
			}

			if (matchesShortcut(e, shortcuts.playPause, isMac)) {
				// Allow space only in inputs/textareas
				if (isEditableTarget) {
					return;
				}
				e.preventDefault();

				const playback = videoPlaybackRef.current;
				if (playback?.video) {
					if (playback.video.paused) {
						playback.play().catch(console.error);
					} else {
						playback.pause();
					}
				}
			}
		};

		window.addEventListener("keydown", handleKeyDown, { capture: true });
		return () => window.removeEventListener("keydown", handleKeyDown, { capture: true });
	}, [shortcuts, isMac, handleUndo, handleRedo, handleSaveProject]);

	useEffect(() => {
		if (selectedZoomId && !zoomRegions.some((region) => region.id === selectedZoomId)) {
			setSelectedZoomId(null);
		}
	}, [selectedZoomId, zoomRegions]);

	useEffect(() => {
		if (selectedTrimId && !trimRegions.some((region) => region.id === selectedTrimId)) {
			setSelectedTrimId(null);
		}
	}, [selectedTrimId, trimRegions]);

	useEffect(() => {
		if (
			selectedAnnotationId &&
			!annotationRegions.some((region) => region.id === selectedAnnotationId)
		) {
			setSelectedAnnotationId(null);
		}
	}, [selectedAnnotationId, annotationRegions]);

	useEffect(() => {
		if (selectedSpeedId && !speedRegions.some((region) => region.id === selectedSpeedId)) {
			setSelectedSpeedId(null);
		}
	}, [selectedSpeedId, speedRegions]);

	const showExportSuccessToast = useCallback((filePath: string) => {
		toast.success(`Exported successfully to ${filePath}`, {
			action: {
				label: "Show in Folder",
				onClick: async () => {
					try {
						await backend.revealInFolder(filePath);
					} catch (err) {
						toast.error(`Error revealing in folder: ${String(err)}`);
					}
				},
			},
		});
	}, []);

	const restorePreviewAfterExport = useCallback(
		async (restoreTime: number, resumePlayback: boolean) => {
			const playback = videoPlaybackRef.current;
			const video = playback?.video;

			if (!playback || !video || !videoPath) {
				return;
			}

			const waitForVideoData = async (reloadSource?: () => void) => {
				if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
					return;
				}

				await new Promise<void>((resolve, reject) => {
					const cleanup = () => {
						video.removeEventListener("loadeddata", handleLoadedData);
						video.removeEventListener("error", handleError);
					};

					const handleLoadedData = () => {
						cleanup();
						resolve();
					};

					const handleError = () => {
						cleanup();
						reject(new Error("Failed to reload preview video"));
					};

					video.addEventListener("loadeddata", handleLoadedData, { once: true });
					video.addEventListener("error", handleError, { once: true });
					reloadSource?.();

					if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
						cleanup();
						resolve();
					}
				});
			};

			const seekToTime = async (targetTime: number) => {
				const duration = Number.isFinite(video.duration) ? video.duration : 0;
				const maxSeekTime = duration > 0 ? Math.max(duration - 0.001, 0) : targetTime;
				const clampedTime = Math.max(0, Math.min(targetTime, maxSeekTime));

				if (Math.abs(video.currentTime - clampedTime) <= 0.001) {
					return;
				}

				await new Promise<void>((resolve, reject) => {
					const cleanup = () => {
						video.removeEventListener("seeked", handleSeeked);
						video.removeEventListener("error", handleError);
					};

					const handleSeeked = () => {
						cleanup();
						resolve();
					};

					const handleError = () => {
						cleanup();
						reject(new Error("Failed to seek preview video after export"));
					};

					video.addEventListener("seeked", handleSeeked, { once: true });
					video.addEventListener("error", handleError, { once: true });
					video.currentTime = clampedTime;
				});
			};

			playback.pause();

			const shouldReloadSource =
				video.getAttribute("src") !== videoPath ||
				video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA;

			if (shouldReloadSource) {
				video.src = videoPath;
				await waitForVideoData(() => {
					video.load();
				});
			}

			await seekToTime(restoreTime);

			if (resumePlayback) {
				try {
					await playback.play();
					return;
				} catch (error) {
					console.error("Failed to resume preview playback after export:", error);
				}
			}

			await playback.refreshFrame().catch(() => undefined);
		},
		[videoPath],
	);

	const handleExport = useCallback(
		async (settings: ExportSettings) => {
			if (!videoPath) {
				toast.error("No video loaded");
				return;
			}

			const sourcePath = videoSourcePath;
			if (!sourcePath) {
				toast.error("Unable to determine source video path");
				return;
			}

			const video = videoPlaybackRef.current?.video;
			if (!video) {
				toast.error("Video not ready");
				return;
			}

			setIsExporting(true);
			setExportProgress(null);
			setExportError(null);
			pendingExportSaveRef.current = null;
			setHasPendingExportSave(false);

			let keepExportDialogOpen = false;
			const wasPlaying = isPlaying;
			const restoreTime = video.currentTime;

			try {
				if (wasPlaying) {
					videoPlaybackRef.current?.pause();
				}

				const sourceWidth = video.videoWidth || 1920;
				const sourceHeight = video.videoHeight || 1080;
				const sourceAspectRatio = sourceHeight > 0 ? sourceWidth / sourceHeight : 16 / 9;
				const aspectRatioValue = getAspectRatioValue(aspectRatio, sourceAspectRatio);

				// Get preview CONTAINER dimensions for scaling
				const playbackRef = videoPlaybackRef.current;
				const containerElement = playbackRef?.containerRef?.current;
				const previewWidth = containerElement?.clientWidth || 1920;
				const previewHeight = containerElement?.clientHeight || 1080;
				const sourceVideoUrl = toFileUrl(sourcePath);
				const facecamSourceUrl = facecamVideoPath ? toFileUrl(facecamVideoPath) : undefined;

				if (settings.format === "gif" && settings.gifConfig) {
					// GIF Export
					const gifExporter = new GifExporter({
						videoUrl: sourceVideoUrl,
						facecamVideoUrl: facecamSourceUrl,
						facecamOffsetMs,
						width: settings.gifConfig.width,
						height: settings.gifConfig.height,
						frameRate: settings.gifConfig.frameRate,
						loop: settings.gifConfig.loop,
						sizePreset: settings.gifConfig.sizePreset,
						wallpaper,
						trimRegions,
						speedRegions,
						showShadow: shadowIntensity > 0,
						shadowIntensity,
						backgroundBlur,
						zoomMotionBlur,
						connectZooms,
						borderRadius,
						padding,
						videoPadding: padding,
						cropRegion,
						facecamSettings,
						annotationRegions,
						zoomRegions: effectiveZoomRegions,
						cursorTelemetry: effectiveCursorTelemetry,
						showCursor,
						cursorSize,
						cursorSmoothing,
						cursorMotionBlur,
						cursorClickBounce,
						previewWidth,
						previewHeight,
						onProgress: (progress: ExportProgress) => {
							setExportProgress(progress);
						},
					});

					exporterRef.current = gifExporter as unknown as VideoExporter;
					const result = await gifExporter.export();

					if (result.success && result.blob) {
						const arrayBuffer = await result.blob.arrayBuffer();
						const fileName = getSuggestedExportFileName("recording", "gif");

						const savePath = await backend.saveExportedVideo(new Uint8Array(arrayBuffer), fileName);

						if (!savePath) {
							pendingExportSaveRef.current = { arrayBuffer, fileName };
							setHasPendingExportSave(true);
							setExportError(
								"Save dialog canceled. Click Save Again to save without re-rendering.",
							);
							toast.info("Save canceled. You can save again without re-exporting.");
							keepExportDialogOpen = true;
						} else {
							showExportSuccessToast(savePath);
							setExportedFilePath(savePath);
						}
					} else {
						setExportError(result.error || "GIF export failed");
						toast.error(result.error || "GIF export failed");
					}
				} else {
					// MP4 Export
					const quality = settings.quality || exportQuality;
					let exportWidth: number;
					let exportHeight: number;
					let bitrate: number;

					if (quality === "source") {
						// Use source resolution
						exportWidth = sourceWidth;
						exportHeight = sourceHeight;

						if (aspectRatio === "native") {
							exportWidth = Math.floor(sourceWidth / 2) * 2;
							exportHeight = Math.floor(sourceHeight / 2) * 2;
						} else if (aspectRatioValue === 1) {
							// Square (1:1): use smaller dimension to avoid codec limits
							const baseDimension = Math.floor(Math.min(sourceWidth, sourceHeight) / 2) * 2;
							exportWidth = baseDimension;
							exportHeight = baseDimension;
						} else if (aspectRatioValue > 1) {
							// Landscape: find largest even dimensions that exactly match aspect ratio
							const baseWidth = Math.floor(sourceWidth / 2) * 2;
							let found = false;
							for (let w = baseWidth; w >= 100 && !found; w -= 2) {
								const h = Math.round(w / aspectRatioValue);
								if (h % 2 === 0 && Math.abs(w / h - aspectRatioValue) < 0.0001) {
									exportWidth = w;
									exportHeight = h;
									found = true;
								}
							}
							if (!found) {
								exportWidth = baseWidth;
								exportHeight = Math.floor(baseWidth / aspectRatioValue / 2) * 2;
							}
						} else {
							// Portrait: find largest even dimensions that exactly match aspect ratio
							const baseHeight = Math.floor(sourceHeight / 2) * 2;
							let found = false;
							for (let h = baseHeight; h >= 100 && !found; h -= 2) {
								const w = Math.round(h * aspectRatioValue);
								if (w % 2 === 0 && Math.abs(w / h - aspectRatioValue) < 0.0001) {
									exportWidth = w;
									exportHeight = h;
									found = true;
								}
							}
							if (!found) {
								exportHeight = baseHeight;
								exportWidth = Math.floor((baseHeight * aspectRatioValue) / 2) * 2;
							}
						}

						// Calculate visually lossless bitrate matching screen recording optimization
						const totalPixels = exportWidth * exportHeight;
						bitrate = 30_000_000;
						if (totalPixels > 1920 * 1080 && totalPixels <= 2560 * 1440) {
							bitrate = 50_000_000;
						} else if (totalPixels > 2560 * 1440) {
							bitrate = 80_000_000;
						}
					} else {
						// Use quality-based target resolution
						const targetHeight = quality === "medium" ? 720 : 1080;

						// Calculate dimensions maintaining aspect ratio
						exportHeight = Math.floor(targetHeight / 2) * 2;
						exportWidth = Math.floor((exportHeight * aspectRatioValue) / 2) * 2;

						// Adjust bitrate for lower resolutions
						const totalPixels = exportWidth * exportHeight;
						if (totalPixels <= 1280 * 720) {
							bitrate = 10_000_000;
						} else if (totalPixels <= 1920 * 1080) {
							bitrate = 20_000_000;
						} else {
							bitrate = 30_000_000;
						}
					}

					const exporter = new VideoExporter({
						videoUrl: sourceVideoUrl,
						width: exportWidth,
						height: exportHeight,
						frameRate: 60,
						bitrate,
						codec: "avc1.640033",
						wallpaper,
						facecamVideoUrl: facecamSourceUrl,
						facecamOffsetMs,
						trimRegions,
						speedRegions,
						showShadow: shadowIntensity > 0,
						shadowIntensity,
						backgroundBlur,
						zoomMotionBlur,
						connectZooms,
						borderRadius,
						padding,
						cropRegion,
						facecamSettings,
						annotationRegions,
						zoomRegions: effectiveZoomRegions,
						cursorTelemetry: effectiveCursorTelemetry,
						showCursor,
						cursorSize,
						cursorSmoothing,
						cursorMotionBlur,
						cursorClickBounce,
						previewWidth,
						previewHeight,
						onProgress: (progress: ExportProgress) => {
							setExportProgress(progress);
						},
					});

					exporterRef.current = exporter;
					const result = await exporter.export();

					if (result.success && result.blob) {
						const arrayBuffer = await result.blob.arrayBuffer();
						const fileName = getSuggestedExportFileName("recording", "mp4");

						const savePath = await backend.saveExportedVideo(new Uint8Array(arrayBuffer), fileName);

						if (!savePath) {
							pendingExportSaveRef.current = { arrayBuffer, fileName };
							setHasPendingExportSave(true);
							setExportError(
								"Save dialog canceled. Click Save Again to save without re-rendering.",
							);
							toast.info("Save canceled. You can save again without re-exporting.");
							keepExportDialogOpen = true;
						} else {
							showExportSuccessToast(savePath);
							setExportedFilePath(savePath);
						}
					} else {
						setExportError(result.error || "Export failed");
						toast.error(result.error || "Export failed");
					}
				}
			} catch (error) {
				console.error("Export error:", error);
				const errorMessage = error instanceof Error ? error.message : "Unknown error";
				setExportError(errorMessage);
				toast.error(`Export failed: ${errorMessage}`);
			} finally {
				try {
					await restorePreviewAfterExport(restoreTime, wasPlaying);
				} catch (error) {
					console.error("Failed to restore preview after export:", error);
				}
				setIsExporting(false);
				exporterRef.current = null;
				setShowExportDialog(keepExportDialogOpen);
				setExportProgress(null);
			}
		},
		[
			videoPath,
			videoSourcePath,
			facecamVideoPath,
			facecamOffsetMs,
			wallpaper,
			trimRegions,
			speedRegions,
			shadowIntensity,
			backgroundBlur,
			zoomMotionBlur,
			connectZooms,
			showCursor,
			effectiveCursorTelemetry,
			effectiveZoomRegions,
			cursorSize,
			cursorSmoothing,
			cursorMotionBlur,
			cursorClickBounce,
			borderRadius,
			padding,
			cropRegion,
			facecamSettings,
			annotationRegions,
			isPlaying,
			aspectRatio,
			exportQuality,
			showExportSuccessToast,
			restorePreviewAfterExport,
		],
	);

	const handleOpenExportDialog = useCallback(() => {
		if (!videoPath) {
			toast.error("No video loaded");
			return;
		}

		if (hasPendingExportSave) {
			setShowExportDialog(true);
			setExportError("Save dialog canceled. Click Save Again to save without re-rendering.");
			return;
		}

		const video = videoPlaybackRef.current?.video;
		if (!video) {
			toast.error("Video not ready");
			return;
		}

		// Build export settings from current state
		const sourceWidth = video.videoWidth || 1920;
		const sourceHeight = video.videoHeight || 1080;
		const gifDimensions = calculateOutputDimensions(
			sourceWidth,
			sourceHeight,
			gifSizePreset,
			GIF_SIZE_PRESETS,
		);

		const settings: ExportSettings = {
			format: exportFormat,
			quality: exportFormat === "mp4" ? exportQuality : undefined,
			gifConfig:
				exportFormat === "gif"
					? {
							frameRate: gifFrameRate,
							loop: gifLoop,
							sizePreset: gifSizePreset,
							width: gifDimensions.width,
							height: gifDimensions.height,
						}
					: undefined,
		};

		setShowExportDialog(true);
		setExportError(null);

		// Start export immediately
		handleExport(settings);
	}, [
		videoPath,
		hasPendingExportSave,
		exportFormat,
		exportQuality,
		gifFrameRate,
		gifLoop,
		gifSizePreset,
		handleExport,
	]);

	const handleCancelExport = useCallback(() => {
		if (exporterRef.current) {
			exporterRef.current.cancel();
			toast.info("Export canceled");
			setShowExportDialog(false);
			setIsExporting(false);
			setExportProgress(null);
			setExportError(null);
			setExportedFilePath(undefined);
		}
	}, []);

	const handleExportDialogClose = useCallback(() => {
		setShowExportDialog(false);
		setExportedFilePath(undefined);
	}, []);

	const handleRetrySaveExport = useCallback(async () => {
		const pendingSave = pendingExportSaveRef.current;
		if (!pendingSave) {
			return;
		}

		const savePath = await backend.saveExportedVideo(
			new Uint8Array(pendingSave.arrayBuffer),
			pendingSave.fileName,
		);

		if (!savePath) {
			setExportError("Save dialog canceled. Click Save Again to save without re-rendering.");
			toast.info("Save canceled. You can try again.");
			return;
		}

		pendingExportSaveRef.current = null;
		setHasPendingExportSave(false);
		setExportError(null);
		setExportedFilePath(savePath);
		showExportSuccessToast(savePath);
		setShowExportDialog(false);
	}, [showExportSuccessToast]);

	const openRecordingsFolder = useCallback(async () => {
		try {
			await backend.openRecordingsFolder();
		} catch (error) {
			toast.error(`Failed to open recordings folder: ${String(error)}`);
		}
	}, []);

	if (loading) {
		return (
			<div className="flex h-screen items-center justify-center bg-[#09090b] px-6 text-slate-200">
				<Empty className="border-white/10 bg-white/[0.02]">
					<EmptyHeader>
						<EmptyMedia className="size-16 border-[#2563EB]/20 bg-[#2563EB]/10 text-[#93c5fd]">
							<LoaderCircle className="size-7 animate-spin" />
						</EmptyMedia>
						<EmptyTitle>Loading video</EmptyTitle>
						<EmptyDescription>
							Preparing your recording and loading it into memory for editing.
						</EmptyDescription>
					</EmptyHeader>
				</Empty>
			</div>
		);
	}
	if (error) {
		return (
			<div className="flex items-center justify-center h-screen bg-background">
				<div className="flex flex-col items-center gap-3">
					<div className="text-destructive">{error}</div>
					<button
						type="button"
						onClick={handleLoadProject}
						className="px-3 py-1.5 rounded-md bg-[#2563EB] text-white text-sm hover:bg-[#2563EB]/90"
					>
						Load Project File
					</button>
				</div>
			</div>
		);
	}

	const showPlaybackLoadingOverlay = Boolean(videoPath) && !playbackReady && !error;

	return (
		<div className="flex flex-col h-screen bg-[#09090b] text-slate-200 overflow-hidden selection:bg-[#2563EB]/30">
			{showPlaybackLoadingOverlay && (
				<div className="fixed inset-0 z-[120] flex items-center justify-center bg-[#09090b]/92 px-6 backdrop-blur-sm">
					<Empty className="border-white/10 bg-white/[0.02]">
						<EmptyHeader>
							<EmptyMedia className="size-16 border-[#2563EB]/20 bg-[#2563EB]/10 text-[#93c5fd]">
								<LoaderCircle className="size-7 animate-spin" />
							</EmptyMedia>
							<EmptyTitle>Loading video</EmptyTitle>
							<EmptyDescription>
								Preparing your recording and loading it into memory for editing.
							</EmptyDescription>
						</EmptyHeader>
					</Empty>
				</div>
			)}
			<div
				className="relative h-10 flex-shrink-0 bg-[#09090b]/80 backdrop-blur-md border-b border-white/5 flex items-center justify-center px-6 z-50"
				style={{ WebkitAppRegion: "drag" } as React.CSSProperties}
			>
				<span className="text-sm font-semibold tracking-tight text-white/90">Open Recorder</span>
				<div
					className="absolute right-4 flex items-center gap-2"
					style={{ WebkitAppRegion: "no-drag" } as React.CSSProperties}
				>
					<button
						type="button"
						onClick={() => setShowShortcutsDialog(true)}
						className="inline-flex h-7 w-7 items-center justify-center rounded-md text-white/60 transition hover:bg-white/8 hover:text-white cursor-pointer"
						title="Keyboard shortcuts"
						aria-label="Keyboard shortcuts"
					>
						<HelpCircle className="h-4 w-4" />
					</button>
					<button
						type="button"
						onClick={() => void openRecordingsFolder()}
						className="inline-flex h-7 items-center gap-1.5 rounded-md px-2 text-white/90 transition hover:bg-white/8 hover:text-white cursor-pointer"
						title="Open recordings folder"
						aria-label="Open recordings folder"
					>
						<FolderOpen className="h-4 w-4" />
						<span className="text-xs font-normal">Manage recordings</span>
					</button>

					<Popover>
						<div className="flex">
							<Button
								type="button"
								size="sm"
								onClick={handleOpenExportDialog}
								className="h-7 rounded-r-none gap-1.5 bg-[#2563EB] text-white text-xs font-medium hover:bg-[#2563EB]/90 active:scale-[0.98] transition-all"
							>
								<Download className="w-3.5 h-3.5" />
								Export {exportFormat === "gif" ? "GIF" : "Video"}
							</Button>
							<PopoverTrigger asChild>
								<Button
									type="button"
									size="sm"
									className="h-7 w-7 p-0 rounded-l-none border-l border-[#2563EB]/50 bg-[#2563EB] text-white hover:bg-[#2563EB]/90 active:scale-[0.98] transition-all"
								>
									<ChevronDown className="w-3.5 h-3.5" />
								</Button>
							</PopoverTrigger>
						</div>
						<PopoverContent
							side="bottom"
							align="end"
							sideOffset={8}
							className="w-[280px] bg-[#09090b] border-white/10 p-3 rounded-xl"
						>
							<div className="space-y-3">
								<div className="flex items-center gap-2">
									<button
										onClick={() => setExportFormat("mp4")}
										className={cn(
											"flex-1 flex items-center justify-center gap-1.5 py-2 rounded-lg border transition-all text-xs font-medium",
											exportFormat === "mp4"
												? "bg-[#2563EB]/10 border-[#2563EB]/50 text-white"
												: "bg-white/5 border-white/10 text-slate-400 hover:bg-white/10 hover:text-slate-200",
										)}
									>
										<Film className="w-3.5 h-3.5" />
										MP4
									</button>
									<button
										onClick={() => setExportFormat("gif")}
										className={cn(
											"flex-1 flex items-center justify-center gap-1.5 py-2 rounded-lg border transition-all text-xs font-medium",
											exportFormat === "gif"
												? "bg-[#2563EB]/10 border-[#2563EB]/50 text-white"
												: "bg-white/5 border-white/10 text-slate-400 hover:bg-white/10 hover:text-slate-200",
										)}
									>
										<Image className="w-3.5 h-3.5" />
										GIF
									</button>
								</div>

								{exportFormat === "mp4" && (
									<div className="bg-white/5 border border-white/5 p-0.5 w-full grid grid-cols-3 h-7 rounded-lg">
										<button
											onClick={() => setExportQuality("medium")}
											className={cn(
												"rounded-md transition-all text-[10px] font-medium",
												exportQuality === "medium"
													? "bg-white text-black"
													: "text-slate-400 hover:text-slate-200",
											)}
										>
											Low
										</button>
										<button
											onClick={() => setExportQuality("good")}
											className={cn(
												"rounded-md transition-all text-[10px] font-medium",
												exportQuality === "good"
													? "bg-white text-black"
													: "text-slate-400 hover:text-slate-200",
											)}
										>
											Medium
										</button>
										<button
											onClick={() => setExportQuality("source")}
											className={cn(
												"rounded-md transition-all text-[10px] font-medium",
												exportQuality === "source"
													? "bg-white text-black"
													: "text-slate-400 hover:text-slate-200",
											)}
										>
											High
										</button>
									</div>
								)}

								{exportFormat === "gif" && (
									<div className="space-y-2">
										<div className="flex items-center gap-2">
											<div className="flex-1 bg-white/5 border border-white/5 p-0.5 grid grid-cols-4 h-7 rounded-lg">
												{GIF_FRAME_RATES.map((rate) => (
													<button
														key={rate.value}
														onClick={() => setGifFrameRate(rate.value)}
														className={cn(
															"rounded-md transition-all text-[10px] font-medium",
															gifFrameRate === rate.value
																? "bg-white text-black"
																: "text-slate-400 hover:text-slate-200",
														)}
													>
														{rate.value}
													</button>
												))}
											</div>
											<div className="flex-1 bg-white/5 border border-white/5 p-0.5 grid grid-cols-3 h-7 rounded-lg">
												{Object.entries(GIF_SIZE_PRESETS).map(([key, _preset]) => (
													<button
														key={key}
														onClick={() => setGifSizePreset(key as GifSizePreset)}
														className={cn(
															"rounded-md transition-all text-[10px] font-medium",
															gifSizePreset === key
																? "bg-white text-black"
																: "text-slate-400 hover:text-slate-200",
														)}
													>
														{key === "original"
															? "Orig"
															: key.charAt(0).toUpperCase() + key.slice(1, 3)}
													</button>
												))}
											</div>
										</div>
										<div className="flex items-center justify-between">
											<span className="text-[10px] text-slate-500">
												{gifOutputDimensions.width} × {gifOutputDimensions.height}px
											</span>
											<div className="flex items-center gap-2">
												<span className="text-[10px] text-slate-400">Loop</span>
												<Switch
													checked={gifLoop}
													onCheckedChange={setGifLoop}
													className="data-[state=checked]:bg-[#2563EB] scale-75"
												/>
											</div>
										</div>
									</div>
								)}
							</div>
						</PopoverContent>
					</Popover>
				</div>
			</div>

			<div className="flex-1 p-5 gap-4 flex min-h-0 relative">
				{/* Left Column - Video & Timeline */}
				<div className="flex-[7] flex flex-col gap-3 min-w-0 h-full">
					<PanelGroup direction="vertical" className="gap-3">
						{/* Top section: video preview and controls */}
						<Panel defaultSize={70} minSize={40}>
							<div className="w-full h-full flex flex-col items-center justify-center bg-black/40 rounded-2xl border border-white/5 shadow-2xl overflow-hidden">
								{/* Video preview */}
								<div
									className="w-full flex justify-center items-center"
									style={{ flex: "1 1 auto", margin: "6px 0 0" }}
								>
									<div
										className="relative"
										style={{
											width: "auto",
											height: "100%",
											aspectRatio: getAspectRatioValue(
												aspectRatio,
												(() => {
													const previewVideo = videoPlaybackRef.current?.video;
													if (previewVideo && previewVideo.videoHeight > 0) {
														return previewVideo.videoWidth / previewVideo.videoHeight;
													}
													return 16 / 9;
												})(),
											),
											maxWidth: "100%",
											margin: "0 auto",
											boxSizing: "border-box",
										}}
									>
										<Profiler id="VideoPlayback" onRender={onRenderProfiler}>
											<VideoPlayback
												key={videoPath || "no-video"}
												aspectRatio={aspectRatio}
												ref={videoPlaybackRef}
												videoPath={videoPath || ""}
												facecamVideoPath={facecamPlaybackPath || undefined}
												facecamOffsetMs={facecamOffsetMs}
												facecamSettings={facecamSettings}
												onDurationChange={setDuration}
												onTimeUpdate={timeStore.setTime}
												onPlayStateChange={setIsPlaying}
												onError={setError}
												wallpaper={wallpaper}
												zoomRegions={effectiveZoomRegions}
												selectedZoomId={selectedZoomId}
												onSelectZoom={handleSelectZoom}
												onZoomFocusChange={handleZoomFocusChange}
												isPlaying={isPlaying}
												showShadow={shadowIntensity > 0}
												shadowIntensity={shadowIntensity}
												backgroundBlur={backgroundBlur}
												zoomMotionBlur={zoomMotionBlur}
												connectZooms={connectZooms}
												borderRadius={borderRadius}
												padding={padding}
												cropRegion={cropRegion}
												trimRegions={trimRegions}
												speedRegions={speedRegions}
												annotationRegions={annotationRegions}
												selectedAnnotationId={selectedAnnotationId}
												onSelectAnnotation={handleSelectAnnotation}
												onAnnotationPositionChange={handleAnnotationPositionChange}
												onAnnotationSizeChange={handleAnnotationSizeChange}
												cursorTelemetry={effectiveCursorTelemetry}
												showCursor={showCursor}
												cursorSize={cursorSize}
												cursorSmoothing={cursorSmoothing}
												cursorMotionBlur={cursorMotionBlur}
												cursorClickBounce={cursorClickBounce}
												onReadyChange={setPlaybackReady}
											/>
										</Profiler>
									</div>
								</div>
								{/* Playback controls */}
								<div
									className="w-full flex justify-center items-center"
									style={{
										height: "48px",
										flexShrink: 0,
										padding: "6px 12px",
										margin: "6px 0 6px 0",
									}}
								>
									<div style={{ width: "100%", maxWidth: "700px" }}>
										<Profiler id="PlaybackControls" onRender={onRenderProfiler}>
											<PlaybackControls
												isPlaying={isPlaying}
												timeStore={timeStore}
												duration={duration}
												onTogglePlayPause={togglePlayPause}
												onSeek={handleSeek}
											/>
										</Profiler>
									</div>
								</div>
							</div>
						</Panel>

						<PanelResizeHandle className="h-3 bg-[#09090b]/80 hover:bg-[#09090b] transition-colors rounded-full mx-4 flex items-center justify-center">
							<div className="w-8 h-1 bg-white/20 rounded-full"></div>
						</PanelResizeHandle>

						{/* Timeline section */}
						<Panel defaultSize={30} minSize={20}>
							<div className="h-full min-h-0 bg-[#09090b] rounded-2xl border border-white/5 shadow-lg overflow-auto flex flex-col">
								<Profiler id="TimelineEditor" onRender={onRenderProfiler}>
									<TimelineEditor
										videoDuration={duration}
										timeStore={timeStore}
										onSeek={handleSeek}
										cursorTelemetry={effectiveCursorTelemetry}
										zoomRegions={effectiveZoomRegions}
										onZoomAdded={handleZoomAdded}
										onZoomSuggested={handleZoomSuggested}
										onZoomSpanChange={handleZoomSpanChange}
										onZoomDelete={handleZoomDelete}
										selectedZoomId={selectedZoomId}
										onSelectZoom={handleSelectZoom}
										trimRegions={trimRegions}
										onTrimAdded={handleTrimAdded}
										onTrimSpanChange={handleTrimSpanChange}
										onTrimDelete={handleTrimDelete}
										selectedTrimId={selectedTrimId}
										onSelectTrim={handleSelectTrim}
										speedRegions={speedRegions}
										onSpeedAdded={handleSpeedAdded}
										onSpeedSpanChange={handleSpeedSpanChange}
										onSpeedDelete={handleSpeedDelete}
										selectedSpeedId={selectedSpeedId}
										onSelectSpeed={handleSelectSpeed}
										annotationRegions={annotationRegions}
										onAnnotationAdded={handleAnnotationAdded}
										onAnnotationSpanChange={handleAnnotationSpanChange}
										onAnnotationDelete={handleAnnotationDelete}
										selectedAnnotationId={selectedAnnotationId}
										onSelectAnnotation={handleSelectAnnotation}
										aspectRatio={aspectRatio}
										onAspectRatioChange={setAspectRatio}
									/>
								</Profiler>
							</div>
						</Panel>
					</PanelGroup>
				</div>

				{/* Right section: settings panel */}
				<Profiler id="SettingsPanel" onRender={onRenderProfiler}>
					<SettingsPanel
						selected={wallpaper}
						onWallpaperChange={setWallpaper}
						selectedZoomDepth={selectedZoomDepth}
						onZoomDepthChange={handleZoomDepthChange}
						selectedZoomId={selectedZoomId}
						onZoomDelete={handleZoomDelete}
						selectedTrimId={selectedTrimId}
						onTrimDelete={handleTrimDelete}
						shadowIntensity={shadowIntensity}
						onShadowChange={setShadowIntensity}
						backgroundBlur={backgroundBlur}
						onBackgroundBlurChange={setBackgroundBlur}
						zoomMotionBlur={zoomMotionBlur}
						onZoomMotionBlurChange={setZoomMotionBlur}
						connectZooms={connectZooms}
						onConnectZoomsChange={setConnectZooms}
						showCursor={showCursor}
						onShowCursorChange={setShowCursor}
						loopCursor={loopCursor}
						onLoopCursorChange={setLoopCursor}
						cursorSize={cursorSize}
						onCursorSizeChange={setCursorSize}
						cursorSmoothing={cursorSmoothing}
						onCursorSmoothingChange={setCursorSmoothing}
						cursorMotionBlur={cursorMotionBlur}
						onCursorMotionBlurChange={setCursorMotionBlur}
						cursorClickBounce={cursorClickBounce}
						onCursorClickBounceChange={setCursorClickBounce}
						borderRadius={borderRadius}
						onBorderRadiusChange={setBorderRadius}
						padding={padding}
						onPaddingChange={setPadding}
						cropRegion={cropRegion}
						onCropChange={setCropRegion}
						facecamVideoPath={facecamVideoPath}
						facecamSettings={facecamSettings}
						onFacecamSettingsChange={setFacecamSettings}
						aspectRatio={aspectRatio}
						videoElement={videoPlaybackRef.current?.video || null}
						selectedAnnotationId={selectedAnnotationId}
						annotationRegions={annotationRegions}
						onAnnotationContentChange={handleAnnotationContentChange}
						onAnnotationTypeChange={handleAnnotationTypeChange}
						onAnnotationStyleChange={handleAnnotationStyleChange}
						onAnnotationFigureDataChange={handleAnnotationFigureDataChange}
						onAnnotationDelete={handleAnnotationDelete}
						selectedSpeedId={selectedSpeedId}
						selectedSpeedValue={selectedSpeedValue}
						onSpeedChange={handleSpeedChange}
						onSpeedDelete={handleSpeedDelete}
					/>
				</Profiler>
			</div>

			<Toaster theme="dark" className="pointer-events-auto" />
			<UpdateNotification />

			<AllShortcutsDialog open={showShortcutsDialog} onOpenChange={setShowShortcutsDialog} />

			<ExportDialog
				isOpen={showExportDialog}
				onClose={handleExportDialogClose}
				progress={exportProgress}
				isExporting={isExporting}
				error={exportError}
				onCancel={handleCancelExport}
				onRetrySave={handleRetrySaveExport}
				canRetrySave={hasPendingExportSave}
				exportFormat={exportFormat}
				exportedFilePath={exportedFilePath}
			/>
		</div>
	);
}
