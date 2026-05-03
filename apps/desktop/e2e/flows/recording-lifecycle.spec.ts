/**
 * Flow 2 — Recording lifecycle
 *
 * Tests the full record → stop → switch-to-editor flow on the HUD overlay.
 * All native recording IPC calls are intercepted by the tauri-shim.
 */

import { expect, test } from "@playwright/test";
import { permissionsGranted } from "../fixtures/permissions-granted";
import {
	configureHandlers,
	installMediaCaptureShim,
	installTauriShim,
	setLocalStorage,
} from "../setup/tauri-shim";

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

async function setupPlatformRecordingPage(
	page: import("@playwright/test").Page,
	platform: "darwin" | "win32",
) {
	await installTauriShim(page);
	await installMediaCaptureShim(page);
	await configureHandlers(page, {
		...permissionsGranted(),
		get_platform: platform,
		get_selected_source: {
			id: "screen:0:0",
			name: platform === "darwin" ? "MacBook Pro Display" : "Windows Desktop",
			sourceType: "screen",
		},
		prepare_recording_file: "/tmp/recording-e2e.webm",
		append_recording_data: null,
		replace_recording_data: "/tmp/recording-e2e.webm",
		set_current_video_path: null,
		set_current_recording_session: null,
		start_cursor_telemetry_capture: null,
		stop_cursor_telemetry_capture: null,
		start_native_screen_recording: "/tmp/native-recording.mov",
		stop_native_screen_recording: "/tmp/native-recording.mov",
		switch_to_editor: null,
		set_recording_state: null,
		hide_cursor: null,
	});
	await setLocalStorage(page, { [ONBOARDING_KEY]: "true" });
}

async function openRecordingControls(page: import("@playwright/test").Page) {
	await page.goto(HUD_URL);
	await expect(page.getByText("Record Video")).toBeVisible({ timeout: 10_000 });
	await page.getByText("Record Video").click();
	await expect(page.getByRole("button", { name: "Back" })).toBeVisible({
		timeout: 5_000,
	});
}

async function startRecordingFromHud(page: import("@playwright/test").Page) {
	await page.getByRole("button", { name: /^Record$/ }).click();
	await expect(page.getByText(/\d{2}:\d{2}/)).toBeVisible({ timeout: 5_000 });
}

async function stopRecordingFromHud(page: import("@playwright/test").Page) {
	await page
		.locator("button")
		.filter({ hasText: /\d{2}:\d{2}/ })
		.click();
	await expect(page.getByText("Record Video")).toBeVisible({ timeout: 5_000 });
}

async function waitForIpcCommand(page: import("@playwright/test").Page, command: string) {
	await expect
		.poll(() => page.evaluate((cmd) => window.__IPC_WAS_CALLED__(cmd), command))
		.toBe(true);
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

	test("clicking Record Video transitions to recording setup view", async ({ page }) => {
		await setupRecordingPage(page);
		await page.goto(HUD_URL);

		await page.getByText("Record Video").click();

		// Recording view is visible — it shows a back button (ChevronLeft)
		// and recording control buttons
		await expect(page.getByRole("button", { name: "Back" })).toBeVisible({
			timeout: 5_000,
		});
	});

	test("back button in recording view returns to choice view", async ({ page }) => {
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

	test("recording-state-changed event causes timer to appear", async ({ page }) => {
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
			await window.electronAPI.invoke("start_native_screen_recording", {
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

	test("stop_native_screen_recording IPC is logged when invoked", async ({ page }) => {
		await setupRecordingPage(page);
		await page.goto(HUD_URL);

		await page.waitForTimeout(500);

		await page.evaluate(async () => {
			await window.electronAPI.invoke("stop_native_screen_recording");
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
			await window.electronAPI.invoke("switch_to_editor", {
				query: "?mode=video",
			});
		});

		const calls = await page.evaluate(() => window.__IPC_GET_CALLS__("switch_to_editor"));
		expect(calls.length).toBeGreaterThanOrEqual(1);
		const lastCall = calls[calls.length - 1];
		expect(lastCall.args.query).toContain("mode=video");
	});

	test("macOS native screen recording starts and stops from the HUD UI", async ({ page }) => {
		await setupPlatformRecordingPage(page, "darwin");
		await openRecordingControls(page);

		await startRecordingFromHud(page);

		const startCalls = await page.evaluate(() =>
			window.__IPC_GET_CALLS__("start_native_screen_recording"),
		);
		expect(startCalls).toHaveLength(1);
		expect(startCalls[0].args.source.name).toBe("MacBook Pro Display");
		expect(startCalls[0].args.options).toEqual({
			captureCursor: false,
			capturesSystemAudio: false,
			capturesMicrophone: false,
			microphoneDeviceId: undefined,
		});

		await stopRecordingFromHud(page);
		await waitForIpcCommand(page, "switch_to_editor");

		const commandNames = await page.evaluate(() =>
			window.__TEST_IPC_LOG__.map((entry: { cmd: string }) => entry.cmd),
		);
		expect(commandNames).toContain("stop_native_screen_recording");
		expect(commandNames).toContain("stop_cursor_telemetry_capture");
		expect(commandNames).toContain("set_current_video_path");
		expect(commandNames).toContain("set_current_recording_session");
		expect(commandNames).toContain("switch_to_editor");
	});

	test("Windows Chromium screen recording starts and stops from the HUD UI", async ({ page }) => {
		await setupPlatformRecordingPage(page, "win32");
		await openRecordingControls(page);

		await startRecordingFromHud(page);

		const nativeStartWasCalled = await page.evaluate(() =>
			window.__IPC_WAS_CALLED__("start_native_screen_recording"),
		);
		expect(nativeStartWasCalled).toBe(false);

		const mediaLogAfterStart = await page.evaluate(() => window.__TEST_MEDIA_LOG__);
		expect(mediaLogAfterStart.map((entry: { cmd: string }) => entry.cmd)).toContain(
			"getDisplayMedia",
		);
		expect(mediaLogAfterStart.map((entry: { cmd: string }) => entry.cmd)).toContain(
			"MediaRecorder.start",
		);

		await stopRecordingFromHud(page);
		await waitForIpcCommand(page, "switch_to_editor");

		const commandNames = await page.evaluate(() =>
			window.__TEST_IPC_LOG__.map((entry: { cmd: string }) => entry.cmd),
		);
		expect(commandNames).toContain("prepare_recording_file");
		expect(commandNames).toContain("append_recording_data");
		expect(commandNames).toContain("replace_recording_data");
		expect(commandNames).toContain("set_current_recording_session");
		expect(commandNames).toContain("switch_to_editor");
	});
});
