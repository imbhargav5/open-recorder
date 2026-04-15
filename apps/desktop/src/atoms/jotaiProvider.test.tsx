// @vitest-environment jsdom

/**
 * Jotai Provider + React component integration tests.
 *
 * Tests cover:
 * 1. Atoms are read correctly on mount
 * 2. State updates propagate to the UI
 * 3. useAtomValue vs useSetAtom vs useAtom behaviour
 * 4. Component re-render tracking (writer doesn't re-render when reader atom changes)
 * 5. Unmount-cleanup patterns (atoms reset when component unmounts)
 * 6. Multiple components sharing the same atom stay in sync
 * 7. Conditional rendering based on atom state
 * 8. Provider-store isolation (separate Providers are fully independent)
 */

import { cleanup, fireEvent, render, screen, act } from "@testing-library/react";
import { Provider, createStore, useAtom, useAtomValue, useSetAtom } from "jotai";
import { useEffect, useRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
	hasSelectedSourceAtom,
	isCapturingAtom,
	launchViewAtom,
	recordingElapsedAtom,
	recordingStartAtom,
	screenshotModeAtom,
	selectedSourceAtom,
} from "./launch";
import {
	cameraEnabledAtom,
	microphoneEnabledAtom,
	recordingActiveAtom,
} from "./recording";
import {
	settingsActiveTabAtom,
	settingsShowCropModalAtom,
} from "./settingsPanel";
import {
	isExportingAtom,
	isPlayingAtom,
	showExportDialogAtom,
	videoErrorAtom,
	videoPathAtom,
} from "./videoEditor";

// ─── Test helpers ────────────────────────────────────────────────────────────

/**
 * Render `ui` inside a fresh Jotai Provider backed by `store`.
 * Returns the store so tests can set atom values imperatively.
 */
function renderWithStore(
	ui: React.ReactElement,
	store = createStore(),
) {
	const result = render(<Provider store={store}>{ui}</Provider>);
	return { store, ...result };
}

afterEach(() => {
	cleanup();
});

// ─── 1. Atoms are read correctly on mount ────────────────────────────────────

describe("atoms are read correctly on mount", () => {
	it("reads launchViewAtom default ('choice') on mount", () => {
		function Display() {
			const view = useAtomValue(launchViewAtom);
			return <span data-testid="view">{view}</span>;
		}
		renderWithStore(<Display />);
		expect(screen.getByTestId("view").textContent).toBe("choice");
	});

	it("reads isCapturingAtom default (false) on mount", () => {
		function Display() {
			const capturing = useAtomValue(isCapturingAtom);
			return <span data-testid="cap">{String(capturing)}</span>;
		}
		renderWithStore(<Display />);
		expect(screen.getByTestId("cap").textContent).toBe("false");
	});

	it("reads selectedSourceAtom default ('Main Display') on mount", () => {
		function Display() {
			const src = useAtomValue(selectedSourceAtom);
			return <span data-testid="src">{src}</span>;
		}
		renderWithStore(<Display />);
		expect(screen.getByTestId("src").textContent).toBe("Main Display");
	});

	it("reads videoPathAtom default (null → empty string) on mount", () => {
		function Display() {
			const path = useAtomValue(videoPathAtom);
			return <span data-testid="path">{path ?? "null"}</span>;
		}
		renderWithStore(<Display />);
		expect(screen.getByTestId("path").textContent).toBe("null");
	});

	it("reads settingsActiveTabAtom default ('appearance') on mount", () => {
		function Display() {
			const tab = useAtomValue(settingsActiveTabAtom);
			return <span data-testid="tab">{tab}</span>;
		}
		renderWithStore(<Display />);
		expect(screen.getByTestId("tab").textContent).toBe("appearance");
	});

	it("reads recordingActiveAtom default (false) on mount", () => {
		function Display() {
			const active = useAtomValue(recordingActiveAtom);
			return <span data-testid="rec">{String(active)}</span>;
		}
		renderWithStore(<Display />);
		expect(screen.getByTestId("rec").textContent).toBe("false");
	});
});

// ─── 2. State updates propagate to the UI ────────────────────────────────────

describe("state updates propagate to the UI", () => {
	it("launchViewAtom update is reflected in the component", () => {
		function Display() {
			const view = useAtomValue(launchViewAtom);
			return <span data-testid="view">{view}</span>;
		}
		const { store } = renderWithStore(<Display />);
		act(() => { store.set(launchViewAtom, "recording"); });
		expect(screen.getByTestId("view").textContent).toBe("recording");
	});

	it("isCapturingAtom update is reflected in the component", () => {
		function Display() {
			const capturing = useAtomValue(isCapturingAtom);
			return <span data-testid="cap">{String(capturing)}</span>;
		}
		const { store } = renderWithStore(<Display />);
		act(() => { store.set(isCapturingAtom, true); });
		expect(screen.getByTestId("cap").textContent).toBe("true");
	});

	it("videoPathAtom update is reflected in the component", () => {
		function Display() {
			const path = useAtomValue(videoPathAtom);
			return <span data-testid="path">{path ?? "null"}</span>;
		}
		const { store } = renderWithStore(<Display />);
		act(() => { store.set(videoPathAtom, "/my/video.mp4"); });
		expect(screen.getByTestId("path").textContent).toBe("/my/video.mp4");
	});

	it("recordingElapsedAtom increments are reflected", () => {
		function Elapsed() {
			const elapsed = useAtomValue(recordingElapsedAtom);
			return <span data-testid="elapsed">{elapsed}</span>;
		}
		const { store } = renderWithStore(<Elapsed />);
		act(() => { store.set(recordingElapsedAtom, 5); });
		expect(screen.getByTestId("elapsed").textContent).toBe("5");
		act(() => { store.set(recordingElapsedAtom, 10); });
		expect(screen.getByTestId("elapsed").textContent).toBe("10");
	});
});

// ─── 3. useAtomValue / useSetAtom / useAtom behaviour ────────────────────────

describe("useAtomValue, useSetAtom, useAtom behaviour", () => {
	it("useSetAtom triggers update seen by a useAtomValue consumer", () => {
		function Reader() {
			const val = useAtomValue(isPlayingAtom);
			return <span data-testid="playing">{String(val)}</span>;
		}
		function Toggler() {
			const setPlaying = useSetAtom(isPlayingAtom);
			return <button onClick={() => setPlaying(true)}>Play</button>;
		}
		renderWithStore(
			<>
				<Reader />
				<Toggler />
			</>,
		);
		expect(screen.getByTestId("playing").textContent).toBe("false");
		fireEvent.click(screen.getByText("Play"));
		expect(screen.getByTestId("playing").textContent).toBe("true");
	});

	it("useAtom provides both read and write in one hook", () => {
		function Toggle() {
			const [capturing, setCapturing] = useAtom(isCapturingAtom);
			return (
				<>
					<span data-testid="val">{String(capturing)}</span>
					<button onClick={() => setCapturing((prev) => !prev)}>Toggle</button>
				</>
			);
		}
		renderWithStore(<Toggle />);
		expect(screen.getByTestId("val").textContent).toBe("false");
		fireEvent.click(screen.getByText("Toggle"));
		expect(screen.getByTestId("val").textContent).toBe("true");
		fireEvent.click(screen.getByText("Toggle"));
		expect(screen.getByTestId("val").textContent).toBe("false");
	});

	it("useAtom setter can replace the full value", () => {
		function TabSwitcher() {
			const [tab, setTab] = useAtom(settingsActiveTabAtom);
			return (
				<>
					<span data-testid="tab">{tab}</span>
					<button onClick={() => setTab("audio")}>Audio</button>
					<button onClick={() => setTab("appearance")}>Appearance</button>
				</>
			);
		}
		renderWithStore(<TabSwitcher />);
		fireEvent.click(screen.getByText("Audio"));
		expect(screen.getByTestId("tab").textContent).toBe("audio");
		fireEvent.click(screen.getByText("Appearance"));
		expect(screen.getByTestId("tab").textContent).toBe("appearance");
	});
});

// ─── 4. Re-render tracking ───────────────────────────────────────────────────

describe("component re-render behaviour", () => {
	it("useSetAtom component does NOT re-render when the atom's value changes", () => {
		let writerRenders = 0;

		function Writer() {
			writerRenders++;
			const setPlaying = useSetAtom(isPlayingAtom);
			return <button onClick={() => setPlaying(true)}>Play</button>;
		}
		function Reader() {
			const val = useAtomValue(isPlayingAtom);
			return <span data-testid="v">{String(val)}</span>;
		}

		renderWithStore(
			<>
				<Writer />
				<Reader />
			</>,
		);

		const rendersBeforeClick = writerRenders;
		fireEvent.click(screen.getByText("Play"));

		// Writer should not re-render; Reader should
		expect(writerRenders).toBe(rendersBeforeClick);
		expect(screen.getByTestId("v").textContent).toBe("true");
	});

	it("useAtomValue component re-renders only for its own atom, not unrelated atoms", () => {
		let readerRenders = 0;

		function Reader() {
			readerRenders++;
			useAtomValue(isPlayingAtom);
			return null;
		}

		const { store } = renderWithStore(<Reader />);
		const before = readerRenders;

		// Change an unrelated atom (videoError)
		act(() => { store.set(videoErrorAtom, "an error"); });
		const afterUnrelated = readerRenders;
		expect(afterUnrelated).toBe(before); // no extra render

		// Change the watched atom
		act(() => { store.set(isPlayingAtom, true); });
		expect(readerRenders).toBeGreaterThan(afterUnrelated); // re-rendered
	});
});

// ─── 5. Unmount-cleanup patterns ─────────────────────────────────────────────

describe("unmount cleanup patterns", () => {
	it("atom reset on unmount is reflected in the store", () => {
		const store = createStore();
		store.set(recordingStartAtom, Date.now());
		store.set(recordingElapsedAtom, 30);

		function ComponentWithCleanup() {
			const setStart = useSetAtom(recordingStartAtom);
			const setElapsed = useSetAtom(recordingElapsedAtom);
			useEffect(() => {
				return () => {
					setStart(null);
					setElapsed(0);
				};
			}, [setStart, setElapsed]);
			return null;
		}

		const { unmount } = render(
			<Provider store={store}>
				<ComponentWithCleanup />
			</Provider>,
		);

		expect(store.get(recordingStartAtom)).not.toBeNull();
		unmount();
		expect(store.get(recordingStartAtom)).toBeNull();
		expect(store.get(recordingElapsedAtom)).toBe(0);
	});

	it("atom values remain after unmount when no cleanup is set up", () => {
		const store = createStore();

		function Component() {
			const setPath = useSetAtom(videoPathAtom);
			useEffect(() => {
				setPath("/persisted.mp4");
			}, [setPath]);
			return null;
		}

		const { unmount } = render(
			<Provider store={store}>
				<Component />
			</Provider>,
		);

		act(() => {}); // flush effects
		unmount();

		// No cleanup → atom retains its value
		expect(store.get(videoPathAtom)).toBe("/persisted.mp4");
	});
});

// ─── 6. Multiple components sharing the same atom ────────────────────────────

describe("multiple components sharing the same atom stay in sync", () => {
	it("two Reader components stay in sync when the atom changes", () => {
		function Reader({ id }: { id: string }) {
			const view = useAtomValue(launchViewAtom);
			return <span data-testid={id}>{view}</span>;
		}
		function Writer() {
			const setView = useSetAtom(launchViewAtom);
			return <button onClick={() => setView("recording")}>Record</button>;
		}

		renderWithStore(
			<>
				<Reader id="a" />
				<Reader id="b" />
				<Writer />
			</>,
		);

		expect(screen.getByTestId("a").textContent).toBe("choice");
		expect(screen.getByTestId("b").textContent).toBe("choice");

		fireEvent.click(screen.getByText("Record"));

		expect(screen.getByTestId("a").textContent).toBe("recording");
		expect(screen.getByTestId("b").textContent).toBe("recording");
	});

	it("three components sharing microphoneEnabledAtom all update together", () => {
		function Display({ id }: { id: string }) {
			const enabled = useAtomValue(microphoneEnabledAtom);
			return <span data-testid={id}>{String(enabled)}</span>;
		}
		function Toggle() {
			const setEnabled = useSetAtom(microphoneEnabledAtom);
			return <button onClick={() => setEnabled(true)}>Enable Mic</button>;
		}

		renderWithStore(
			<>
				<Display id="c1" />
				<Display id="c2" />
				<Display id="c3" />
				<Toggle />
			</>,
		);

		fireEvent.click(screen.getByText("Enable Mic"));

		expect(screen.getByTestId("c1").textContent).toBe("true");
		expect(screen.getByTestId("c2").textContent).toBe("true");
		expect(screen.getByTestId("c3").textContent).toBe("true");
	});
});

// ─── 7. Conditional rendering based on atom state ────────────────────────────

describe("conditional rendering based on atom state", () => {
	it("shows recording UI only when launchViewAtom is 'recording'", () => {
		function ConditionalView() {
			const view = useAtomValue(launchViewAtom);
			return (
				<div>
					{view === "recording" && <div data-testid="rec-ui">Recording…</div>}
					{view !== "recording" && <div data-testid="idle-ui">Idle</div>}
				</div>
			);
		}
		const { store } = renderWithStore(<ConditionalView />);

		expect(screen.getByTestId("idle-ui")).toBeTruthy();
		expect(screen.queryByTestId("rec-ui")).toBeNull();

		act(() => { store.set(launchViewAtom, "recording"); });

		expect(screen.getByTestId("rec-ui")).toBeTruthy();
		expect(screen.queryByTestId("idle-ui")).toBeNull();
	});

	it("shows export dialog only when showExportDialogAtom is true", () => {
		function ExportDialog() {
			const show = useAtomValue(showExportDialogAtom);
			return show ? <div data-testid="export-dialog">Export</div> : null;
		}
		const { store } = renderWithStore(<ExportDialog />);

		expect(screen.queryByTestId("export-dialog")).toBeNull();
		act(() => { store.set(showExportDialogAtom, true); });
		expect(screen.getByTestId("export-dialog")).toBeTruthy();
		act(() => { store.set(showExportDialogAtom, false); });
		expect(screen.queryByTestId("export-dialog")).toBeNull();
	});

	it("shows error banner only when videoErrorAtom is non-null", () => {
		function ErrorBanner() {
			const error = useAtomValue(videoErrorAtom);
			return error ? <div data-testid="error">{error}</div> : null;
		}
		const { store } = renderWithStore(<ErrorBanner />);

		expect(screen.queryByTestId("error")).toBeNull();
		act(() => { store.set(videoErrorAtom, "Decode failed"); });
		expect(screen.getByTestId("error").textContent).toBe("Decode failed");
		act(() => { store.set(videoErrorAtom, null); });
		expect(screen.queryByTestId("error")).toBeNull();
	});

	it("shows crop modal only when settingsShowCropModalAtom is true", () => {
		function CropModal() {
			const show = useAtomValue(settingsShowCropModalAtom);
			return show ? <div data-testid="crop-modal">Crop</div> : null;
		}
		function OpenButton() {
			const setShow = useSetAtom(settingsShowCropModalAtom);
			return <button onClick={() => setShow(true)}>Open Crop</button>;
		}
		renderWithStore(
			<>
				<CropModal />
				<OpenButton />
			</>,
		);

		expect(screen.queryByTestId("crop-modal")).toBeNull();
		fireEvent.click(screen.getByText("Open Crop"));
		expect(screen.getByTestId("crop-modal")).toBeTruthy();
	});

	it("hides camera panel when cameraEnabledAtom is false", () => {
		function CameraPanel() {
			const enabled = useAtomValue(cameraEnabledAtom);
			return enabled ? <div data-testid="cam-panel">Camera active</div> : null;
		}
		const { store } = renderWithStore(<CameraPanel />);

		expect(screen.queryByTestId("cam-panel")).toBeNull();
		act(() => { store.set(cameraEnabledAtom, true); });
		expect(screen.getByTestId("cam-panel")).toBeTruthy();
	});

	it("shows exporting indicator when isExportingAtom is true", () => {
		function ExportIndicator() {
			const exporting = useAtomValue(isExportingAtom);
			return exporting ? <div data-testid="exporting">Exporting…</div> : null;
		}
		const { store } = renderWithStore(<ExportIndicator />);

		expect(screen.queryByTestId("exporting")).toBeNull();
		act(() => { store.set(isExportingAtom, true); });
		expect(screen.getByTestId("exporting")).toBeTruthy();
	});
});

// ─── 8. Provider-store isolation ─────────────────────────────────────────────

describe("Provider-store isolation", () => {
	it("two separate Providers do not share atom state", () => {
		function Display({ id }: { id: string }) {
			const view = useAtomValue(launchViewAtom);
			return <span data-testid={id}>{view}</span>;
		}

		const storeA = createStore();
		const storeB = createStore();
		storeA.set(launchViewAtom, "recording");

		render(
			<>
				<Provider store={storeA}>
					<Display id="storeA" />
				</Provider>
				<Provider store={storeB}>
					<Display id="storeB" />
				</Provider>
			</>,
		);

		expect(screen.getByTestId("storeA").textContent).toBe("recording");
		expect(screen.getByTestId("storeB").textContent).toBe("choice");
	});

	it("writing to storeA does not cause storeB component to re-render", () => {
		let storeBRenders = 0;

		function StoreBDisplay() {
			storeBRenders++;
			const view = useAtomValue(launchViewAtom);
			return <span>{view}</span>;
		}

		const storeA = createStore();
		const storeB = createStore();

		render(
			<>
				<Provider store={storeA}>
					{/* intentionally empty – just to hold storeA */}
					<span />
				</Provider>
				<Provider store={storeB}>
					<StoreBDisplay />
				</Provider>
			</>,
		);

		const before = storeBRenders;
		act(() => { storeA.set(launchViewAtom, "screenshot"); });
		expect(storeBRenders).toBe(before); // storeB component did NOT re-render
	});

	it("screenshotModeAtom changes in storeA are invisible to storeB component", () => {
		function ModeDisplay() {
			const mode = useAtomValue(screenshotModeAtom);
			return <span data-testid="mode">{mode ?? "none"}</span>;
		}

		const storeA = createStore();
		const storeB = createStore();

		render(
			<Provider store={storeB}>
				<ModeDisplay />
			</Provider>,
		);

		act(() => { storeA.set(screenshotModeAtom, "area"); });

		// storeB's component still shows the default
		expect(screen.getByTestId("mode").textContent).toBe("none");
	});

	it("initialising a store with preset values is visible to its Provider's children", () => {
		const store = createStore();
		store.set(launchViewAtom, "onboarding");
		store.set(selectedSourceAtom, "External Monitor");
		store.set(hasSelectedSourceAtom, false);

		function Summary() {
			const view = useAtomValue(launchViewAtom);
			const source = useAtomValue(selectedSourceAtom);
			const selected = useAtomValue(hasSelectedSourceAtom);
			return (
				<div>
					<span data-testid="view">{view}</span>
					<span data-testid="source">{source}</span>
					<span data-testid="selected">{String(selected)}</span>
				</div>
			);
		}

		render(
			<Provider store={store}>
				<Summary />
			</Provider>,
		);

		expect(screen.getByTestId("view").textContent).toBe("onboarding");
		expect(screen.getByTestId("source").textContent).toBe("External Monitor");
		expect(screen.getByTestId("selected").textContent).toBe("false");
	});
});
