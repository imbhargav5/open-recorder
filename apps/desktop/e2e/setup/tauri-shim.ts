/**
 * Electron IPC shim for Playwright E2E tests.
 *
 * Installs a fake window.electronAPI so the React renderer can boot and run
 * inside a plain Chromium window (driven by Playwright) without any Electron
 * native binary.
 *
 * Usage (in every test):
 *   await installTauriShim(page);   // kept for backwards-compat — installs the shim
 *   await configureHandlers(page, { get_platform: 'linux', ... });
 *   await setLocalStorage(page, { 'some-key': 'some-value' });
 *   await page.goto('/?windowType=hud-overlay');
 */

export const ELECTRON_SHIM_SCRIPT = /* javascript */ `
(function () {
  if (window.electronAPI) return; // guard against double-injection

  // ─── Public test surfaces ────────────────────────────────────────────────────
  // __TEST_HANDLERS__         : { [channel]: (args) => returnValue }
  // __TEST_EVENT_LISTENERS__  : { [channel]: Array<callback> }
  // __TEST_IPC_LOG__          : Array<{ cmd, args, time }>
  // __TAURI_FIRE_EVENT__      : (channel, payload) => void  (kept for spec compat)
  window.__TEST_HANDLERS__ = {};
  window.__TEST_EVENT_LISTENERS__ = {};
  window.__TEST_IPC_LOG__ = [];

  // ─── Default responses for all known commands ─────────────────────────────
  var DEFAULTS = {
    // App
    get_app_name: 'Open Recorder',
    // Permissions — default everything to "granted" so startup doesn't stall
    get_screen_recording_permission_status: 'granted',
    get_accessibility_permission_status: 'granted',
    get_microphone_permission_status: 'granted',
    get_camera_permission_status: 'granted',
    request_screen_recording_permission: true,
    request_accessibility_permission: true,
    request_microphone_permission: true,
    request_camera_permission: true,
    open_screen_recording_preferences: null,
    open_accessibility_preferences: null,
    open_microphone_preferences: null,
    open_camera_preferences: null,
    // Updater
    get_updater_state: {
      supported: false,
      dialogOpen: false,
      status: 'idle',
      currentVersion: '0.0.31',
      version: null,
      releaseNotes: null,
      downloadProgress: 0,
      error: null,
    },
    check_for_updates: {
      supported: false,
      dialogOpen: false,
      status: 'idle',
      currentVersion: '0.0.31',
      version: null,
      releaseNotes: null,
      downloadProgress: 0,
      error: null,
    },
    download_update: {
      supported: false,
      dialogOpen: false,
      status: 'idle',
      currentVersion: '0.0.31',
      version: null,
      releaseNotes: null,
      downloadProgress: 0,
      error: null,
    },
    dismiss_updater_dialog: {
      supported: false,
      dialogOpen: false,
      status: 'idle',
      currentVersion: '0.0.31',
      version: null,
      releaseNotes: null,
      downloadProgress: 0,
      error: null,
    },
    // Platform
    get_platform: window.__OPEN_RECORDER_E2E_PLATFORM__ || 'linux',
    get_asset_base_path: '/assets',
    hide_cursor: null,
    open_external_url: null,
    reveal_in_folder: null,
    open_recordings_folder: null,
    // Files
    get_current_video_path: null,
    get_recorded_video_path: null,
    set_current_video_path: null,
    clear_current_video_path: null,
    get_current_screenshot_path: null,
    set_current_screenshot_path: null,
    read_local_file: [],
    prepare_recording_file: '/tmp/test-recording.webm',
    append_recording_data: null,
    replace_recording_data: '/tmp/test-recording.webm',
    delete_recording_file: null,
    store_recording_asset: '/tmp/asset.bin',
    store_recorded_video: '/tmp/test-recording.webm',
    // Recording session
    get_current_recording_session: null,
    set_current_recording_session: null,
    // Settings
    get_recordings_directory: '/home/user/recordings',
    choose_recordings_directory: null,
    get_shortcuts: null,
    save_shortcuts: null,
    // Sources
    get_sources: [],
    get_selected_source: null,
    select_source: null,
    flash_selected_screen: null,
    // Recording
    set_recording_state: null,
    start_native_screen_recording: '/tmp/test-recording.webm',
    stop_native_screen_recording: '/tmp/test-recording.webm',
    start_cursor_telemetry_capture: null,
    stop_cursor_telemetry_capture: null,
    select_screen_area: null,
    // Cursor
    get_cursor_telemetry: [],
    set_cursor_scale: null,
    get_system_cursor_assets: [],
    // Screenshot
    take_screenshot: '/tmp/test-screenshot.png',
    // Window management
    switch_to_editor: null,
    switch_to_image_editor: null,
    open_source_selector: null,
    close_source_selector: null,
    hud_overlay_show: null,
    hud_overlay_hide: null,
    hud_overlay_close: null,
    start_hud_overlay_drag: null,
    set_has_unsaved_changes: null,
    resize_hud_to_onboarding: null,
    restore_hud_size: null,
    // Dialogs
    save_exported_video: null,
    save_screenshot_file: null,
    open_video_file_picker: null,
    save_project_file: '/tmp/test-project.openrec',
    load_project_file: null,
    load_current_project_file: null,
    // Windows-specific
    is_wgc_available: false,
    mux_wgc_recording: '/tmp/test-recording.mp4',
    // Clipboard
    write_clipboard_image: null,
  };

  // ─── electronAPI shim ─────────────────────────────────────────────────────
  window.electronAPI = {
    invoke: async function (channel, args) {
      args = args || {};

      // Log every IPC call for test assertions
      window.__TEST_IPC_LOG__.push({ cmd: channel, args: args, time: Date.now() });

      // Per-test handler overrides
      var handlers = window.__TEST_HANDLERS__ || {};
      if (typeof handlers[channel] === 'function') {
        return handlers[channel](args);
      }

      // Default responses
      if (Object.prototype.hasOwnProperty.call(DEFAULTS, channel)) {
        return DEFAULTS[channel];
      }

      // Unknown command — warn and return null (don't throw)
      console.warn('[electron-shim] Unhandled command:', channel, args);
      return null;
    },

    on: function (channel, callback) {
      if (!window.__TEST_EVENT_LISTENERS__[channel]) {
        window.__TEST_EVENT_LISTENERS__[channel] = [];
      }
      window.__TEST_EVENT_LISTENERS__[channel].push(callback);
      return function () {
        var listeners = window.__TEST_EVENT_LISTENERS__[channel] || [];
        var idx = listeners.indexOf(callback);
        if (idx >= 0) listeners.splice(idx, 1);
      };
    },

    send: function (channel, args) {
      window.__TEST_IPC_LOG__.push({ cmd: channel, args: args || {}, time: Date.now() });
    },
  };

  // ─── Test helper: fire a fake event ──────────────────────────────────────
  window.__TAURI_FIRE_EVENT__ = function (eventName, payload) {
    var listeners = (window.__TEST_EVENT_LISTENERS__ || {})[eventName] || [];
    for (var i = 0; i < listeners.length; i++) {
      listeners[i](payload);
    }
  };

  // ─── Test helper: check if a command was called ───────────────────────────
  window.__IPC_WAS_CALLED__ = function (cmdName) {
    return (window.__TEST_IPC_LOG__ || []).some(function (e) {
      return e.cmd === cmdName;
    });
  };

  // ─── Test helper: get all calls to a command ─────────────────────────────
  window.__IPC_GET_CALLS__ = function (cmdName) {
    return (window.__TEST_IPC_LOG__ || []).filter(function (e) {
      return e.cmd === cmdName;
    });
  };
})();
`;

/**
 * Installs the Electron IPC shim on a Playwright page via addInitScript.
 * Call this BEFORE page.goto() to ensure the shim is ready when the app boots.
 */
export async function installTauriShim(page: import("@playwright/test").Page): Promise<void> {
	const platform = process.env.OPEN_RECORDER_E2E_PLATFORM ?? "linux";
	await page.addInitScript((value) => {
		// biome-ignore lint/suspicious/noExplicitAny: test shim
		(window as any).__OPEN_RECORDER_E2E_PLATFORM__ = value;
	}, platform);
	await page.addInitScript({ content: ELECTRON_SHIM_SCRIPT });
}

/**
 * Installs deterministic capture primitives for renderer-only recording tests.
 * The app still exercises its real recording state machine and IPC calls, while
 * the browser media APIs are kept stable on headless macOS/Windows/Linux CI.
 */
export async function installMediaCaptureShim(
	page: import("@playwright/test").Page,
): Promise<void> {
	await page.addInitScript(() => {
		// biome-ignore lint/suspicious/noExplicitAny: test shim
		const target = window as any;
		target.__TEST_MEDIA_LOG__ = [];

		const makeStream = () => {
			const canvas = document.createElement("canvas");
			canvas.width = 640;
			canvas.height = 360;
			const context = canvas.getContext("2d");
			context!.fillStyle = "#1d4ed8";
			context!.fillRect(0, 0, canvas.width, canvas.height);
			context!.fillStyle = "#ffffff";
			context!.fillRect(24, 24, 160, 90);
			return canvas.captureStream(30);
		};

		class TestMediaRecorder {
			ondataavailable: ((event: { data: Blob }) => void) | null = null;
			onstop: (() => Promise<void> | void) | null = null;
			onerror: (() => void) | null = null;
			state: "inactive" | "recording" = "inactive";

			constructor(
				public stream: MediaStream,
				public options?: MediaRecorderOptions,
			) {
				target.__TEST_MEDIA_LOG__.push({
					cmd: "MediaRecorder.constructor",
					options,
					tracks: stream.getTracks().map((track) => track.kind),
				});
			}

			start(timeslice?: number) {
				this.state = "recording";
				target.__TEST_MEDIA_LOG__.push({ cmd: "MediaRecorder.start", timeslice });
			}

			stop() {
				this.state = "inactive";
				target.__TEST_MEDIA_LOG__.push({ cmd: "MediaRecorder.stop" });
				const blob = new Blob(["open-recorder-test-data"], {
					type: this.options?.mimeType ?? "video/webm",
				});
				this.ondataavailable?.({ data: blob });
				queueMicrotask(() => {
					void this.onstop?.();
				});
			}

			static isTypeSupported(type: string) {
				return type.startsWith("video/webm");
			}
		}

		target.MediaRecorder = TestMediaRecorder;

		const mediaDevices = navigator.mediaDevices ?? {};
		Object.defineProperty(navigator, "mediaDevices", {
			configurable: true,
			value: {
				...mediaDevices,
				getDisplayMedia: async (constraints?: DisplayMediaStreamOptions) => {
					target.__TEST_MEDIA_LOG__.push({ cmd: "getDisplayMedia", constraints });
					return makeStream();
				},
				getUserMedia: async (constraints?: MediaStreamConstraints) => {
					target.__TEST_MEDIA_LOG__.push({ cmd: "getUserMedia", constraints });
					return makeStream();
				},
				enumerateDevices: async () => [],
			},
		});
	});
}

/**
 * Pre-configures command handlers as an init script (runs before page JS).
 * Values must be JSON-serializable. Each handler returns the value statically.
 */
export async function configureHandlers(
	page: import("@playwright/test").Page,
	handlers: Record<string, unknown>,
): Promise<void> {
	await page.addInitScript((h) => {
		for (const [cmd, val] of Object.entries(h)) {
			// biome-ignore lint/suspicious/noExplicitAny: test shim
			(window as any).__TEST_HANDLERS__[cmd] = () => val;
		}
	}, handlers);
}

/**
 * Configures the get_sources handler to return different sources depending on
 * whether the call is requesting screen sources or window sources.
 */
export async function configureSourceHandlers(
	page: import("@playwright/test").Page,
	{
		screenSources,
		windowSources,
	}: {
		screenSources: unknown[];
		windowSources: unknown[];
	},
): Promise<void> {
	await page.addInitScript(
		({ screens, windows }) => {
			// biome-ignore lint/suspicious/noExplicitAny: test shim
			(window as any).__TEST_HANDLERS__.get_sources = (args: { opts?: { types?: string[] } }) => {
				const types = (args.opts && args.opts.types) || [];
				if (types.indexOf("window") >= 0) return windows;
				return screens;
			};
		},
		{ screens: screenSources, windows: windowSources },
	);
}

/**
 * Pre-sets localStorage items as an init script (runs before page JS).
 */
export async function setLocalStorage(
	page: import("@playwright/test").Page,
	items: Record<string, string>,
): Promise<void> {
	await page.addInitScript((kv) => {
		for (const [key, value] of Object.entries(kv)) {
			localStorage.setItem(key, value);
		}
	}, items);
}
