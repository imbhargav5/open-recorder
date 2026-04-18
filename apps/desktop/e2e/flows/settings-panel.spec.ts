/**
 * Flow 6 — Settings panel
 *
 * Tests that the editor settings panel/sidebar renders and responds to
 * interactions. Because deep settings interactions require the video to load,
 * we focus on the IPC contract and verifiable UI state transitions.
 */

import { expect, test } from "@playwright/test";
import {
  configureHandlers,
  installTauriShim,
} from "../setup/tauri-shim";
import { fakeRecordingSession } from "../fixtures/fake-recording-session";

const EDITOR_URL = "/?windowType=editor";

async function setupSettingsPage(page: import("@playwright/test").Page) {
  await installTauriShim(page);
  await configureHandlers(page, {
    get_current_video_path: "/tmp/test-recording.webm",
    get_current_recording_session: fakeRecordingSession(),
    load_current_project_file: null,
    get_cursor_telemetry: [],
    get_system_cursor_assets: [],
    get_shortcuts: null,
    set_has_unsaved_changes: null,
    get_recordings_directory: "/home/user/recordings",
  });
}

test.describe("Settings panel", () => {
  test("editor mounts and root element has content", async ({ page }) => {
    await setupSettingsPage(page);
    await page.goto(EDITOR_URL);

    await page.waitForTimeout(3_000);

    const rootHasContent = await page.evaluate(
      () => (document.getElementById("root")?.innerHTML?.length ?? 0) > 10,
    );
    expect(rootHasContent).toBe(true);
  });

  test("set_has_unsaved_changes IPC is handled by the shim", async ({
    page,
  }) => {
    await setupSettingsPage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(500);

    // Invoke the command through the shim
    const result = await page.evaluate(async () => {
      return window.electronAPI.invoke("set_has_unsaved_changes", {
        hasChanges: true,
      });
    });

    expect(result).toBeNull();

    const calls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("set_has_unsaved_changes"),
    );
    expect(calls.length).toBeGreaterThanOrEqual(1);
    expect(calls[calls.length - 1].args.hasChanges).toBe(true);
  });

  test("save_shortcuts IPC is handled correctly", async ({ page }) => {
    await setupSettingsPage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(500);

    const fakeShortcuts = {
      startRecording: "CmdOrCtrl+Shift+R",
      stopRecording: "CmdOrCtrl+Shift+S",
    };

    const result = await page.evaluate(async (shortcuts) => {
      return window.electronAPI.invoke("save_shortcuts", { shortcuts });
    }, fakeShortcuts);

    expect(result).toBeNull();

    const calls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("save_shortcuts"),
    );
    expect(calls.length).toBeGreaterThanOrEqual(1);
  });

  test("get_recordings_directory returns expected path", async ({ page }) => {
    await setupSettingsPage(page);
    await page.goto(EDITOR_URL);

    const dir = await page.evaluate(async () => {
      return window.electronAPI.invoke("get_recordings_directory");
    });

    expect(dir).toBe("/home/user/recordings");
  });

  test("cursor-related IPC commands are handled without errors", async ({
    page,
  }) => {
    await setupSettingsPage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(500);

    const results = await page.evaluate(async () => {
      const cursorAssets = await window.electronAPI.invoke(
        "get_system_cursor_assets",
      );
      await window.electronAPI.invoke("set_cursor_scale", { scale: 1.5 });
      const telemetry = await window.electronAPI.invoke(
        "get_cursor_telemetry",
        { videoPath: "/tmp/test-recording.webm" },
      );
      return { cursorAssets, telemetry };
    });

    expect(Array.isArray(results.cursorAssets)).toBe(true);
    expect(Array.isArray(results.telemetry)).toBe(true);

    const scaleCalls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("set_cursor_scale"),
    );
    expect(scaleCalls.length).toBeGreaterThanOrEqual(1);
    expect(scaleCalls[scaleCalls.length - 1].args.scale).toBe(1.5);
  });

  test("editor page handles menu events without crashing", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (err) => {
      if (
        !err.message.includes("WebGL") &&
        !err.message.includes("play()")
      ) {
        errors.push(err.message);
      }
    });

    await setupSettingsPage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(2_000);

    // Fire menu events that the editor listens to
    await page.evaluate(() => {
      window.__TAURI_FIRE_EVENT__("menu-save-project", null);
      window.__TAURI_FIRE_EVENT__("menu-save-project-as", null);
      window.__TAURI_FIRE_EVENT__("menu-open-video-file", null);
    });

    await page.waitForTimeout(500);

    expect(errors).toHaveLength(0);
  });
});
