/**
 * Typed registry for the Tauri IPC shim.
 *
 * Maps every Tauri command name (exactly as called in backend.ts) to its
 * TypeScript return type so tests get autocompletion when setting up handlers.
 */

// ─── Types mirroring backend.ts ─────────────────────────────────────────────

export type PermissionStatus =
  | "granted"
  | "denied"
  | "restricted"
  | "not_determined"
  | "unknown"
  | "checking";

export interface DesktopSource {
  id: string;
  name: string;
  sourceType?: "screen" | "window";
  thumbnail?: string | null;
  appIcon?: string | null;
  windowId?: number;
  windowTitle?: string;
  window_title?: string;
}

export interface ProcessedDesktopSource extends DesktopSource {
  displayId?: string;
}

export interface RecordingSession {
  videoPath: string;
  facecamPath?: string | null;
  facecamOffsetMs?: number;
  startedAt: number;
  sourceId?: string;
  sourceName?: string;
  width?: number;
  height?: number;
  frameRate?: number;
  cursorTelemetryPath?: string | null;
}

export interface SourceListOptions {
  types?: string[];
  thumbnailSize?: { width?: number; height?: number };
  withThumbnails?: boolean;
  timeoutMs?: number;
}

export interface NativeRecordingOptions {
  captureCursor?: boolean;
  capturesSystemAudio?: boolean;
  capturesMicrophone?: boolean;
  microphoneDeviceId?: string;
  microphoneLabel?: string;
}

// ─── Command handler map ─────────────────────────────────────────────────────

/**
 * Typed map from every Tauri command name to (args) => ReturnType.
 * Each handler receives the args object passed to invoke().
 */
export interface TauriCommandHandlers {
  // Platform
  get_platform: () => string;
  get_asset_base_path: () => string;
  hide_cursor: () => null;
  open_external_url: (args: { url: string }) => null;
  reveal_in_folder: (args: { path: string }) => null;
  open_recordings_folder: () => null;

  // Files
  get_current_video_path: () => string | null;
  get_recorded_video_path: () => string | null;
  set_current_video_path: (args: { path: string }) => null;
  clear_current_video_path: () => null;
  get_current_screenshot_path: () => string | null;
  set_current_screenshot_path: (args: { path: string | null }) => null;
  read_local_file: (args: { path: string }) => number[];
  prepare_recording_file: (args: { fileName: string }) => string;
  append_recording_data: (args: { path: string; data: number[] }) => null;
  replace_recording_data: (args: { path: string; data: number[] }) => string;
  delete_recording_file: (args: { path: string }) => null;
  store_recording_asset: (args: { assetData: number[]; fileName: string }) => string;
  store_recorded_video: (args: { videoData: number[]; fileName: string }) => string;

  // Recording session
  get_current_recording_session: () => RecordingSession | null;
  set_current_recording_session: (args: { session: RecordingSession }) => null;

  // Settings
  get_recordings_directory: () => string;
  choose_recordings_directory: () => string | null;
  get_shortcuts: () => unknown | null;
  save_shortcuts: (args: { shortcuts: unknown }) => null;

  // Sources
  get_sources: (args: { opts?: SourceListOptions }) => ProcessedDesktopSource[];
  get_selected_source: () => DesktopSource | null;
  select_source: (args: { source: DesktopSource }) => null;
  flash_selected_screen: (args: { source: DesktopSource }) => null;

  // Recording
  set_recording_state: (args: { recording: boolean }) => null;
  start_native_screen_recording: (args: {
    source: DesktopSource;
    options: NativeRecordingOptions;
  }) => string;
  stop_native_screen_recording: () => string;
  start_cursor_telemetry_capture: () => null;
  stop_cursor_telemetry_capture: (args: { videoPath?: string | null }) => null;
  select_screen_area: () => {
    x: number;
    y: number;
    width: number;
    height: number;
    displayId: number;
  } | null;

  // Cursor
  get_cursor_telemetry: (args: { videoPath: string }) => unknown[];
  set_cursor_scale: (args: { scale: number }) => null;
  get_system_cursor_assets: () => unknown[];

  // Permissions
  get_screen_recording_permission_status: () => PermissionStatus;
  request_screen_recording_permission: () => boolean;
  open_screen_recording_preferences: () => null;
  get_accessibility_permission_status: () => PermissionStatus;
  request_accessibility_permission: () => boolean;
  open_accessibility_preferences: () => null;
  get_microphone_permission_status: () => PermissionStatus;
  request_microphone_permission: () => boolean;
  get_camera_permission_status: () => PermissionStatus;
  request_camera_permission: () => boolean;
  open_microphone_preferences: () => null;
  open_camera_preferences: () => null;

  // Dialogs
  save_exported_video: (args: { videoData: number[]; fileName: string }) => string | null;
  save_screenshot_file: (args: { imageData: number[]; fileName: string }) => string | null;
  open_video_file_picker: () => string | null;
  save_project_file: (args: {
    data: string;
    suggestedName?: string;
    existingPath?: string;
  }) => string | null;
  load_project_file: () => unknown | null;
  load_current_project_file: () => unknown | null;

  // Screenshot
  take_screenshot: (args: { captureType: string; windowId?: number }) => string;

  // Window management
  switch_to_editor: (args: { query?: string }) => null;
  switch_to_image_editor: () => null;
  open_source_selector: (args: { tab?: "screens" | "windows" }) => null;
  close_source_selector: () => null;
  hud_overlay_show: () => null;
  hud_overlay_hide: () => null;
  hud_overlay_close: () => null;
  start_hud_overlay_drag: () => null;
  set_has_unsaved_changes: (args: { hasChanges: boolean }) => null;

  // Windows-specific
  is_wgc_available: () => boolean;
  mux_wgc_recording: () => string;
}

// ─── Helper types ─────────────────────────────────────────────────────────────

/**
 * A partial handler map that overrides specific commands for a test.
 * Values must be JSON-serializable (they're passed to page.addInitScript).
 */
export type PartialHandlerValues = {
  [K in keyof TauriCommandHandlers]?: ReturnType<TauriCommandHandlers[K]>;
};

/**
 * All known Tauri event names (as used in listen() calls).
 */
export type TauriEventName =
  | "stop-recording-from-tray"
  | "new-recording-from-tray"
  | "recording-state-changed"
  | "recording-interrupted"
  | "cursor-state-changed"
  | "menu-open-video-file"
  | "menu-load-project"
  | "menu-save-project"
  | "menu-save-project-as"
  | "request-save-before-close"
  | "menu-check-updates";
