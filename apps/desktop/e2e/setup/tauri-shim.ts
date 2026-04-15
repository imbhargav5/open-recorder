/**
 * Tauri IPC shim for Playwright E2E tests.
 *
 * In Tauri v2 all invoke() calls go through window.__TAURI_INTERNALS__.invoke()
 * and listen() calls go through invoke('plugin:event|listen', ...).
 * This shim installs a complete fake of that interface so the React app can
 * initialise and run inside a plain Chromium window without any native binary.
 *
 * Usage (in every test):
 *   await page.addInitScript({ content: TAURI_SHIM_SCRIPT });
 *   // optionally configure per-test handlers BEFORE navigation
 *   await page.addInitScript((handlers) => {
 *     for (const [cmd, val] of Object.entries(handlers)) {
 *       window.__TEST_HANDLERS__[cmd] = () => val;
 *     }
 *   }, handlerMap);
 *   await page.goto('/?windowType=hud-overlay');
 */

export const TAURI_SHIM_SCRIPT = /* javascript */ `
(function () {
  if (window.__TAURI_INTERNALS__) return; // guard against double-injection

  // ─── Callback registry ──────────────────────────────────────────────────────
  let _nextId = 0;

  // ─── Public test surfaces ────────────────────────────────────────────────────
  // __TEST_HANDLERS__    : { [cmdName]: (args) => returnValue }
  // __TEST_EVENT_LISTENERS__ : { [eventName]: Array<{ handlerId: number }> }
  // __TEST_IPC_LOG__     : Array<{ cmd, args, time }>
  // __TAURI_FIRE_EVENT__ : (eventName, payload) => void
  window.__TEST_HANDLERS__ = {};
  window.__TEST_EVENT_LISTENERS__ = {};
  window.__TEST_IPC_LOG__ = [];

  // ─── Default responses for all known commands ─────────────────────────────
  const DEFAULTS = {
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
    // Platform
    get_platform: 'linux',
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
  };

  // ─── __TAURI_INTERNALS__ shim ─────────────────────────────────────────────
  window.__TAURI_INTERNALS__ = {
    metadata: {
      currentWindow: { label: 'main' },
      currentWebview: { label: 'main', windowLabel: 'main' },
    },

    transformCallback: function (callback, once) {
      var id = ++_nextId;
      var key = '_' + id;
      if (once) {
        window[key] = function () {
          callback.apply(this, arguments);
          delete window[key];
        };
      } else {
        window[key] = callback;
      }
      return id;
    },

    unregisterCallback: function (id) {
      delete window['_' + id];
    },

    invoke: async function (cmd, args) {
      args = args || {};

      // Log every IPC call for test assertions
      window.__TEST_IPC_LOG__.push({ cmd: cmd, args: args, time: Date.now() });

      // ── Event plugin ──────────────────────────────────────────────────────
      if (cmd === 'plugin:event|listen') {
        var event = args.event;
        var handlerId = args.handler;
        if (!window.__TEST_EVENT_LISTENERS__[event]) {
          window.__TEST_EVENT_LISTENERS__[event] = [];
        }
        window.__TEST_EVENT_LISTENERS__[event].push({ handlerId: handlerId });
        return handlerId; // eventId == handlerId in shim
      }
      if (cmd === 'plugin:event|unlisten') {
        var evName = args.event;
        var evId = args.eventId;
        if (window.__TEST_EVENT_LISTENERS__[evName]) {
          window.__TEST_EVENT_LISTENERS__[evName] = window.__TEST_EVENT_LISTENERS__[evName]
            .filter(function (l) { return l.handlerId !== evId; });
        }
        return null;
      }
      if (cmd === 'plugin:event|emit') return null;

      // ── App plugin ────────────────────────────────────────────────────────
      if (cmd === 'plugin:app|name') return 'Open Recorder';
      if (cmd === 'plugin:app|version') return '0.0.21';
      if (cmd === 'plugin:app|tauri_version') return '2.0.0';

      // ── Window/webview plugins (all no-ops) ───────────────────────────────
      if (
        cmd.startsWith('plugin:window|') ||
        cmd.startsWith('plugin:webview|') ||
        cmd.startsWith('plugin:os|') ||
        cmd.startsWith('plugin:updater|') ||
        cmd.startsWith('plugin:global-shortcut|') ||
        cmd.startsWith('plugin:notification|') ||
        cmd.startsWith('plugin:process|') ||
        cmd.startsWith('plugin:shell|') ||
        cmd.startsWith('plugin:fs|') ||
        cmd.startsWith('plugin:dialog|') ||
        cmd.startsWith('plugin:clipboard-manager|') ||
        cmd.startsWith('plugin:resources|')
      ) {
        // Return sensible defaults for specific queries
        if (cmd === 'plugin:window|primary_monitor') {
          return {
            name: 'main',
            size: { width: 1920, height: 1080 },
            position: { x: 0, y: 0 },
            scaleFactor: 1,
          };
        }
        return null;
      }

      // ── Per-test handler overrides ────────────────────────────────────────
      var handlers = window.__TEST_HANDLERS__ || {};
      if (typeof handlers[cmd] === 'function') {
        return handlers[cmd](args);
      }

      // ── Default responses ─────────────────────────────────────────────────
      if (Object.prototype.hasOwnProperty.call(DEFAULTS, cmd)) {
        return DEFAULTS[cmd];
      }

      // Unknown command — warn and return null (don't throw)
      console.warn('[tauri-shim] Unhandled command:', cmd, args);
      return null;
    },

    convertFileSrc: function (filePath, protocol) {
      // Return a URL that the browser will not reject, but that won't load any real file
      return 'data:text/plain,' + encodeURIComponent(filePath || '');
    },
  };

  // ─── Event plugin internals (used by _unlisten) ───────────────────────────
  window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
    unregisterListener: function (event, eventId) {
      if (window.__TEST_EVENT_LISTENERS__[event]) {
        window.__TEST_EVENT_LISTENERS__[event] = window.__TEST_EVENT_LISTENERS__[event]
          .filter(function (l) { return l.handlerId !== eventId; });
      }
    },
  };

  // ─── Test helper: fire a fake Tauri event ─────────────────────────────────
  window.__TAURI_FIRE_EVENT__ = function (eventName, payload) {
    var listeners = (window.__TEST_EVENT_LISTENERS__ || {})[eventName] || [];
    for (var i = 0; i < listeners.length; i++) {
      var fn = window['_' + listeners[i].handlerId];
      if (typeof fn === 'function') {
        fn({
          event: eventName,
          payload: payload,
          id: listeners[i].handlerId,
          windowLabel: 'main',
        });
      }
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
 * Installs the Tauri IPC shim on a Playwright page via addInitScript.
 * Call this BEFORE page.goto() to ensure the shim is ready when the app boots.
 */
export async function installTauriShim(
  page: import("@playwright/test").Page,
): Promise<void> {
  await page.addInitScript({ content: TAURI_SHIM_SCRIPT });
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
 * This avoids strict-mode violations when both screen and window calls
 * return the same static list.
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
      (window as any).__TEST_HANDLERS__.get_sources = (args: {
        opts?: { types?: string[] };
      }) => {
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
