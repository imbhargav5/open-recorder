import { atom } from "jotai";
import type { Setter } from "jotai/vanilla";
import {
	type AnnotationRegion,
	type CropRegion,
	type CursorTelemetryPoint,
	DEFAULT_AUDIO_MUTED,
	DEFAULT_AUDIO_VOLUME,
	DEFAULT_CROP_REGION,
	DEFAULT_CURSOR_CLICK_BOUNCE,
	DEFAULT_CURSOR_MOTION_BLUR,
	DEFAULT_CURSOR_SIZE,
	DEFAULT_CURSOR_SMOOTHING,
	DEFAULT_ZOOM_MOTION_BLUR,
	type SpeedRegion,
	type TrimRegion,
	type ZoomRegion,
} from "@/components/video-editor/types";
import type { CustomFont } from "@/lib/customFonts";
import type {
	ExportFormat,
	ExportProgress,
	ExportQuality,
	GifFrameRate,
	GifSizePreset,
} from "@/lib/exporter";
import { createDefaultFacecamSettings, type FacecamSettings } from "@/lib/recordingSession";
import { DEFAULT_WALLPAPER_PATH } from "@/lib/wallpapers";
import type { AspectRatio } from "@/utils/aspectRatioUtils";
import { resetTimelineRuntimeAtom } from "./timeline";

// --- Composite types ---
export type CursorSettings = {
	showCursor: boolean;
	loopCursor: boolean;
	cursorSize: number;
	cursorSmoothing: number;
	cursorMotionBlur: number;
	cursorClickBounce: number;
};
export type CropDragHandle = "top" | "right" | "bottom" | "left" | null;

// --- Video source ---
export const videoPathAtom = atom<string | null>(null);
export const videoSourcePathAtom = atom<string | null>(null);
export const sourceNameAtom = atom<string | null>(null);
export const facecamVideoPathAtom = atom<string | null>(null);
export const facecamPlaybackPathAtom = atom<string | null>(null);
export const facecamOffsetMsAtom = atom<number>(0);
export const currentProjectPathAtom = atom<string | null>(null);

// --- Loading/error state ---
export const videoLoadingAtom = atom<boolean>(true);
export const playbackReadyAtom = atom<boolean>(false);
export const videoErrorAtom = atom<string | null>(null);
export const videoPlaybackPixiReadyAtom = atom<boolean>(false);
export const videoPlaybackMetadataReadyAtom = atom<boolean>(false);
export const videoPlaybackFirstFrameReadyAtom = atom<boolean>(false);
export const videoPlaybackCursorOverlayReadyAtom = atom<boolean>(false);
export const videoPlaybackFacecamReadyAtom = atom<boolean>(false);
export const videoPlaybackAnnotationVisibilityTickAtom = atom<number>(0);
export const videoPlaybackResolvedWallpaperAtom = atom<string | null>(null);
export const resetVideoPlaybackRuntimeAtom = atom(null, (_get, set) => {
	set(videoPlaybackPixiReadyAtom, false);
	set(videoPlaybackMetadataReadyAtom, false);
	set(videoPlaybackFirstFrameReadyAtom, false);
	set(videoPlaybackCursorOverlayReadyAtom, false);
	set(videoPlaybackFacecamReadyAtom, false);
	set(videoPlaybackAnnotationVisibilityTickAtom, 0);
	set(videoPlaybackResolvedWallpaperAtom, null);
});

export const resetEditorPlaybackForSourceAtom = atom(null, (_get, set) => {
	set(isPlayingAtom, false);
	set(durationAtom, 0);
	set(videoErrorAtom, null);
	set(playbackReadyAtom, false);
	set(cursorTelemetryAtom, []);
	set(resetVideoPlaybackRuntimeAtom);
	set(resetTimelineRuntimeAtom);
	set(clearTimelineSelectionAtom);
});

// --- Playback state ---
export const isPlayingAtom = atom<boolean>(false);
export const durationAtom = atom<number>(0);

// --- Appearance settings ---
export const videoWallpaperAtom = atom<string>(DEFAULT_WALLPAPER_PATH);
export const audioMutedAtom = atom<boolean>(DEFAULT_AUDIO_MUTED);
export const audioVolumeAtom = atom<number>(DEFAULT_AUDIO_VOLUME);
export const shadowIntensityAtom = atom<number>(0.67);
export const backgroundBlurAtom = atom<number>(0);
export const zoomMotionBlurAtom = atom<number>(DEFAULT_ZOOM_MOTION_BLUR);
export const connectZoomsAtom = atom<boolean>(true);
export const borderRadiusAtom = atom<number>(12.5);
export const paddingAtom = atom<number>(50);

// --- Cursor settings (composite) ---
export const cursorSettingsAtom = atom<CursorSettings>({
	showCursor: false,
	loopCursor: false,
	cursorSize: DEFAULT_CURSOR_SIZE,
	cursorSmoothing: DEFAULT_CURSOR_SMOOTHING,
	cursorMotionBlur: DEFAULT_CURSOR_MOTION_BLUR,
	cursorClickBounce: DEFAULT_CURSOR_CLICK_BOUNCE,
});

// --- Crop / Facecam ---
export const cropRegionAtom = atom<CropRegion>(DEFAULT_CROP_REGION);
export const cropControlDragHandleAtom = atom<CropDragHandle>(null);
export const cropControlDragStartAtom = atom<{ x: number; y: number }>({ x: 0, y: 0 });
export const cropControlInitialCropAtom = atom<CropRegion>(DEFAULT_CROP_REGION);
export const resetCropControlDragAtom = atom(null, (_get, set) => {
	set(cropControlDragHandleAtom, null);
	set(cropControlDragStartAtom, { x: 0, y: 0 });
	set(cropControlInitialCropAtom, DEFAULT_CROP_REGION);
});
export const facecamSettingsAtom = atom<FacecamSettings>(createDefaultFacecamSettings());

// --- Zoom / Trim / Speed / Annotation regions ---
export const zoomRegionsAtom = atom<ZoomRegion[]>([]);
export const cursorTelemetryAtom = atom<CursorTelemetryPoint[]>([]);
export const selectedZoomIdAtom = atom<string | null>(null);
export const trimRegionsAtom = atom<TrimRegion[]>([]);
export const selectedTrimIdAtom = atom<string | null>(null);
export const speedRegionsAtom = atom<SpeedRegion[]>([]);
export const selectedSpeedIdAtom = atom<string | null>(null);
export const annotationRegionsAtom = atom<AnnotationRegion[]>([]);
export const selectedAnnotationIdAtom = atom<string | null>(null);

export const clearTimelineSelectionAtom = atom(null, (_get, set) => {
	set(selectedZoomIdAtom, null);
	set(selectedTrimIdAtom, null);
	set(selectedSpeedIdAtom, null);
	set(selectedAnnotationIdAtom, null);
});
export const selectZoomAtom = atom(null, (_get, set, id: string | null) => {
	set(selectedZoomIdAtom, id);
	if (id) {
		set(selectedTrimIdAtom, null);
		set(selectedSpeedIdAtom, null);
		set(selectedAnnotationIdAtom, null);
	}
});
export const selectTrimAtom = atom(null, (_get, set, id: string | null) => {
	set(selectedTrimIdAtom, id);
	if (id) {
		set(selectedZoomIdAtom, null);
		set(selectedSpeedIdAtom, null);
		set(selectedAnnotationIdAtom, null);
	}
});
export const selectSpeedAtom = atom(null, (_get, set, id: string | null) => {
	set(selectedSpeedIdAtom, id);
	if (id) {
		set(selectedZoomIdAtom, null);
		set(selectedTrimIdAtom, null);
		set(selectedAnnotationIdAtom, null);
	}
});
export const selectAnnotationAtom = atom(null, (_get, set, id: string | null) => {
	set(selectedAnnotationIdAtom, id);
	if (id) {
		set(selectedZoomIdAtom, null);
		set(selectedTrimIdAtom, null);
		set(selectedSpeedIdAtom, null);
	}
});

type LoadedEditorStatePayload = {
	wallpaper: string;
	audioMuted: boolean;
	audioVolume: number;
	shadowIntensity: number;
	backgroundBlur: number;
	zoomMotionBlur: number;
	connectZooms: boolean;
	cursorSettings: CursorSettings;
	borderRadius: number;
	padding: number;
	cropRegion: CropRegion;
	facecamSettings: FacecamSettings;
	zoomRegions: ZoomRegion[];
	trimRegions: TrimRegion[];
	speedRegions: SpeedRegion[];
	annotationRegions: AnnotationRegion[];
	aspectRatio: AspectRatio;
	exportQuality: ExportQuality;
	exportFormat: ExportFormat;
	gifFrameRate: GifFrameRate;
	gifLoop: boolean;
	gifSizePreset: GifSizePreset;
};

type ApplyLoadedProjectPayload = {
	sourcePath: string;
	resolvedVideoPath: string;
	sourceName: string | null;
	facecamVideoPath: string | null;
	facecamPlaybackPath: string | null;
	facecamOffsetMs: number;
	currentProjectPath: string | null;
	editor: LoadedEditorStatePayload;
	lastSavedSnapshot: string;
};

type ApplyLoadedSessionPayload = {
	sourcePath: string;
	resolvedVideoPath: string;
	sourceName: string | null;
	facecamVideoPath: string | null;
	facecamPlaybackPath: string | null;
	facecamOffsetMs: number;
	facecamSettings: FacecamSettings;
	showCursorOverlay: boolean;
};

type ApplyLoadedVideoPayload = {
	sourcePath: string;
	resolvedVideoPath: string;
	sourceName: string | null;
	facecamSettings: FacecamSettings;
};

function applyLoadedEditorState(set: Setter, editor: LoadedEditorStatePayload) {
	set(videoWallpaperAtom, editor.wallpaper);
	set(audioMutedAtom, editor.audioMuted);
	set(audioVolumeAtom, editor.audioVolume);
	set(shadowIntensityAtom, editor.shadowIntensity);
	set(backgroundBlurAtom, editor.backgroundBlur);
	set(zoomMotionBlurAtom, editor.zoomMotionBlur);
	set(connectZoomsAtom, editor.connectZooms);
	set(cursorSettingsAtom, editor.cursorSettings);
	set(borderRadiusAtom, editor.borderRadius);
	set(paddingAtom, editor.padding);
	set(cropRegionAtom, editor.cropRegion);
	set(facecamSettingsAtom, editor.facecamSettings);
	set(zoomRegionsAtom, editor.zoomRegions);
	set(trimRegionsAtom, editor.trimRegions);
	set(speedRegionsAtom, editor.speedRegions);
	set(annotationRegionsAtom, editor.annotationRegions);
	set(aspectRatioAtom, editor.aspectRatio);
	set(exportQualityAtom, editor.exportQuality);
	set(exportFormatAtom, editor.exportFormat);
	set(gifFrameRateAtom, editor.gifFrameRate);
	set(gifLoopAtom, editor.gifLoop);
	set(gifSizePresetAtom, editor.gifSizePreset);
}

export const applyLoadedProjectAtom = atom(
	null,
	(_get, set, payload: ApplyLoadedProjectPayload) => {
		set(resetEditorPlaybackForSourceAtom);
		set(videoSourcePathAtom, payload.sourcePath);
		set(videoPathAtom, payload.resolvedVideoPath);
		set(sourceNameAtom, payload.sourceName);
		set(facecamVideoPathAtom, payload.facecamVideoPath);
		set(facecamPlaybackPathAtom, payload.facecamPlaybackPath);
		set(facecamOffsetMsAtom, payload.facecamOffsetMs);
		set(currentProjectPathAtom, payload.currentProjectPath);
		applyLoadedEditorState(set, payload.editor);
		set(clearTimelineSelectionAtom);
		set(lastSavedSnapshotAtom, payload.lastSavedSnapshot);
	},
);

export const applyLoadedSessionAtom = atom(
	null,
	(_get, set, payload: ApplyLoadedSessionPayload) => {
		set(resetEditorPlaybackForSourceAtom);
		set(videoSourcePathAtom, payload.sourcePath);
		set(videoPathAtom, payload.resolvedVideoPath);
		set(sourceNameAtom, payload.sourceName);
		set(facecamVideoPathAtom, payload.facecamVideoPath);
		set(facecamPlaybackPathAtom, payload.facecamPlaybackPath);
		set(facecamOffsetMsAtom, payload.facecamOffsetMs);
		set(facecamSettingsAtom, payload.facecamSettings);
		set(cursorSettingsAtom, (current) =>
			current.showCursor === payload.showCursorOverlay
				? current
				: { ...current, showCursor: payload.showCursorOverlay },
		);
		set(currentProjectPathAtom, null);
		set(lastSavedSnapshotAtom, null);
		set(clearTimelineSelectionAtom);
	},
);

export const applyLoadedVideoAtom = atom(null, (_get, set, payload: ApplyLoadedVideoPayload) => {
	set(resetEditorPlaybackForSourceAtom);
	set(videoSourcePathAtom, payload.sourcePath);
	set(videoPathAtom, payload.resolvedVideoPath);
	set(sourceNameAtom, payload.sourceName);
	set(facecamVideoPathAtom, null);
	set(facecamPlaybackPathAtom, null);
	set(facecamOffsetMsAtom, 0);
	set(facecamSettingsAtom, payload.facecamSettings);
	set(currentProjectPathAtom, null);
	set(lastSavedSnapshotAtom, null);
	set(clearTimelineSelectionAtom);
});

// --- Export state ---
export const isExportingAtom = atom<boolean>(false);
export const exportProgressAtom = atom<ExportProgress | null>(null);
export const exportErrorAtom = atom<string | null>(null);
export const showExportDialogAtom = atom<boolean>(false);
export const exportDialogShowSuccessAtom = atom<boolean>(false);
export const showShortcutsDialogAtom = atom<boolean>(false);
export const aspectRatioAtom = atom<AspectRatio>("16:9");
export const exportQualityAtom = atom<ExportQuality>("good");
export const exportFormatAtom = atom<ExportFormat>("mp4");
export const gifFrameRateAtom = atom<GifFrameRate>(15);
export const gifLoopAtom = atom<boolean>(true);
export const gifSizePresetAtom = atom<GifSizePreset>("medium");
export const exportedFilePathAtom = atom<string | undefined>(undefined);
export const hasPendingExportSaveAtom = atom<boolean>(false);
export const lastSavedSnapshotAtom = atom<string | null>(null);

// --- Custom font dialog state ---
export const addCustomFontDialogOpenAtom = atom<boolean>(false);
export const addCustomFontImportUrlAtom = atom<string>("");
export const addCustomFontNameAtom = atom<string>("");
export const addCustomFontLoadingAtom = atom<boolean>(false);
export const annotationCustomFontsAtom = atom<CustomFont[]>([]);
export const resetAddCustomFontDialogAtom = atom(null, (_get, set) => {
	set(addCustomFontImportUrlAtom, "");
	set(addCustomFontNameAtom, "");
	set(addCustomFontLoadingAtom, false);
});
