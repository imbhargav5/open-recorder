import { atom } from "jotai";
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
