/**
 * Application state for the Electron main process.
 * Mirrors the Rust AppState from src-tauri/src/state/.
 */

export interface SelectedSource {
	id: string;
	name: string;
	sourceType?: string; // "screen" | "window"
	thumbnail?: string;
	displayId?: string;
	appIcon?: string;
	originalName?: string;
	appName?: string;
	windowTitle?: string;
	windowId?: number;
}

export interface FacecamSettings {
	enabled: boolean;
	shape: string;
	size: number;
	cornerRadius: number;
	borderWidth: number;
	borderColor: string;
	margin: number;
	anchor: string;
	customX?: number;
	customY?: number;
}

export interface RecordingSession {
	screenVideoPath: string;
	facecamVideoPath?: string;
	facecamOffsetMs?: number;
	facecamSettings?: FacecamSettings;
	sourceName?: string;
}

export interface CursorTelemetryPoint {
	x: number;
	y: number;
	timestamp: number;
	cursor_type?: string;
	click_type?: string;
}

export interface ShortcutConfig {
	startStopRecording?: string;
	pauseResumeRecording?: string;
	cancelRecording?: string;
}

export interface CursorTelemetryCapture {
	stop: () => void;
	samples: CursorTelemetryPoint[];
	intervalId?: ReturnType<typeof setInterval>;
}

export interface AppState {
	selectedSource: SelectedSource | null;
	cachedWindowSources: SelectedSource[];
	currentVideoPath: string | null;
	currentRecordingSession: RecordingSession | null;
	currentProjectPath: string | null;
	customRecordingsDir: string | null;
	nativeScreenRecordingActive: boolean;
	cursorTelemetry: CursorTelemetryPoint[];
	cursorTelemetryCapture: CursorTelemetryCapture | null;
	cachedSystemCursorAssets: unknown | null;
	hasUnsavedChanges: boolean;
	unsavedEditorWindows: Set<string>;
	cursorScale: number;
	shortcuts: ShortcutConfig | null;
	currentScreenshotPath: string | null;
}

export function createDefaultState(): AppState {
	return {
		selectedSource: null,
		cachedWindowSources: [],
		currentVideoPath: null,
		currentRecordingSession: null,
		currentProjectPath: null,
		customRecordingsDir: null,
		nativeScreenRecordingActive: false,
		cursorTelemetry: [],
		cursorTelemetryCapture: null,
		cachedSystemCursorAssets: null,
		hasUnsavedChanges: false,
		unsavedEditorWindows: new Set(),
		cursorScale: 1.0,
		shortcuts: null,
		currentScreenshotPath: null,
	};
}
