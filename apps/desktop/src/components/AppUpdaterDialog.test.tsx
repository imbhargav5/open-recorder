// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { UpdaterState } from "@/lib/backend";

let updaterStateHandler: ((state: UpdaterState) => void) | null = null;
let downloadProgressHandler: ((payload: { percent: number }) => void) | null = null;

vi.mock("@/lib/backend", () => ({
	getUpdaterState: vi.fn(),
	checkForUpdates: vi.fn(),
	downloadUpdate: vi.fn(),
	dismissUpdaterDialog: vi.fn(),
	installUpdateAndRestart: vi.fn(),
	onUpdaterStateChanged: vi.fn(),
	onUpdaterDownloadProgress: vi.fn(),
}));

vi.mock("lucide-react", () => ({
	CheckCircle2: () => null,
	Download: () => null,
	LoaderCircle: () => null,
	RefreshCw: () => null,
	TriangleAlert: () => null,
	X: () => null,
}));

const backend = vi.mocked(await import("@/lib/backend"));
const { AppUpdaterDialog } = await import("./AppUpdaterDialog");

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

function createUpdaterState(overrides: Partial<UpdaterState> = {}): UpdaterState {
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

function renderDialog() {
	return render(
		<Provider store={createStore()}>
			<AppUpdaterDialog enableAutoCheck={false} />
		</Provider>,
	);
}

async function emitUpdaterState(state: UpdaterState) {
	await act(async () => {
		updaterStateHandler?.(state);
		await Promise.resolve();
	});
}

async function emitDownloadProgress(percent: number) {
	await act(async () => {
		downloadProgressHandler?.({ percent });
		await Promise.resolve();
	});
}

beforeEach(() => {
	vi.clearAllMocks();
	updaterStateHandler = null;
	downloadProgressHandler = null;

	backend.getUpdaterState.mockResolvedValue(createUpdaterState());
	backend.checkForUpdates.mockResolvedValue(createUpdaterState({ dialogOpen: true, status: "checking" }));
	backend.downloadUpdate.mockResolvedValue(
		createUpdaterState({ dialogOpen: true, status: "downloading" }),
	);
	backend.dismissUpdaterDialog.mockResolvedValue(createUpdaterState());
	backend.installUpdateAndRestart.mockResolvedValue(undefined);
	backend.onUpdaterStateChanged.mockImplementation((callback) => {
		updaterStateHandler = callback;
		return Promise.resolve(vi.fn());
	});
	backend.onUpdaterDownloadProgress.mockImplementation((callback) => {
		downloadProgressHandler = callback;
		return Promise.resolve(vi.fn());
	});
});

afterEach(() => {
	cleanup();
	vi.clearAllMocks();
});

describe("AppUpdaterDialog", () => {
	it("renders the manual-check flow from checking to up-to-date", async () => {
		renderDialog();

		await waitFor(() => {
			expect(backend.getUpdaterState).toHaveBeenCalledTimes(1);
			expect(backend.onUpdaterStateChanged).toHaveBeenCalledTimes(1);
			expect(backend.onUpdaterDownloadProgress).toHaveBeenCalledTimes(1);
		});

		await emitUpdaterState(createUpdaterState({ dialogOpen: true, status: "checking" }));
		expect(await screen.findByText("Checking for updates")).toBeInTheDocument();

		await emitUpdaterState(createUpdaterState({ dialogOpen: true, status: "up-to-date" }));
		expect(await screen.findByText("Open Recorder is up to date")).toBeInTheDocument();
		expect(
			screen.getByText("You already have the latest available version installed."),
		).toBeInTheDocument();
	});

	it("renders an available update and installs it through backend IPC", async () => {
		backend.getUpdaterState.mockResolvedValue(
			createUpdaterState({
				dialogOpen: true,
				status: "available",
				version: "0.0.32",
				releaseNotes: "Bug fixes and performance improvements.",
			}),
		);
		backend.downloadUpdate.mockResolvedValue(
			createUpdaterState({
				dialogOpen: true,
				status: "downloading",
				version: "0.0.32",
				releaseNotes: "Bug fixes and performance improvements.",
			}),
		);

		renderDialog();

		expect(await screen.findByText("Update available: v0.0.32")).toBeInTheDocument();
		expect(screen.getByText("Bug fixes and performance improvements.")).toBeInTheDocument();

		await userEvent.click(screen.getByRole("button", { name: "Install update" }));
		expect(backend.downloadUpdate).toHaveBeenCalledTimes(1);
		expect(await screen.findByText("Updating Open Recorder")).toBeInTheDocument();

		await emitDownloadProgress(42);
		expect(await screen.findByText("42% downloaded")).toBeInTheDocument();

		await emitUpdaterState(
			createUpdaterState({
				dialogOpen: true,
				status: "ready",
				version: "0.0.32",
				releaseNotes: "Bug fixes and performance improvements.",
				downloadProgress: 100,
			}),
		);
		expect(await screen.findByText("Update ready to restart")).toBeInTheDocument();

		await userEvent.click(screen.getByRole("button", { name: "Restart now" }));
		expect(backend.installUpdateAndRestart).toHaveBeenCalledTimes(1);
	});

	it("shows an error state and retries through the check-for-updates IPC path", async () => {
		backend.getUpdaterState.mockResolvedValue(
			createUpdaterState({
				dialogOpen: true,
				status: "error",
				error: "Network timeout",
			}),
		);
		backend.checkForUpdates.mockResolvedValue(
			createUpdaterState({
				dialogOpen: true,
				status: "checking",
			}),
		);

		renderDialog();

		expect(await screen.findByText("Update failed")).toBeInTheDocument();
		expect(screen.getByText("Network timeout")).toBeInTheDocument();

		await userEvent.click(screen.getByRole("button", { name: "Try again" }));
		expect(backend.checkForUpdates).toHaveBeenCalledWith({ showDialog: true });
	});
});
