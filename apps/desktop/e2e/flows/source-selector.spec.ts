/**
 * Flow 3 — Source Selector
 *
 * Tests the /?windowType=source-selector window:
 *  - Loading spinner while getSources is pending
 *  - Screens tab renders screen thumbnails
 *  - Windows tab renders window list
 *  - Selecting a source and sharing calls the correct IPC commands
 */

import { expect, test } from "@playwright/test";
import {
  configureHandlers,
  configureSourceHandlers,
  installTauriShim,
} from "../setup/tauri-shim";
import {
  fakeScreenSources,
  fakeWindowSources,
} from "../fixtures/fake-sources";

const SOURCE_SELECTOR_URL = "/?windowType=source-selector";

test.describe("Source Selector", () => {
  test.beforeEach(async ({ page }) => {
    await installTauriShim(page);
  });

  test("renders 'Choose what to share' heading", async ({ page }) => {
    await configureHandlers(page, { get_sources: [] });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });
  });

  test("Screens tab is visible by default", async ({ page }) => {
    await configureSourceHandlers(page, {
      screenSources: fakeScreenSources(),
      windowSources: fakeWindowSources(),
    });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByRole("tab", { name: /screens/i })).toBeVisible();
  });

  test("Windows tab is visible", async ({ page }) => {
    await configureSourceHandlers(page, {
      screenSources: fakeScreenSources(),
      windowSources: fakeWindowSources(),
    });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByRole("tab", { name: /windows/i })).toBeVisible();
  });

  test("screen sources appear as buttons after getSources resolves", async ({
    page,
  }) => {
    // Use type-aware handler so getSources({types:["window"]}) doesn't
    // return screen sources and cause strict-mode duplicate text violations.
    await configureSourceHandlers(page, {
      screenSources: fakeScreenSources(),
      windowSources: [],
    });
    await page.goto(SOURCE_SELECTOR_URL);

    // Wait for the heading (means loading is done)
    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });

    // The Screens tab content should list our fake screen names
    // Use .first() to be resilient if the same name appears in both tabs
    await expect(page.getByText("Main Display").first()).toBeVisible({
      timeout: 8_000,
    });
    await expect(page.getByText("External Monitor").first()).toBeVisible({
      timeout: 5_000,
    });
  });

  test("clicking Windows tab switches to window list", async ({ page }) => {
    await configureSourceHandlers(page, {
      screenSources: fakeScreenSources(),
      windowSources: fakeWindowSources(),
    });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });

    // Click the Windows tab
    await page.getByRole("tab", { name: /windows/i }).click();

    // Window sources should now be visible
    await expect(page.getByText("Google Chrome")).toBeVisible({
      timeout: 5_000,
    });
    await expect(page.getByText("Visual Studio Code")).toBeVisible({
      timeout: 5_000,
    });
  });

  test("clicking a source enables the Share Source button", async ({ page }) => {
    // Use type-aware handler to prevent duplicate text in both tabs
    await configureSourceHandlers(page, {
      screenSources: fakeScreenSources(),
      windowSources: [],
    });
    await configureHandlers(page, { select_source: null });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByText("Main Display").first()).toBeVisible({
      timeout: 8_000,
    });

    // Share Source button is disabled before selection
    const shareBtn = page.getByRole("button", { name: "Share Source" });
    await expect(shareBtn).toBeDisabled();

    // Click on a source — use first() to handle strict mode
    await page.getByText("Main Display").first().click();

    // Share Source button should now be enabled
    await expect(shareBtn).toBeEnabled({ timeout: 3_000 });
  });

  test("clicking Share Source calls select_source with the selected source id", async ({
    page,
  }) => {
    await configureSourceHandlers(page, {
      screenSources: fakeScreenSources(),
      windowSources: [],
    });
    await configureHandlers(page, { select_source: null });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByText("Main Display").first()).toBeVisible({
      timeout: 8_000,
    });

    // Select the first screen source
    await page.getByText("Main Display").first().click();

    // Click Share Source
    await page.getByRole("button", { name: "Share Source" }).click();

    // Verify select_source was called
    await page.waitForTimeout(500);
    const calls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("select_source"),
    );
    expect(calls.length).toBeGreaterThanOrEqual(1);
    const lastCall = calls[calls.length - 1];
    expect(lastCall.args.source.id).toBe("screen:0:0");
  });

  test("Cancel button is visible in source selector", async ({ page }) => {
    await configureHandlers(page, { get_sources: fakeScreenSources() });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });

    await expect(page.getByRole("button", { name: "Cancel" })).toBeVisible();
  });

  test("empty state message shows when no sources are available", async ({
    page,
  }) => {
    await configureHandlers(page, { get_sources: [] });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });

    // The empty state renders the "No screens available" message
    await expect(page.getByText(/no screens available/i)).toBeVisible({
      timeout: 5_000,
    });
  });

  test("getSources IPC call is logged on mount", async ({ page }) => {
    await configureHandlers(page, { get_sources: fakeScreenSources() });
    await page.goto(SOURCE_SELECTOR_URL);

    await expect(page.getByText("Choose what to share")).toBeVisible({
      timeout: 10_000,
    });
    // Give the component time to make all its getSources calls
    await page.waitForTimeout(1_000);

    const wasCalled = await page.evaluate(() =>
      window.__IPC_WAS_CALLED__("get_sources"),
    );
    expect(wasCalled).toBe(true);
  });
});
