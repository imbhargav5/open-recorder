/**
 * Smoke — Native recording (tauri-driver only, macOS CI)
 *
 * These tests require a real Tauri native binary and tauri-driver, which are
 * not available in the standard Playwright-only CI environment.
 *
 * All tests in this file are skipped by default. To run them locally:
 *   1. Build the app: pnpm build
 *   2. Start tauri-driver: tauri-driver
 *   3. Run with TAURI_DRIVER=1: TAURI_DRIVER=1 pnpm e2e --config e2e/playwright.config.ts
 *
 * These tests exist as a placeholder for future native E2E coverage once
 * tauri-driver support is wired into the macOS CI pipeline.
 */

import { test } from "@playwright/test";

const NEEDS_TAURI_DRIVER = !process.env.TAURI_DRIVER;

test.describe("Native recording smoke tests (tauri-driver only)", () => {
  test.skip(
    NEEDS_TAURI_DRIVER,
    "Requires TAURI_DRIVER=1 env var and a running tauri-driver process",
  );

  test("placeholder: start and stop a native recording session", async () => {
    // TODO: implement using tauri-driver WebDriver session
    // Steps would be:
    // 1. Connect to tauri-driver WebDriver endpoint
    // 2. Click Record button
    // 3. Verify native recording starts (OS-level screen capture)
    // 4. Click Stop
    // 5. Verify .webm file is created on disk
  });

  test("placeholder: native recording produces a valid WebM file", async () => {
    // TODO: verify output file is a valid WebM with correct metadata
  });

  test("placeholder: cursor telemetry is captured during native recording", async () => {
    // TODO: verify cursor telemetry JSON is written alongside the recording
  });
});
