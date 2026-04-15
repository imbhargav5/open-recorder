/**
 * Flow 1 — Onboarding
 *
 * Tests the first-launch permission onboarding flow that appears when
 * `open-recorder-onboarding-v1` is absent from localStorage.
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

test.describe("Onboarding flow", () => {
  test.beforeEach(async ({ page }) => {
    // Install IPC shim before any app JavaScript runs
    await installTauriShim(page);
  });

  test("shows PermissionOnboarding welcome step when localStorage key is absent", async ({
    page,
  }) => {
    // DO NOT set the onboarding key — app should show onboarding
    await configureHandlers(page, {
      get_screen_recording_permission_status: "not_determined",
      get_microphone_permission_status: "not_determined",
      get_camera_permission_status: "granted",
      get_accessibility_permission_status: "granted",
    });

    await page.goto(HUD_URL);

    // The welcome step renders "Welcome to Open Recorder"
    await expect(page.getByText("Welcome to Open Recorder")).toBeVisible({
      timeout: 10_000,
    });
    // The first action button on the welcome step
    await expect(page.getByRole("button", { name: "Get Started" })).toBeVisible();
  });

  test("does NOT show onboarding when localStorage key is already set", async ({
    page,
  }) => {
    await setLocalStorage(page, { [ONBOARDING_KEY]: "true" });
    await configureHandlers(page, permissionsGranted());

    await page.goto(HUD_URL);

    // The main HUD choice view shows "Screenshot" and "Record Video"
    await expect(page.getByText("Record Video")).toBeVisible({ timeout: 10_000 });
    // Onboarding welcome text must NOT be present
    await expect(page.getByText("Welcome to Open Recorder")).not.toBeVisible();
  });

  test("advances through welcome step and gets closer to completion", async ({
    page,
  }) => {
    // No onboarding key → should show onboarding
    await configureHandlers(page, {
      get_screen_recording_permission_status: "granted",
      get_microphone_permission_status: "granted",
      get_camera_permission_status: "granted",
      get_accessibility_permission_status: "granted",
      request_screen_recording_permission: true,
      request_microphone_permission: true,
      request_camera_permission: true,
    });

    await page.goto(HUD_URL);

    // Welcome step should be visible
    await expect(page.getByText("Welcome to Open Recorder")).toBeVisible({
      timeout: 10_000,
    });

    // Click "Get Started" to advance to next step
    await page.getByRole("button", { name: "Get Started" }).click();

    // After advancing from welcome, the step dot indicator changes
    // and we should no longer see the welcome heading
    // (the next step shows a permission step or "You're All Set!" on Linux
    //  since isMacOS is false and screen-recording step is skipped)
    await expect(page.getByText("Welcome to Open Recorder")).not.toBeVisible({
      timeout: 5_000,
    });
  });

  test("completes onboarding and writes key to localStorage", async ({ page }) => {
    await configureHandlers(page, {
      get_screen_recording_permission_status: "granted",
      get_microphone_permission_status: "granted",
      get_camera_permission_status: "granted",
      get_accessibility_permission_status: "granted",
      request_screen_recording_permission: true,
      request_microphone_permission: true,
      request_camera_permission: true,
    });

    await page.goto(HUD_URL);

    // Welcome step
    await expect(page.getByText("Welcome to Open Recorder")).toBeVisible({
      timeout: 10_000,
    });
    await page.getByRole("button", { name: "Get Started" }).click();

    // On Linux (isMacOS=false) the steps are: welcome → microphone → camera → done
    // Click through permission steps using "Continue" or "Skip" buttons
    // Keep clicking the primary action button until we reach the "done" step
    for (let i = 0; i < 5; i++) {
      const startRecording = page.getByRole("button", {
        name: "Start Recording",
      });
      if (await startRecording.isVisible()) {
        // We're on the "done" step — click to complete onboarding
        await startRecording.click();
        break;
      }

      // Advance through permission step
      const continueBtn = page.getByRole("button", { name: /continue|skip|next/i });
      if (await continueBtn.isVisible()) {
        await continueBtn.click();
        await page.waitForTimeout(200);
      }
    }

    // After completion, the localStorage key should be set
    const key = await page.evaluate(
      (k) => localStorage.getItem(k),
      ONBOARDING_KEY,
    );
    expect(key).toBe("true");
  });

  test("shows main HUD view after onboarding is completed", async ({ page }) => {
    await configureHandlers(page, permissionsGranted());
    // Start with no onboarding key
    await page.goto(HUD_URL);

    // Should see onboarding first
    await expect(page.getByText("Welcome to Open Recorder")).toBeVisible({
      timeout: 10_000,
    });

    // Programmatically complete onboarding by setting localStorage
    // and triggering a page reload (simulating returning user)
    await page.evaluate(
      ([k]) => localStorage.setItem(k, "true"),
      [ONBOARDING_KEY],
    );
    await page.reload();

    // After reload with key set, main HUD (choice view) should appear
    await expect(page.getByText("Record Video")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByText("Screenshot")).toBeVisible();
  });
});
