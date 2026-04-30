/**
 * Backend abstraction layer — Electron IPC via contextBridge.
 *
 * All communication with the Electron main process goes through this module.
 * The public API is identical to the former Tauri version so call-sites need
 * no changes.
 */

import { invoke, listen } from "@/lib/electronBridge";
import { toFileUrl } from "@/lib/fileUrl";
import { resolveMediaPlaybackUrl as resolveMediaPlaybackAssetUrl } from "@/lib/mediaPlaybackUrl";
import type { RecordingSession } from "./recordingSession";
import type { ShortcutsConfig } from "./shortcuts";
import type { DesktopSource } from "../components/launch/sourceSelectorState";

export type UnlistenFn = () => void;

function normalizePermissionStatus(status: string): string {
	return status === "not-determined" ? "not_determined" : status;
}

// ─── Source List Options ─────────────────────────────────────────────────────

export interface SourceListOptions {
	types?: string[];
	thumbnailSize?: { width?: number; height?: number };
	withThumbnails?: boolean;
	timeoutMs?: number;
}

// ─── Native Recording Options ────────────────────────────────────────────────

export interface NativeRecordingOptions {
	captureCursor?: boolean;
	capturesSystemAudio?: boolean;
	capturesMicrophone?: boolean;
	microphoneDeviceId?: string;
	microphoneLabel?: string;
}

export type UpdateStatus =
	| "idle"
	| "checking"
	| "up-to-date"
	| "available"
	| "downloading"
	| "ready"
	| "error";

export interface UpdaterState {
	supported: boolean;
	dialogOpen: boolean;
	status: UpdateStatus;
	currentVersion: string;
	version: string | null;
	releaseNotes: string | null;
	downloadProgress: number;
	error: string | null;
}

// ─── Platform ───────────────────────────────────────────────────────────────

export function getPlatform(): Promise<string> {
	return invoke("get_platform");
}

export function openExternalUrl(url: string): Promise<void> {
	return invoke("open_external_url", { url });
}

export function revealInFolder(path: string): Promise<void> {
	return invoke("reveal_in_folder", { path });
}

export function openRecordingsFolder(): Promise<void> {
	return invoke("open_recordings_folder");
}

export function getAssetBasePath(): Promise<string> {
	return invoke("get_asset_base_path");
}

export function hideCursor(): Promise<void> {
	return invoke("hide_cursor");
}

// ─── Files ──────────────────────────────────────────────────────────────────

export async function readLocalFile(path: string): Promise<Uint8Array> {
	const data: number[] = await invoke("read_local_file", { path });
	return new Uint8Array(data);
}

export function resolveMediaPlaybackUrl(path: string): Promise<string> {
	return Promise.resolve(resolveMediaPlaybackAssetUrl(path));
}

export function storeRecordedVideo(videoData: Uint8Array, fileName: string): Promise<string> {
	return invoke("store_recorded_video", {
		videoData: Array.from(videoData),
		fileName,
	});
}

export function prepareRecordingFile(fileName: string): Promise<string> {
	return invoke("prepare_recording_file", { fileName });
}

export function appendRecordingData(path: string, data: Uint8Array): Promise<void> {
	return invoke("append_recording_data", {
		path,
		data: Array.from(data),
	});
}

export function replaceRecordingData(path: string, data: Uint8Array): Promise<string> {
	return invoke("replace_recording_data", {
		path,
		data: Array.from(data),
	});
}

export function deleteRecordingFile(path: string): Promise<void> {
	return invoke("delete_recording_file", { path });
}

export function storeRecordingAsset(assetData: Uint8Array, fileName: string): Promise<string> {
	return invoke("store_recording_asset", {
		assetData: Array.from(assetData),
		fileName,
	});
}

export function getRecordedVideoPath(): Promise<string | null> {
	return invoke("get_recorded_video_path");
}

export function setCurrentVideoPath(path: string): Promise<void> {
	return invoke("set_current_video_path", { path });
}

export function getCurrentVideoPath(): Promise<string | null> {
	return invoke("get_current_video_path");
}

export function clearCurrentVideoPath(): Promise<void> {
	return invoke("clear_current_video_path");
}

// ─── Recording Session ──────────────────────────────────────────────────────

export function getCurrentRecordingSession(): Promise<RecordingSession | null> {
	return invoke("get_current_recording_session");
}

export function setCurrentRecordingSession(session: RecordingSession): Promise<void> {
	return invoke("set_current_recording_session", { session });
}

// ─── Settings ───────────────────────────────────────────────────────────────

export function getRecordingsDirectory(): Promise<string> {
	return invoke("get_recordings_directory");
}

export function chooseRecordingsDirectory(): Promise<string | null> {
	return invoke("choose_recordings_directory");
}

export function getShortcuts(): Promise<ShortcutsConfig | null> {
	return invoke("get_shortcuts");
}

export function saveShortcuts(shortcuts: ShortcutsConfig): Promise<void> {
	return invoke("save_shortcuts", { shortcuts });
}

// ─── Sources ────────────────────────────────────────────────────────────────

export function selectSource(source: DesktopSource): Promise<void> {
	return invoke("select_source", { source });
}

export function flashSelectedScreen(source: DesktopSource): Promise<void> {
	return invoke("flash_selected_screen", { source });
}

export function getSelectedSource(): Promise<DesktopSource | null> {
	return invoke("get_selected_source");
}

export function getSources(opts?: SourceListOptions): Promise<ProcessedDesktopSource[]> {
	return invoke("get_sources", { opts });
}

// ─── Recording ──────────────────────────────────────────────────────────────

export function setRecordingState(recording: boolean): Promise<void> {
	return invoke("set_recording_state", { recording });
}

export function startNativeScreenRecording(
	source: DesktopSource,
	options: NativeRecordingOptions,
): Promise<string> {
	return invoke("start_native_screen_recording", { source, options });
}

export function stopNativeScreenRecording(): Promise<string> {
	return invoke("stop_native_screen_recording");
}

export function startCursorTelemetryCapture(): Promise<void> {
	return invoke("start_cursor_telemetry_capture");
}

export function stopCursorTelemetryCapture(videoPath?: string | null): Promise<void> {
	return invoke("stop_cursor_telemetry_capture", { videoPath });
}

export function selectScreenArea(): Promise<{
	x: number;
	y: number;
	width: number;
	height: number;
	displayId: number;
} | null> {
	return invoke("select_screen_area");
}

// ─── Cursor ─────────────────────────────────────────────────────────────────

export function getCursorTelemetry(videoPath: string): Promise<unknown> {
	return invoke("get_cursor_telemetry", { videoPath });
}

export function setCursorScale(scale: number): Promise<void> {
	return invoke("set_cursor_scale", { scale });
}

export function getSystemCursorAssets(): Promise<unknown> {
	return invoke("get_system_cursor_assets");
}

// ─── Permissions ────────────────────────────────────────────────────────────

export function getScreenRecordingPermissionStatus(): Promise<string> {
	return invoke<string>("get_screen_recording_permission_status")
		.then(normalizePermissionStatus)
		.catch((err) => {
			console.error("[backend] getScreenRecordingPermissionStatus failed:", err);
			return "unknown";
		});
}

export function requestScreenRecordingPermission(): Promise<boolean> {
	return invoke<boolean>("request_screen_recording_permission").catch((err) => {
		console.error("[backend] requestScreenRecordingPermission failed:", err);
		return false;
	});
}

export function openScreenRecordingPreferences(): Promise<void> {
	return invoke("open_screen_recording_preferences");
}

/**
 * Probe effective screen-recording permission by asking the OS for a thumbnail
 * via `desktopCapturer.getSources`.  This bypasses macOS's per-process cache
 * on `systemPreferences.getMediaAccessStatus("screen")`, which otherwise stays
 * stuck on the status read at app launch.
 */
export function probeScreenRecordingEffectiveStatus(): Promise<string> {
	return invoke<string>("probe_screen_recording_effective_status")
		.then(normalizePermissionStatus)
		.catch((err) => {
			console.error("[backend] probeScreenRecordingEffectiveStatus failed:", err);
			return "unknown";
		});
}

export async function getEffectiveScreenRecordingPermissionStatus(): Promise<string> {
	const effectiveStatus = await probeScreenRecordingEffectiveStatus();
	if (effectiveStatus !== "unknown") {
		return effectiveStatus;
	}

	return getScreenRecordingPermissionStatus();
}

/**
 * Relaunch the Electron app.  Required on macOS after granting screen-recording
 * permission in dev because the TCC cache only refreshes on a fresh process.
 */
export function relaunchApp(): Promise<void> {
	return invoke("relaunch_app");
}

export function getUpdaterState(): Promise<UpdaterState> {
	return invoke<UpdaterState>("get_updater_state");
}

export function checkForUpdates(options?: { showDialog?: boolean }): Promise<UpdaterState> {
	return invoke<UpdaterState>("check_for_updates", options ?? {});
}

export function downloadUpdate(): Promise<UpdaterState> {
	return invoke<UpdaterState>("download_update");
}

export function dismissUpdaterDialog(): Promise<UpdaterState> {
	return invoke<UpdaterState>("dismiss_updater_dialog");
}

export function installUpdateAndRestart(): Promise<void> {
	return invoke("install_update_and_restart");
}

export function getAccessibilityPermissionStatus(): Promise<string> {
	return invoke<string>("get_accessibility_permission_status").catch((err) => {
		console.error("[backend] getAccessibilityPermissionStatus failed:", err);
		return "unknown";
	});
}

export function requestAccessibilityPermission(): Promise<boolean> {
	return invoke<boolean>("request_accessibility_permission").catch((err) => {
		console.error("[backend] requestAccessibilityPermission failed:", err);
		return false;
	});
}

export function openAccessibilityPreferences(): Promise<void> {
	return invoke("open_accessibility_preferences");
}

export function getMicrophonePermissionStatus(): Promise<string> {
	return invoke<string>("get_microphone_permission_status")
		.then(normalizePermissionStatus)
		.catch((err) => {
			console.error("[backend] getMicrophonePermissionStatus failed:", err);
			return "unknown";
		});
}

export function requestMicrophonePermission(): Promise<boolean> {
	return invoke<boolean>("request_microphone_permission").catch((err) => {
		console.error("[backend] requestMicrophonePermission failed:", err);
		return false;
	});
}

export function getCameraPermissionStatus(): Promise<string> {
	return invoke<string>("get_camera_permission_status")
		.then(normalizePermissionStatus)
		.catch((err) => {
			console.error("[backend] getCameraPermissionStatus failed:", err);
			return "unknown";
		});
}

export function requestCameraPermission(): Promise<boolean> {
	return invoke<boolean>("request_camera_permission").catch((err) => {
		console.error("[backend] requestCameraPermission failed:", err);
		return false;
	});
}

export function openMicrophonePreferences(): Promise<void> {
	return invoke("open_microphone_preferences");
}

export function openCameraPreferences(): Promise<void> {
	return invoke("open_camera_preferences");
}

// ─── Dialogs ────────────────────────────────────────────────────────────────

export function saveExportedVideo(videoData: Uint8Array, fileName: string): Promise<string | null> {
	return invoke("save_exported_video", {
		videoData: Array.from(videoData),
		fileName,
	});
}

export function saveScreenshotFile(imageData: Uint8Array, fileName: string): Promise<string | null> {
	return invoke("save_screenshot_file", {
		imageData: Array.from(imageData),
		fileName,
	});
}

export function openVideoFilePicker(): Promise<string | null> {
	return invoke("open_video_file_picker");
}

export function saveProjectFile(
	data: string,
	suggestedName?: string,
	existingPath?: string,
): Promise<string | null> {
	return invoke("save_project_file", { data, suggestedName, existingPath });
}

export function loadProjectFile(): Promise<{ data?: unknown; filePath?: string | null } | null> {
	return invoke("load_project_file");
}

export function loadCurrentProjectFile(): Promise<{ data?: unknown; filePath?: string | null } | null> {
	return invoke("load_current_project_file");
}

// ─── Screenshot ─────────────────────────────────────────────────────────────

export function takeScreenshot(captureType: string, windowId?: number): Promise<string> {
	return invoke("take_screenshot", { captureType, windowId });
}

export function getCurrentScreenshotPath(): Promise<string | null> {
	return invoke("get_current_screenshot_path");
}

export function setCurrentScreenshotPath(path: string | null): Promise<void> {
	return invoke("set_current_screenshot_path", { path });
}

// ─── Window Management ──────────────────────────────────────────────────────

export function switchToEditor(query?: string): Promise<void> {
	return invoke("switch_to_editor", { query });
}

export function switchToImageEditor(): Promise<void> {
	return invoke("switch_to_image_editor");
}

export function openSourceSelector(tab?: "screens" | "windows"): Promise<void> {
	return invoke("open_source_selector", { tab });
}

export function closeSourceSelector(): Promise<void> {
	return invoke("close_source_selector");
}

export function hudOverlayShow(): Promise<void> {
	return invoke("hud_overlay_show");
}

export function hudOverlayHide(): Promise<void> {
	return invoke("hud_overlay_hide");
}

export function hudOverlayClose(): Promise<void> {
	return invoke("hud_overlay_close");
}

export function startHudOverlayDrag(): Promise<void> {
	return invoke("start_hud_overlay_drag");
}

export function setHasUnsavedChanges(hasChanges: boolean): Promise<void> {
	return invoke("set_has_unsaved_changes", { hasChanges });
}

// ─── Windows-specific ───────────────────────────────────────────────────────

export function isWgcAvailable(): Promise<boolean> {
	return invoke("is_wgc_available");
}

export function muxWgcRecording(): Promise<string> {
	return invoke("mux_wgc_recording");
}

// ─── Event Listeners ────────────────────────────────────────────────────────

export function onStopRecordingFromTray(callback: () => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("stop-recording-from-tray", callback));
}

export function onNewRecordingFromTray(callback: () => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("new-recording-from-tray", callback));
}

export function onRecordingStateChanged(
	callback: (recording: boolean) => void,
): Promise<UnlistenFn> {
	return Promise.resolve(listen("recording-state-changed", callback));
}

export function onRecordingInterrupted(callback: () => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("recording-interrupted", callback));
}

export function onCursorStateChanged(callback: (cursorType: string) => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("cursor-state-changed", callback));
}

export function onMenuOpenVideoFile(callback: () => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("menu-open-video-file", callback));
}

export function onMenuLoadProject(callback: () => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("menu-load-project", callback));
}

export function onMenuSaveProject(callback: () => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("menu-save-project", callback));
}

export function onMenuSaveProjectAs(callback: () => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("menu-save-project-as", callback));
}

export function onRequestSaveBeforeClose(callback: () => void): Promise<UnlistenFn> {
	return Promise.resolve(listen("request-save-before-close", callback));
}

export function onUpdaterStateChanged(
	callback: (state: UpdaterState) => void,
): Promise<UnlistenFn> {
	return Promise.resolve(listen("updater-state-changed", callback));
}

export function onUpdaterDownloadProgress(
	callback: (event: { percent: number }) => void,
): Promise<UnlistenFn> {
	return Promise.resolve(listen("updater-download-progress", callback));
}

// ─── Asset Path Conversion ──────────────────────────────────────────────────

/**
 * Convert a native file path to a URL that can be loaded in the renderer.
 * In Electron the renderer can load file:// URLs directly.
 */
export function convertFileToSrc(filePath: string): Promise<string> {
	return Promise.resolve(toFileUrl(filePath));
}

// ─── Runtime Detection ──────────────────────────────────────────────────────

export function isElectron(): boolean {
	return typeof window !== "undefined" && "electronAPI" in window;
}

/** @deprecated Use isElectron() */
export function isTauri(): boolean {
	return isElectron();
}
