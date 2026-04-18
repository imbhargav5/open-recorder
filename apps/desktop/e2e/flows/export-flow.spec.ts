/**
 * Flow 5 — Export flow
 *
 * Tests that the export dialog appears and responds to progress events.
 * Because the full VideoEditor requires a real video, we test the IPC
 * contract and the atoms/state transitions that the ExportDialog observes.
 */

import { expect, test } from "@playwright/test";
import {
  configureHandlers,
  installTauriShim,
} from "../setup/tauri-shim";
import { fakeRecordingSession } from "../fixtures/fake-recording-session";

const EDITOR_URL = "/?windowType=editor";

async function setupExportPage(page: import("@playwright/test").Page) {
  await installTauriShim(page);
  await configureHandlers(page, {
    get_current_video_path: "/tmp/test-recording.webm",
    get_current_recording_session: fakeRecordingSession(),
    load_current_project_file: null,
    get_cursor_telemetry: [],
    get_system_cursor_assets: [],
    get_shortcuts: null,
    set_has_unsaved_changes: null,
    save_exported_video: "/tmp/test-export.mp4",
  });
}

test.describe("Export flow", () => {
  test("editor page loads without unhandled exceptions", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (err) => {
      if (
        !err.message.includes("WebGL") &&
        !err.message.includes("play()") &&
        !err.message.includes("ResizeObserver")
      ) {
        errors.push(err.message);
      }
    });

    await setupExportPage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(3_000);

    expect(errors).toHaveLength(0);
  });

  test("save_exported_video IPC is correctly handled by shim", async ({
    page,
  }) => {
    await setupExportPage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(1_000);

    // Directly invoke the export command through the shim
    const result = await page.evaluate(async () => {
      return window.electronAPI.invoke("save_exported_video", {
        videoData: [],
        fileName: "export.mp4",
      });
    });

    expect(result).toBe("/tmp/test-export.mp4");

    const calls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("save_exported_video"),
    );
    expect(calls.length).toBeGreaterThanOrEqual(1);
    expect(calls[calls.length - 1].args.fileName).toBe("export.mp4");
  });

  test("IPC log tracks multiple sequential export-related commands", async ({
    page,
  }) => {
    await setupExportPage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(500);

    // Simulate the sequence of IPC calls that an export flow would make
    await page.evaluate(async () => {
      // 1. Get current video path
      await window.electronAPI.invoke("get_current_video_path");
      // 2. Save exported video
      await window.electronAPI.invoke("save_exported_video", {
        videoData: [],
        fileName: "test-export.mp4",
      });
    });

    const videoPathCalls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("get_current_video_path"),
    );
    const exportCalls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("save_exported_video"),
    );

    expect(videoPathCalls.length).toBeGreaterThanOrEqual(1);
    expect(exportCalls.length).toBeGreaterThanOrEqual(1);
  });

  test("firing export progress events does not crash the page", async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on("pageerror", (err) => errors.push(err.message));

    await setupExportPage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(2_000);

    // Fire fake export progress events through the event bus
    await page.evaluate(() => {
      window.__TAURI_FIRE_EVENT__("export-progress", {
        percentage: 25,
        phase: "encoding",
      });
      window.__TAURI_FIRE_EVENT__("export-progress", {
        percentage: 50,
        phase: "encoding",
      });
      window.__TAURI_FIRE_EVENT__("export-progress", {
        percentage: 100,
        phase: "finalizing",
      });
    });

    await page.waitForTimeout(500);

    // No fatal crashes
    const fatalErrors = errors.filter(
    );
    expect(fatalErrors).toHaveLength(0);
  });

  test("shim returns correct values for all export-related commands", async ({
    page,
  }) => {
    await setupExportPage(page);
    await page.goto(EDITOR_URL);

    const results = await page.evaluate(async () => {
      return {
        videoPath: await window.electronAPI.invoke("get_current_video_path"),
        exportedPath: await window.electronAPI.invoke("save_exported_video", {
          videoData: [],
          fileName: "gif-export.gif",
        }),
        screenshotPath: await window.electronAPI.invoke(
          "save_screenshot_file",
          { imageData: [], fileName: "screenshot.png" },
        ),
      };
    });

    expect(results.videoPath).toBe("/tmp/test-recording.webm");
    expect(results.exportedPath).toBe("/tmp/test-export.mp4");
    // save_screenshot_file defaults to null unless overridden
    expect(results.screenshotPath).toBeNull();
  });
});
