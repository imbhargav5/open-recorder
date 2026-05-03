/**
 * Flow 8 — Screenshot flow
 *
 * Tests the screenshot capture flow:
 *  - HUD overlay screenshot mode renders
 *  - take_screenshot IPC is called with correct captureType
 *  - switch_to_image_editor IPC is called after capture
 *  - Image editor window renders with expected structure
 */

import { expect, test } from "@playwright/test";
import { permissionsGranted } from "../fixtures/permissions-granted";
import { configureHandlers, installTauriShim, setLocalStorage } from "../setup/tauri-shim";

const HUD_URL = "/?windowType=hud-overlay";
const IMAGE_EDITOR_URL = "/?windowType=image-editor";
const ONBOARDING_KEY = "open-recorder-onboarding-v1";

async function setupScreenshotPage(page: import("@playwright/test").Page) {
	await installTauriShim(page);
	await configureHandlers(page, {
		...permissionsGranted(),
		take_screenshot: "/tmp/test-screenshot.png",
		switch_to_image_editor: null,
		hud_overlay_hide: null,
		hud_overlay_show: null,
		get_selected_source: null,
		get_current_screenshot_path: "/tmp/test-screenshot.png",
		set_current_screenshot_path: null,
		close_source_selector: null,
	});
	await setLocalStorage(page, { [ONBOARDING_KEY]: "true" });
}

type ScreenshotPlatform = {
	label: "macOS" | "Windows";
	platform: "darwin" | "win32";
};

const screenshotPlatforms: ScreenshotPlatform[] = [
	{ label: "macOS", platform: "darwin" },
	{ label: "Windows", platform: "win32" },
];

async function setupPlatformScreenshotPage(
	page: import("@playwright/test").Page,
	platform: "darwin" | "win32",
	selectedSource: Record<string, unknown>,
) {
	await installTauriShim(page);
	await configureHandlers(page, {
		...permissionsGranted(),
		get_platform: platform,
		take_screenshot: "/tmp/test-screenshot.png",
		switch_to_image_editor: null,
		hud_overlay_hide: null,
		hud_overlay_show: null,
		get_selected_source: selectedSource,
		get_current_screenshot_path: "/tmp/test-screenshot.png",
		set_current_screenshot_path: null,
		close_source_selector: null,
		open_source_selector: null,
	});
	await setLocalStorage(page, { [ONBOARDING_KEY]: "true" });
}

async function openScreenshotControls(page: import("@playwright/test").Page) {
	await page.goto(HUD_URL);
	await expect(page.getByText("Screenshot")).toBeVisible({ timeout: 10_000 });
	await page.getByText("Screenshot").click();
	await expect(page.getByRole("button", { name: /capture entire screen/i })).toBeVisible({
		timeout: 5_000,
	});
}

async function commandNames(page: import("@playwright/test").Page) {
	return page.evaluate(() => window.__TEST_IPC_LOG__.map((entry: { cmd: string }) => entry.cmd));
}

test.describe("Screenshot flow", () => {
	test("Screenshot button is visible in the HUD choice view", async ({ page }) => {
		await setupScreenshotPage(page);
		await page.goto(HUD_URL);

		await expect(page.getByText("Screenshot")).toBeVisible({ timeout: 10_000 });
	});

	test("clicking Screenshot transitions to screenshot mode view", async ({ page }) => {
		await setupScreenshotPage(page);
		await page.goto(HUD_URL);

		await page.getByText("Screenshot").click();

		// Screenshot view shows mode buttons (Screen, Window, Area)
		await expect(page.getByRole("button", { name: /capture entire screen/i })).toBeVisible({
			timeout: 5_000,
		});
	});

	test("screenshot mode buttons render (Screen, Window, Area)", async ({ page }) => {
		await setupScreenshotPage(page);
		await page.goto(HUD_URL);

		await page.getByText("Screenshot").click();
		await page.waitForTimeout(300);

		// All three capture mode buttons should be present
		await expect(page.getByRole("button", { name: /capture entire screen/i })).toBeVisible({
			timeout: 5_000,
		});
		await expect(page.getByRole("button", { name: /capture window/i })).toBeVisible();
		await expect(page.getByRole("button", { name: /capture area/i })).toBeVisible();
	});

	test("back button in screenshot view returns to choice view", async ({ page }) => {
		await setupScreenshotPage(page);
		await page.goto(HUD_URL);

		await page.getByText("Screenshot").click();
		await expect(page.getByRole("button", { name: "Back" })).toBeVisible({ timeout: 5_000 });

		await page.getByRole("button", { name: "Back" }).click();

		// Back to choice view
		await expect(page.getByText("Record Video")).toBeVisible({ timeout: 5_000 });
		await expect(page.getByText("Screenshot")).toBeVisible();
	});

	test("take_screenshot IPC is called when invoked via shim", async ({ page }) => {
		await setupScreenshotPage(page);
		await page.goto(HUD_URL);
		await page.waitForTimeout(500);

		// Directly invoke take_screenshot via shim to test the contract
		const result = await page.evaluate(async () => {
			return window.electronAPI.invoke("take_screenshot", {
				captureType: "screen",
				windowId: undefined,
			});
		});

		expect(result).toBe("/tmp/test-screenshot.png");

		const calls = await page.evaluate(() => window.__IPC_GET_CALLS__("take_screenshot"));
		expect(calls.length).toBeGreaterThanOrEqual(1);
		expect(calls[calls.length - 1].args.captureType).toBe("screen");
	});

	test("switch_to_image_editor IPC is called when invoked via shim", async ({ page }) => {
		await setupScreenshotPage(page);
		await page.goto(HUD_URL);
		await page.waitForTimeout(500);

		await page.evaluate(async () => {
			await window.electronAPI.invoke("switch_to_image_editor");
		});

		const wasCalled = await page.evaluate(() =>
			window.__IPC_WAS_CALLED__("switch_to_image_editor"),
		);
		expect(wasCalled).toBe(true);
	});

	test("screenshot flow IPC sequence: hud_overlay_hide → take_screenshot → switch_to_image_editor", async ({
		page,
	}) => {
		await setupScreenshotPage(page);
		await page.goto(HUD_URL);
		await page.waitForTimeout(500);

		// Simulate the full screenshot capture sequence
		await page.evaluate(async () => {
			await window.electronAPI.invoke("hud_overlay_hide");
			await window.electronAPI.invoke("take_screenshot", {
				captureType: "screen",
				windowId: undefined,
			});
			await window.electronAPI.invoke("switch_to_image_editor");
		});

		// Verify all three commands were called in the log
		const log = await page.evaluate(() => window.__TEST_IPC_LOG__);
		const cmdNames = log.map((entry: { cmd: string }) => entry.cmd);

		expect(cmdNames).toContain("hud_overlay_hide");
		expect(cmdNames).toContain("take_screenshot");
		expect(cmdNames).toContain("switch_to_image_editor");

		// Verify order
		const hideIdx = cmdNames.lastIndexOf("hud_overlay_hide");
		const shotIdx = cmdNames.lastIndexOf("take_screenshot");
		const editorIdx = cmdNames.lastIndexOf("switch_to_image_editor");
		expect(hideIdx).toBeLessThan(shotIdx);
		expect(shotIdx).toBeLessThan(editorIdx);
	});

	test("image-editor window renders root element", async ({ page }) => {
		await installTauriShim(page);
		await configureHandlers(page, {
			get_current_screenshot_path: "/tmp/test-screenshot.png",
		});
		await page.goto(IMAGE_EDITOR_URL);

		await page.waitForTimeout(2_000);

		// The root element should be mounted
		const root = page.locator("#root");
		await expect(root).toBeAttached({ timeout: 5_000 });

		// Should have child content
		const childCount = await page.evaluate(
			() => document.getElementById("root")?.childElementCount ?? 0,
		);
		expect(childCount).toBeGreaterThan(0);
	});

	test("image-editor page loads without fatal JS errors", async ({ page }) => {
		const errors: string[] = [];
		page.on("pageerror", (err) => {
			if (
				!err.message.includes("tauri") &&
				!err.message.includes("WebGL") &&
				!err.message.includes("play()") &&
				!err.message.includes("ResizeObserver")
			) {
				errors.push(err.message);
			}
		});

		await installTauriShim(page);
		await configureHandlers(page, {
			get_current_screenshot_path: "/tmp/test-screenshot.png",
		});
		await page.goto(IMAGE_EDITOR_URL);
		await page.waitForTimeout(3_000);

		expect(errors).toHaveLength(0);
	});

	for (const { label, platform } of screenshotPlatforms) {
		test(`${label} screen screenshot capture uses the HUD UI`, async ({ page }) => {
			await setupPlatformScreenshotPage(page, platform, {
				id: "screen:0:0",
				name: `${label} Display`,
				sourceType: "screen",
			});
			await openScreenshotControls(page);

			await page.getByRole("button", { name: /capture entire screen/i }).click();
			await expect(page.getByRole("button", { name: /take screenshot/i })).toBeVisible({
				timeout: 5_000,
			});
			await page.getByRole("button", { name: /take screenshot/i }).click();

			await expect
				.poll(async () => (await commandNames(page)).includes("switch_to_image_editor"))
				.toBe(true);

			const calls = await page.evaluate(() => window.__IPC_GET_CALLS__("take_screenshot"));
			expect(calls.at(-1).args).toEqual({
				captureType: "screen",
				windowId: undefined,
			});
			const names = await commandNames(page);
			expect(names.indexOf("hud_overlay_hide")).toBeLessThan(names.indexOf("take_screenshot"));
			expect(names.indexOf("take_screenshot")).toBeLessThan(
				names.indexOf("switch_to_image_editor"),
			);
		});

		test(`${label} window screenshot capture sends the selected window id`, async ({ page }) => {
			await setupPlatformScreenshotPage(page, platform, {
				id: "window:1234",
				name: "Design Review",
				sourceType: "window",
				windowId: 1234,
				windowTitle: "Design Review",
			});
			await openScreenshotControls(page);

			await page.getByRole("button", { name: /capture window/i }).click();
			await expect(page.getByRole("button", { name: /take screenshot/i })).toBeVisible({
				timeout: 5_000,
			});
			await page.getByRole("button", { name: /take screenshot/i }).click();

			await expect
				.poll(async () => (await commandNames(page)).includes("switch_to_image_editor"))
				.toBe(true);

			const calls = await page.evaluate(() => window.__IPC_GET_CALLS__("take_screenshot"));
			expect(calls.at(-1).args).toEqual({
				captureType: "window",
				windowId: 1234,
			});
		});

		test(`${label} area screenshot capture runs immediately`, async ({ page }) => {
			await setupPlatformScreenshotPage(page, platform, {
				id: "screen:0:0",
				name: `${label} Display`,
				sourceType: "screen",
			});
			await openScreenshotControls(page);

			await page.getByRole("button", { name: /capture area/i }).click();

			await expect
				.poll(async () => (await commandNames(page)).includes("switch_to_image_editor"))
				.toBe(true);

			const calls = await page.evaluate(() => window.__IPC_GET_CALLS__("take_screenshot"));
			expect(calls.at(-1).args).toEqual({
				captureType: "area",
				windowId: undefined,
			});
			const names = await commandNames(page);
			expect(names).toContain("close_source_selector");
			expect(names.indexOf("hud_overlay_hide")).toBeLessThan(names.indexOf("take_screenshot"));
		});
	}
});
