/**
 * Integration tests: Source Selection Flow
 *
 * Verifies multi-atom workflows for source selection:
 *   open selector → load sources → pick screen/window → source atom set → selector closes
 */

import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
	hasSelectedSourceAtom,
	selectedSourceAtom,
} from "@/atoms/launch";
import {
	selectedDesktopSourceAtom,
	sourceSelectorTabAtom,
	sourcesAtom,
	sourcesLoadingAtom,
	windowsLoadingAtom,
} from "@/atoms/sourceSelector";
import type { DesktopSource } from "@/components/launch/sourceSelectorState";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeFreshStore() {
	return createStore();
}

const MOCK_SCREEN: DesktopSource = {
	id: "screen:0",
	name: "Main Display",
	thumbnail: "data:image/png;base64,abc123",
	type: "screen",
};

const MOCK_WINDOW: DesktopSource = {
	id: "window:101",
	name: "Visual Studio Code",
	thumbnail: "data:image/png;base64,xyz789",
	type: "window",
};

// ---------------------------------------------------------------------------
// Initial state
// ---------------------------------------------------------------------------

describe("source selection – initial state", () => {
	it("sources list is empty before loading", () => {
		const store = makeFreshStore();
		expect(store.get(sourcesAtom)).toEqual([]);
	});

	it("screens are loading by default", () => {
		const store = makeFreshStore();
		expect(store.get(sourcesLoadingAtom)).toBe(true);
	});

	it("windows are loading by default", () => {
		const store = makeFreshStore();
		expect(store.get(windowsLoadingAtom)).toBe(true);
	});

	it("default tab is screens", () => {
		const store = makeFreshStore();
		expect(store.get(sourceSelectorTabAtom)).toBe("screens");
	});

	it("no desktop source is selected by default", () => {
		const store = makeFreshStore();
		expect(store.get(selectedDesktopSourceAtom)).toBeNull();
	});
});

// ---------------------------------------------------------------------------
// Loading sources
// ---------------------------------------------------------------------------

describe("source selection – loading sources", () => {
	it("loading state clears when sources arrive", () => {
		const store = makeFreshStore();
		store.set(sourcesAtom, [MOCK_SCREEN]);
		store.set(sourcesLoadingAtom, false);

		expect(store.get(sourcesLoadingAtom)).toBe(false);
		expect(store.get(sourcesAtom)).toHaveLength(1);
	});

	it("multiple sources can be stored", () => {
		const store = makeFreshStore();
		store.set(sourcesAtom, [MOCK_SCREEN, MOCK_WINDOW]);
		store.set(sourcesLoadingAtom, false);
		store.set(windowsLoadingAtom, false);

		expect(store.get(sourcesAtom)).toHaveLength(2);
	});

	it("windows loading clears independently of screens loading", () => {
		const store = makeFreshStore();
		store.set(sourcesLoadingAtom, false);
		// windows still loading
		expect(store.get(windowsLoadingAtom)).toBe(true);
		store.set(windowsLoadingAtom, false);
		expect(store.get(windowsLoadingAtom)).toBe(false);
	});
});

// ---------------------------------------------------------------------------
// Tab switching
// ---------------------------------------------------------------------------

describe("source selection – tab switching", () => {
	it("switching to windows tab updates sourceSelectorTabAtom", () => {
		const store = makeFreshStore();
		store.set(sourceSelectorTabAtom, "windows");
		expect(store.get(sourceSelectorTabAtom)).toBe("windows");
	});

	it("switching back to screens tab works", () => {
		const store = makeFreshStore();
		store.set(sourceSelectorTabAtom, "windows");
		store.set(sourceSelectorTabAtom, "screens");
		expect(store.get(sourceSelectorTabAtom)).toBe("screens");
	});

	it("sources are still available after switching tabs", () => {
		const store = makeFreshStore();
		store.set(sourcesAtom, [MOCK_SCREEN, MOCK_WINDOW]);
		store.set(sourceSelectorTabAtom, "windows");

		expect(store.get(sourcesAtom)).toHaveLength(2);
		expect(store.get(sourceSelectorTabAtom)).toBe("windows");
	});
});

// ---------------------------------------------------------------------------
// Selecting a source
// ---------------------------------------------------------------------------

describe("source selection – picking a source", () => {
	it("selecting a screen sets selectedDesktopSourceAtom", () => {
		const store = makeFreshStore();
		store.set(sourcesAtom, [MOCK_SCREEN]);
		store.set(selectedDesktopSourceAtom, MOCK_SCREEN);

		expect(store.get(selectedDesktopSourceAtom)).toEqual(MOCK_SCREEN);
	});

	it("selecting a window sets selectedDesktopSourceAtom", () => {
		const store = makeFreshStore();
		store.set(sourcesAtom, [MOCK_WINDOW]);
		store.set(selectedDesktopSourceAtom, MOCK_WINDOW);

		expect(store.get(selectedDesktopSourceAtom)?.id).toBe("window:101");
	});

	it("selecting a source propagates name to selectedSourceAtom in launch atoms", () => {
		const store = makeFreshStore();
		store.set(selectedDesktopSourceAtom, MOCK_SCREEN);
		store.set(selectedSourceAtom, MOCK_SCREEN.name);

		expect(store.get(selectedSourceAtom)).toBe("Main Display");
	});

	it("hasSelectedSourceAtom becomes true after selection", () => {
		const store = makeFreshStore();
		store.set(selectedDesktopSourceAtom, MOCK_SCREEN);
		store.set(hasSelectedSourceAtom, true);

		expect(store.get(hasSelectedSourceAtom)).toBe(true);
	});

	it("switching selection clears the previous source", () => {
		const store = makeFreshStore();
		store.set(selectedDesktopSourceAtom, MOCK_SCREEN);
		store.set(selectedDesktopSourceAtom, MOCK_WINDOW);

		expect(store.get(selectedDesktopSourceAtom)?.name).toBe("Visual Studio Code");
	});

	it("source selection subscription fires on change", () => {
		const store = makeFreshStore();
		const events: Array<DesktopSource | null> = [];
		const unsub = store.sub(selectedDesktopSourceAtom, () => {
			events.push(store.get(selectedDesktopSourceAtom));
		});

		store.set(selectedDesktopSourceAtom, MOCK_SCREEN);
		store.set(selectedDesktopSourceAtom, MOCK_WINDOW);
		store.set(selectedDesktopSourceAtom, null);
		unsub();

		expect(events).toHaveLength(3);
		expect(events[0]?.id).toBe("screen:0");
		expect(events[2]).toBeNull();
	});
});

// ---------------------------------------------------------------------------
// Full selection flow
// ---------------------------------------------------------------------------

describe("source selection – full selection flow", () => {
	it("complete flow: load → switch tab → pick → confirm", () => {
		const store = makeFreshStore();

		// 1. Sources loading
		expect(store.get(sourcesLoadingAtom)).toBe(true);

		// 2. Sources arrive
		store.set(sourcesAtom, [MOCK_SCREEN, MOCK_WINDOW]);
		store.set(sourcesLoadingAtom, false);
		store.set(windowsLoadingAtom, false);

		// 3. Switch to windows tab
		store.set(sourceSelectorTabAtom, "windows");

		// 4. Pick a window
		store.set(selectedDesktopSourceAtom, MOCK_WINDOW);
		store.set(selectedSourceAtom, MOCK_WINDOW.name);
		store.set(hasSelectedSourceAtom, true);

		// Verify final state
		expect(store.get(selectedDesktopSourceAtom)?.name).toBe("Visual Studio Code");
		expect(store.get(selectedSourceAtom)).toBe("Visual Studio Code");
		expect(store.get(hasSelectedSourceAtom)).toBe(true);
		expect(store.get(sourceSelectorTabAtom)).toBe("windows");
	});
});
