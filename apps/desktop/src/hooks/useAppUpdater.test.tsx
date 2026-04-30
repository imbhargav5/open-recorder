// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { UpdaterState } from "@/lib/backend";
import type { UseAppUpdaterReturn } from "./useAppUpdater";
import { useAppUpdater } from "./useAppUpdater";

vi.mock("@/lib/backend", () => ({
	getUpdaterState: vi.fn(),
	checkForUpdates: vi.fn(),
	downloadUpdate: vi.fn(),
	dismissUpdaterDialog: vi.fn(),
	installUpdateAndRestart: vi.fn(),
	onUpdaterStateChanged: vi.fn(),
	onUpdaterDownloadProgress: vi.fn(),
}));

const backend = vi.mocked(await import("@/lib/backend"));

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

type HookHarnessResult = {
	getCurrent: () => UseAppUpdaterReturn;
	unmount: () => Promise<void>;
};

function makeState(overrides: Partial<UpdaterState> = {}): UpdaterState {
	return {
		supported: true,
		dialogOpen: false,
		status: "idle",
		currentVersion: "0.0.31",
		version: null,
		releaseNotes: null,
		downloadProgress: 0,
		error: null,
		...overrides,
	};
}

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function mountHook(options?: { enableAutoCheck?: boolean }): Promise<HookHarnessResult> {
	const container = document.createElement("div");
	const root: Root = createRoot(container);
	const store = createStore();
	let currentValue!: UseAppUpdaterReturn;

	function Harness() {
		currentValue = useAppUpdater(options);
		return null;
	}

	await act(async () => {
		root.render(
			<Provider store={store}>
				<Harness />
			</Provider>,
		);
	});
	await flushEffects();

	return {
		getCurrent: () => currentValue,
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
		},
	};
}

beforeEach(() => {
	vi.clearAllMocks();
	backend.getUpdaterState.mockResolvedValue(makeState());
	backend.checkForUpdates.mockResolvedValue(makeState());
	backend.downloadUpdate.mockResolvedValue(makeState({ status: "downloading", dialogOpen: true }));
	backend.dismissUpdaterDialog.mockResolvedValue(makeState());
	backend.installUpdateAndRestart.mockResolvedValue(undefined);
	backend.onUpdaterStateChanged.mockImplementation(async () => vi.fn());
	backend.onUpdaterDownloadProgress.mockImplementation(async () => vi.fn());
});

afterEach(() => {
	vi.restoreAllMocks();
});

describe("useAppUpdater", () => {
	it("surfaces an available update after a manual check", async () => {
		backend.checkForUpdates.mockResolvedValue(
			makeState({
				dialogOpen: true,
				status: "available",
				version: "0.0.32",
				releaseNotes: "Bug fixes",
			}),
		);

		const hook = await mountHook({ enableAutoCheck: false });

		await act(async () => {
			await hook.getCurrent().checkForUpdate({ showDialog: true });
		});

		expect(backend.checkForUpdates).toHaveBeenCalledWith({ showDialog: true });
		expect(hook.getCurrent().status).toBe("available");
		expect(hook.getCurrent().isDialogOpen).toBe(true);
		expect(hook.getCurrent().version).toBe("0.0.32");
		expect(hook.getCurrent().releaseNotes).toBe("Bug fixes");

		await hook.unmount();
	});

	it("shows the up-to-date state for an interactive no-update check", async () => {
		backend.checkForUpdates.mockResolvedValue(
			makeState({
				dialogOpen: true,
				status: "up-to-date",
			}),
		);

		const hook = await mountHook({ enableAutoCheck: false });

		await act(async () => {
			await hook.getCurrent().checkForUpdate({ showDialog: true });
		});

		expect(hook.getCurrent().status).toBe("up-to-date");
		expect(hook.getCurrent().isDialogOpen).toBe(true);

		await hook.unmount();
	});

	it("shows updater errors returned by the backend contract", async () => {
		backend.checkForUpdates.mockResolvedValue(
			makeState({
				dialogOpen: true,
				status: "error",
				error: "Feed unavailable",
			}),
		);

		const hook = await mountHook({ enableAutoCheck: false });

		await act(async () => {
			await hook.getCurrent().checkForUpdate({ showDialog: true });
		});

		expect(hook.getCurrent().status).toBe("error");
		expect(hook.getCurrent().error).toBe("Feed unavailable");

		await hook.unmount();
	});

	it("tracks download progress and becomes ready to restart", async () => {
		let onStateChanged: ((state: UpdaterState) => void) | undefined;
		let onProgress: ((payload: { percent: number }) => void) | undefined;

		backend.onUpdaterStateChanged.mockImplementation(async (callback) => {
			onStateChanged = callback;
			return vi.fn();
		});
		backend.onUpdaterDownloadProgress.mockImplementation(async (callback) => {
			onProgress = callback;
			return vi.fn();
		});
		backend.getUpdaterState.mockResolvedValue(
			makeState({
				dialogOpen: true,
				status: "available",
				version: "0.0.32",
			}),
		);
		backend.downloadUpdate.mockResolvedValue(
			makeState({
				dialogOpen: true,
				status: "downloading",
				version: "0.0.32",
				downloadProgress: 0,
			}),
		);

		const hook = await mountHook({ enableAutoCheck: false });

		await act(async () => {
			await hook.getCurrent().downloadAndInstall();
		});
		await act(async () => {
			onProgress?.({ percent: 42 });
		});
		await act(async () => {
			onStateChanged?.(
				makeState({
					dialogOpen: true,
					status: "ready",
					version: "0.0.32",
					downloadProgress: 100,
				}),
			);
		});

		expect(backend.downloadUpdate).toHaveBeenCalledTimes(1);
		expect(hook.getCurrent().downloadProgress).toBe(100);
		expect(hook.getCurrent().status).toBe("ready");

		await hook.unmount();
	});

	it("restarts through the updater install path instead of reloading the window", async () => {
		const hook = await mountHook({ enableAutoCheck: false });

		await act(async () => {
			await hook.getCurrent().restartApp();
		});

		expect(backend.installUpdateAndRestart).toHaveBeenCalledTimes(1);

		await hook.unmount();
	});
});
