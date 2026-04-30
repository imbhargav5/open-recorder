import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/electronBridge", () => ({
	invoke: vi.fn(),
	listen: vi.fn(),
}));

vi.mock("@/lib/mediaPlaybackUrl", () => ({
	resolveMediaPlaybackUrl: vi.fn((path: string) => path),
}));

const { invoke, listen } = vi.mocked(await import("@/lib/electronBridge"));
const backend = await import("@/lib/backend");

beforeEach(() => {
	vi.clearAllMocks();
});

afterEach(() => {
	vi.restoreAllMocks();
});

describe("updater backend wrappers", () => {
	it("gets updater state through the explicit IPC channel", async () => {
		invoke.mockResolvedValue({
			supported: true,
			dialogOpen: false,
			status: "idle",
			currentVersion: "0.0.31",
			version: null,
			releaseNotes: null,
			downloadProgress: 0,
			error: null,
		});

		await backend.getUpdaterState();

		expect(invoke).toHaveBeenCalledWith("get_updater_state");
	});

	it("checks for updates with a JSON-safe options payload", async () => {
		invoke.mockResolvedValue({
			supported: true,
			dialogOpen: true,
			status: "checking",
			currentVersion: "0.0.31",
			version: null,
			releaseNotes: null,
			downloadProgress: 0,
			error: null,
		});

		await backend.checkForUpdates({ showDialog: true });

		expect(invoke).toHaveBeenCalledWith("check_for_updates", { showDialog: true });
	});

	it("downloads updates and installs them through distinct IPC commands", async () => {
		invoke.mockResolvedValue(undefined);

		await backend.downloadUpdate();
		await backend.installUpdateAndRestart();

		expect(invoke).toHaveBeenNthCalledWith(1, "download_update");
		expect(invoke).toHaveBeenNthCalledWith(2, "install_update_and_restart");
	});

	it("subscribes to updater state and progress events", async () => {
		const unlisten = vi.fn();
		listen.mockReturnValue(unlisten);

		const stateCallback = vi.fn();
		const progressCallback = vi.fn();

		const stateUnlisten = await backend.onUpdaterStateChanged(stateCallback);
		const progressUnlisten = await backend.onUpdaterDownloadProgress(progressCallback);

		expect(listen).toHaveBeenNthCalledWith(1, "updater-state-changed", stateCallback);
		expect(listen).toHaveBeenNthCalledWith(2, "updater-download-progress", progressCallback);
		expect(stateUnlisten).toBe(unlisten);
		expect(progressUnlisten).toBe(unlisten);
	});
});
