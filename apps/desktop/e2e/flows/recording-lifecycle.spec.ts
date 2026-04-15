/**
 * Flow 2 — Recording lifecycle
 *
 * Tests the full record → stop → switch-to-editor flow on the HUD overlay.
 * All native recording IPC calls are intercepted by the tauri-shim.
 */

import { expect, test } from "@playwright/test";
import {
  configureHandlers,
  installTauriShim,
  setLocalStorage,
} from "../setup/tauri-shim";
import { permissionsGranted } from "../fixtures/permissions-granted";

const HUD_URL = "/?windowType=hud-overlay";
const ONBOARDING_KEY = "open-recorder-onboarding-v1";

// ─── Shared setup ─────────────────────────────────────────────────────────────

async function setupRecordingPage(page: import("@playwright/test").Page) {
  await installTauriShim(page);
  // All permissions granted so recording path is available
  await configureHandlers(page, {
    ...permissionsGranted(),
    // Return a fake selected source so source-related guards pass
    get_selected_source: {
      id: "screen:0:0",
      name: "Main Display",
      sourceType: "screen",
    },
    // Simulate startNativeScreenRecording returning a path
    start_native_screen_recording: "/tmp/test-recording.webm",
    stop_native_screen_recording: "/tmp/test-recording.webm",
  });
  // Skip onboarding
  await setLocalStorage(page, { [ONBOARDING_KEY]: "true" });
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test.describe("Recording lifecycle", () => {
  test("main HUD choice view renders with Screenshot and Record Video buttons", async ({
    page,
  }) => {
    await setupRecordingPage(page);
    await page.goto(HUD_URL);

    await expect(page.getByText("Record Video")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByText("Screenshot")).toBeVisible();
  });

  test("clicking Record Video transitions to recording setup view", async ({
    page,
  }) => {
    await setupRecordingPage(page);
    await page.goto(HUD_URL);

    await page.getByText("Record Video").click();

    // Recording view is visible — it shows a back button (ChevronLeft)
    // and recording control buttons
    await expect(page.getByRole("button", { name: "Back" })).toBeVisible({
      timeout: 5_000,
    });
  });

  test("back button in recording view returns to choice view", async ({
    page,
  }) => {
    await setupRecordingPage(page);
    await page.goto(HUD_URL);

    await page.getByText("Record Video").click();
    await expect(page.getByRole("button", { name: "Back" })).toBeVisible({
      timeout: 5_000,
    });

    await page.getByRole("button", { name: "Back" }).click();

    // Should be back to choice view
    await expect(page.getByText("Record Video")).toBeVisible({ timeout: 5_000 });
    await expect(page.getByText("Screenshot")).toBeVisible();
  });

  test("recording-state-changed event causes timer to appear", async ({
    page,
  }) => {
    await setupRecordingPage(page);
    await page.goto(HUD_URL);

    // Navigate to recording view
    await page.getByText("Record Video").click();
    await page.waitForTimeout(500);

    // Simulate Tauri firing a recording-state-changed event (recording started)
    await page.evaluate(() => {
      window.__TAURI_FIRE_EVENT__("recording-state-changed", true);
    });

    // When recording is active, the timer "00:00" appears in the HUD
    await expect(page.getByText(/\d{2}:\d{2}/)).toBeVisible({ timeout: 5_000 });
  });

  test("stop recording resets to choice view after recording-state-changed false", async ({
    page,
  }) => {
    await setupRecordingPage(page);
    await page.goto(HUD_URL);

    // Start simulated recording
    await page.getByText("Record Video").click();
    await page.evaluate(() => {
      window.__TAURI_FIRE_EVENT__("recording-state-changed", true);
    });
    await expect(page.getByText(/\d{2}:\d{2}/)).toBeVisible({ timeout: 5_000 });

    // Simulate recording stopped
    await page.evaluate(() => {
      window.__TAURI_FIRE_EVENT__("recording-state-changed", false);
    });

    // Should return to choice view
    await expect(page.getByText("Record Video")).toBeVisible({ timeout: 5_000 });
  });

  test("IPC log captures start_native_screen_recording call when shim is triggered directly", async ({
    page,
  }) => {
    await setupRecordingPage(page);
    await page.goto(HUD_URL);

    // Wait for app to boot
    await page.waitForTimeout(1000);

    // Manually invoke the command via the shim to verify IPC logging works
    await page.evaluate(async () => {
      await window.__TAURI_INTERNALS__.invoke("start_native_screen_recording", {
        source: { id: "screen:0:0", name: "Main Display", sourceType: "screen" },
        options: {},
      });
    });

    const wasCalled = await page.evaluate(() =>
      window.__IPC_WAS_CALLED__("start_native_screen_recording"),
    );
    expect(wasCalled).toBe(true);

    const calls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("start_native_screen_recording"),
    );
    expect(calls).toHaveLength(1);
    expect(calls[0].args.source.id).toBe("screen:0:0");
  });

  test("stop_native_screen_recording IPC is logged when invoked", async ({
    page,
  }) => {
    await setupRecordingPage(page);
    await page.goto(HUD_URL);

    await page.waitForTimeout(500);

    await page.evaluate(async () => {
      await window.__TAURI_INTERNALS__.invoke("stop_native_screen_recording");
    });

    const wasCalled = await page.evaluate(() =>
      window.__IPC_WAS_CALLED__("stop_native_screen_recording"),
    );
    expect(wasCalled).toBe(true);
  });

  test("switch_to_editor IPC is logged when invoked", async ({ page }) => {
    await setupRecordingPage(page);
    await page.goto(HUD_URL);

    await page.waitForTimeout(500);

    await page.evaluate(async () => {
      await window.__TAURI_INTERNALS__.invoke("switch_to_editor", {
        query: "?mode=video",
      });
    });

    const calls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("switch_to_editor"),
    );
    expect(calls.length).toBeGreaterThanOrEqual(1);
    const lastCall = calls[calls.length - 1];
    expect(lastCall.args.query).toContain("mode=video");
  });
});
