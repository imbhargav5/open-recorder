/**
 * Backend abstraction layer — Tauri v2 commands and event listeners.
 */

import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import { convertFileSrc } from '@tauri-apps/api/core';

export type { UnlistenFn };

// ─── Platform ───────────────────────────────────────────────────────────────

export function getPlatform(): Promise<string> {
  return invoke('get_platform');
}

export function openExternalUrl(url: string): Promise<void> {
  return invoke('open_external_url', { url });
}

export function revealInFolder(path: string): Promise<void> {
  return invoke('reveal_in_folder', { path });
}

export function openRecordingsFolder(): Promise<void> {
  return invoke('open_recordings_folder');
}

export function getAssetBasePath(): Promise<string> {
  return invoke('get_asset_base_path');
}

export function hideCursor(): Promise<void> {
  return invoke('hide_cursor');
}

// ─── Files ──────────────────────────────────────────────────────────────────

export async function readLocalFile(path: string): Promise<Uint8Array> {
  const data: number[] = await invoke('read_local_file', { path });
  return new Uint8Array(data);
}

export function storeRecordedVideo(
  videoData: Uint8Array,
  fileName: string
): Promise<string> {
  return invoke('store_recorded_video', {
    videoData: Array.from(videoData),
    fileName,
  });
}

export function storeRecordingAsset(
  assetData: Uint8Array,
  fileName: string
): Promise<string> {
  return invoke('store_recording_asset', {
    assetData: Array.from(assetData),
    fileName,
  });
}

export function getRecordedVideoPath(): Promise<string | null> {
  return invoke('get_recorded_video_path');
}

export function setCurrentVideoPath(path: string): Promise<void> {
  return invoke('set_current_video_path', { path });
}

export function getCurrentVideoPath(): Promise<string | null> {
  return invoke('get_current_video_path');
}

export function clearCurrentVideoPath(): Promise<void> {
  return invoke('clear_current_video_path');
}

// ─── Recording Session ──────────────────────────────────────────────────────

export function getCurrentRecordingSession(): Promise<any | null> {
  return invoke('get_current_recording_session');
}

export function setCurrentRecordingSession(session: any): Promise<void> {
  return invoke('set_current_recording_session', { session });
}

// ─── Settings ───────────────────────────────────────────────────────────────

export function getRecordingsDirectory(): Promise<string> {
  return invoke('get_recordings_directory');
}

export function chooseRecordingsDirectory(): Promise<string | null> {
  return invoke('choose_recordings_directory');
}

export function getShortcuts(): Promise<any | null> {
  return invoke('get_shortcuts');
}

export function saveShortcuts(shortcuts: any): Promise<void> {
  return invoke('save_shortcuts', { shortcuts });
}

// ─── Sources ────────────────────────────────────────────────────────────────

export function selectSource(source: any): Promise<void> {
  return invoke('select_source', { source });
}

export function flashSelectedScreen(source: any): Promise<void> {
  return invoke('flash_selected_screen', { source });
}

export function getSelectedSource(): Promise<any | null> {
  return invoke('get_selected_source');
}

export function getSources(opts?: any): Promise<any[]> {
  return invoke('get_sources', { opts });
}

// ─── Recording ──────────────────────────────────────────────────────────────

export function setRecordingState(recording: boolean): Promise<void> {
  return invoke('set_recording_state', { recording });
}

export function startNativeScreenRecording(
  source: any,
  options: any
): Promise<string> {
  return invoke('start_native_screen_recording', { source, options });
}

export function stopNativeScreenRecording(): Promise<string> {
  return invoke('stop_native_screen_recording');
}

// ─── Cursor ─────────────────────────────────────────────────────────────────

export function getCursorTelemetry(videoPath: string): Promise<any> {
  return invoke('get_cursor_telemetry', { videoPath });
}

export function setCursorScale(scale: number): Promise<void> {
  return invoke('set_cursor_scale', { scale });
}

export function getSystemCursorAssets(): Promise<any> {
  return invoke('get_system_cursor_assets');
}

// ─── Permissions ────────────────────────────────────────────────────────────

export function getScreenRecordingPermissionStatus(): Promise<string> {
  return invoke('get_screen_recording_permission_status');
}

export function requestScreenRecordingPermission(): Promise<boolean> {
  return invoke('request_screen_recording_permission');
}

export function openScreenRecordingPreferences(): Promise<void> {
  return invoke('open_screen_recording_preferences');
}

export function getAccessibilityPermissionStatus(): Promise<string> {
  return invoke('get_accessibility_permission_status');
}

export function requestAccessibilityPermission(): Promise<boolean> {
  return invoke('request_accessibility_permission');
}

export function openAccessibilityPreferences(): Promise<void> {
  return invoke('open_accessibility_preferences');
}

// ─── Dialogs ────────────────────────────────────────────────────────────────

export function saveExportedVideo(
  videoData: Uint8Array,
  fileName: string
): Promise<string | null> {
  return invoke('save_exported_video', {
    videoData: Array.from(videoData),
    fileName,
  });
}

export function openVideoFilePicker(): Promise<string | null> {
  return invoke('open_video_file_picker');
}

export function saveProjectFile(
  data: string,
  suggestedName?: string,
  existingPath?: string
): Promise<string | null> {
  return invoke('save_project_file', { data, suggestedName, existingPath });
}

export function loadProjectFile(): Promise<any | null> {
  return invoke('load_project_file');
}

export function loadCurrentProjectFile(): Promise<any | null> {
  return invoke('load_current_project_file');
}

// ─── Window Management ──────────────────────────────────────────────────────

export function switchToEditor(): Promise<void> {
  return invoke('switch_to_editor');
}

export function openSourceSelector(): Promise<void> {
  return invoke('open_source_selector');
}

export function hudOverlayHide(): Promise<void> {
  return invoke('hud_overlay_hide');
}

export function hudOverlayClose(): Promise<void> {
  return invoke('hud_overlay_close');
}

export function setHasUnsavedChanges(hasChanges: boolean): Promise<void> {
  return invoke('set_has_unsaved_changes', { hasChanges });
}

// ─── Windows-specific ───────────────────────────────────────────────────────

export function isWgcAvailable(): Promise<boolean> {
  return invoke('is_wgc_available');
}

export function muxWgcRecording(): Promise<string> {
  return invoke('mux_wgc_recording');
}

// ─── Event Listeners ────────────────────────────────────────────────────────

export function onStopRecordingFromTray(callback: () => void): Promise<UnlistenFn> {
  return listen('stop-recording-from-tray', callback);
}

export function onRecordingStateChanged(
  callback: (recording: boolean) => void
): Promise<UnlistenFn> {
  return listen('recording-state-changed', (e) => callback(e.payload as boolean));
}

export function onRecordingInterrupted(callback: () => void): Promise<UnlistenFn> {
  return listen('recording-interrupted', callback);
}

export function onCursorStateChanged(
  callback: (cursorType: string) => void
): Promise<UnlistenFn> {
  return listen('cursor-state-changed', (e) => callback(e.payload as string));
}

export function onMenuLoadProject(callback: () => void): Promise<UnlistenFn> {
  return listen('menu-load-project', callback);
}

export function onMenuSaveProject(callback: () => void): Promise<UnlistenFn> {
  return listen('menu-save-project', callback);
}

export function onMenuSaveProjectAs(callback: () => void): Promise<UnlistenFn> {
  return listen('menu-save-project-as', callback);
}

export function onRequestSaveBeforeClose(callback: () => void): Promise<UnlistenFn> {
  return listen('request-save-before-close', callback);
}

export function onMenuCheckUpdates(callback: () => void): Promise<UnlistenFn> {
  return listen('menu-check-updates', callback);
}

// ─── Asset Path Conversion ──────────────────────────────────────────────────

export function convertFileToSrc(path: string): Promise<string> {
  return Promise.resolve(convertFileSrc(path));
}

// ─── Runtime Detection ──────────────────────────────────────────────────────

export function isTauri(): boolean {
  return true;
}

