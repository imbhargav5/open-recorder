/**
 * Smoke — Native recording (Electron full-app, macOS CI)
 *
 * These tests require a fully packaged Electron binary. They are skipped in
 * the standard Playwright-only CI environment that runs against the Vite dev
 * server with the Electron IPC shim.
 *
 * To run locally:
 *   1. Build and package the app: pnpm build:dist
 *   2. Set ELECTRON_APP=1: ELECTRON_APP=1 pnpm e2e --config e2e/playwright.config.ts
 *
 * These tests exist as a placeholder for future native E2E coverage once
 * full Electron app testing is wired into the macOS CI pipeline.
 */

import { test } from "@playwright/test";

const NEEDS_ELECTRON_APP = !process.env.ELECTRON_APP;

test.describe("Native recording smoke tests (Electron full-app only)", () => {
  test.skip(
    NEEDS_ELECTRON_APP,
    "Requires ELECTRON_APP=1 env var and a packaged Electron binary",
  );

  test("placeholder: start and stop a native recording session", async () => {
    // TODO: implement using Playwright Electron launch
    // Steps would be:
    // 1. Launch Electron app via playwright.electron.launch()
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
