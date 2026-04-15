// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import {
	exportErrorAtom,
	exportProgressAtom,
	exportedFilePathAtom,
	isExportingAtom,
	showExportDialogAtom,
} from "@/atoms/videoEditor";
import type { ExportProgress } from "@/lib/exporter";

vi.mock("@/lib/backend", () => ({
	revealInFolder: vi.fn(),
}));

// lucide-react icons are ESM-only; stub them out to keep the test lightweight
vi.mock("lucide-react", () => ({
	X: () => null,
	Download: () => null,
	Loader2: () => null,
}));

const { ExportDialog } = await import("./ExportDialog");

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

const COMPLETED_PROGRESS: ExportProgress = {
	currentFrame: 60,
	totalFrames: 60,
	percentage: 100,
	estimatedTimeRemaining: 0,
};

interface Harness {
	container: HTMLDivElement;
	unmount: () => Promise<void>;
}

async function renderDialog(
	store: ReturnType<typeof createStore>,
	props: { onClose?: () => void } = {},
): Promise<Harness> {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);

	await act(async () => {
		root.render(
			<Provider store={store}>
				<ExportDialog onClose={props.onClose ?? vi.fn()} />
			</Provider>,
		);
	});

	return {
		container,
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
			container.remove();
		},
	};
}

afterEach(() => {
	vi.clearAllMocks();
	vi.useRealTimers();
	document.body.innerHTML = "";
});

describe("ExportDialog – setTimeout cleanup on unmount", () => {
	it("clears the auto-close timer when the component unmounts before it fires", async () => {
		vi.useFakeTimers();

		const store = createStore();
		store.set(showExportDialogAtom, true);
		store.set(isExportingAtom, false);
		store.set(exportProgressAtom, COMPLETED_PROGRESS);
		store.set(exportErrorAtom, null);
		store.set(exportedFilePathAtom, "/tmp/recording.mp4");

		const onClose = vi.fn();
		const consoleError = vi.spyOn(console, "error");

		const harness = await renderDialog(store, { onClose });

		// The effect should have scheduled the auto-close timer
		expect(onClose).not.toHaveBeenCalled();

		// Unmount before the 2-second timer fires
		await harness.unmount();

		// Advance past the 2-second mark – the timer should have been cleared
		act(() => {
			vi.advanceTimersByTime(3000);
		});

		// onClose must NOT be called after unmount
		expect(onClose).not.toHaveBeenCalled();

		// No React "state update on an unmounted component" warnings
		const stateUpdateWarnings = consoleError.mock.calls.filter((args) =>
			String(args[0]).includes("unmounted"),
		);
		expect(stateUpdateWarnings).toHaveLength(0);

		consoleError.mockRestore();
	});

	it("does NOT schedule a timer while still exporting", async () => {
		vi.useFakeTimers();

		const store = createStore();
		store.set(showExportDialogAtom, true);
		store.set(isExportingAtom, true);
		store.set(exportProgressAtom, COMPLETED_PROGRESS);
		store.set(exportErrorAtom, null);

		const onClose = vi.fn();

		const harness = await renderDialog(store, { onClose });

		act(() => {
			vi.advanceTimersByTime(5000);
		});

		expect(onClose).not.toHaveBeenCalled();

		await harness.unmount();
	});
});
