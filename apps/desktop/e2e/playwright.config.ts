import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, devices } from "@playwright/test";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webServerEnv = {
	...process.env,
	OPEN_RECORDER_RENDERER_ONLY: "1",
};

/**
 * Playwright E2E configuration for the Open Recorder Tauri desktop app.
 *
 * Tests run against the Vite dev server (no native Tauri binary needed).
 * All Tauri IPC calls are intercepted by the tauri-shim injected via
 * page.addInitScript() before React initialises.
 *
 * @see apps/desktop/e2e/setup/tauri-shim.ts
 */
export default defineConfig({
	testDir: "./flows",
	testIgnore: ["**/._*"],

	/* Run tests in parallel for speed */
	fullyParallel: true,

	/* Retry on CI to absorb flakiness */
	retries: process.env.CI ? 2 : 0,

	/* HTML report saved next to this config file */
	reporter: [["html", { outputFolder: path.join(__dirname, "..", "e2e-results") }]],

	use: {
		/* Base URL matches the Vite dev server port in vite.config.ts */
		baseURL: "http://127.0.0.1:5789",

		/* Use Playwright's bundled Chromium (no system Chrome dependency) */
		...devices["Desktop Chrome"],

		launchOptions: {
			args: [
				/* Grant fake media devices so getUserMedia doesn't block the UI */
				"--use-fake-ui-for-media-stream",
				"--use-fake-device-for-media-stream",
				/* Disable CORS so asset:// URLs from the shim don't cause errors */
				"--disable-web-security",
				/* Enable GPU-less WebGL so PixiJS can initialise in headless mode */
				"--enable-webgl",
				"--use-gl=angle",
				"--enable-unsafe-webgpu",
			],
		},

		/* Capture screenshot on test failure for easier debugging */
		screenshot: "only-on-failure",
		video: "retain-on-failure",
	},

	/* Start the Vite dev server automatically if it isn't already running */
	webServer: {
		command: "pnpm exec vite --host 127.0.0.1 --port 5789 --strictPort",
		url: "http://127.0.0.1:5789",
		/** CWD is apps/desktop/ (one level above this config file) */
		cwd: path.join(__dirname, ".."),
		env: webServerEnv,
		reuseExistingServer: !process.env.CI,
		timeout: 120_000,
		stdout: "pipe",
		stderr: "pipe",
	},
});
