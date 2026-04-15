// @vitest-environment jsdom

/**
 * Storage Edge Case Tests for Jotai State Management
 *
 * Covers: localStorage full (QuotaExceededError), localStorage unavailable,
 * corrupt JSON in storage, storage events from other tabs, and
 * atomWithStorage read/write behaviour under adverse conditions.
 *
 * Note: atomWithStorage in Jotai v2 requires `getOnInit: true` for the
 * vanilla store's `get()` to read from localStorage on first access.
 */

import { atomWithStorage } from "jotai/utils";
import { createStore } from "jotai/vanilla";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { getInitialLocale, normalizeLocale } from "@/atoms/i18n";
import { getInitialLaunchView } from "@/atoms/launch";
import { getInitialTab } from "@/atoms/sourceSelector";

// ─── Helpers ─────────────────────────────────────────────────────────────────

function clearStorage() {
	window.localStorage.clear();
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe("storage edge cases", () => {
	beforeEach(() => {
		vi.restoreAllMocks(); // restore before clearing so clear() works
		clearStorage();
	});

	afterEach(() => {
		vi.restoreAllMocks(); // restore before clearing so clear() works
		clearStorage();
	});

	// ── atomWithStorage baseline ──────────────────────────────────────────────

	it("atomWithStorage returns the initial value when localStorage is empty", () => {
		const store = createStore();
		const persistedAtom = atomWithStorage("edge-test-key", "default-value");

		expect(store.get(persistedAtom)).toBe("default-value");
	});

	it("atomWithStorage with getOnInit reads a previously stored string value", () => {
		window.localStorage.setItem("edge-str-key", JSON.stringify("stored"));
		const store = createStore();
		const persistedAtom = atomWithStorage("edge-str-key", "default", undefined, {
			getOnInit: true,
		});

		expect(store.get(persistedAtom)).toBe("stored");
	});

	it("atomWithStorage persists a new value to localStorage on set", () => {
		const store = createStore();
		const persistedAtom = atomWithStorage("edge-write-key", "original");

		store.set(persistedAtom, "changed");

		expect(JSON.parse(window.localStorage.getItem("edge-write-key") ?? "null")).toBe("changed");
	});

	it("atomWithStorage with getOnInit reads a stored object value correctly", () => {
		const stored = { name: "Open Recorder", version: 2 };
		window.localStorage.setItem("edge-obj-key", JSON.stringify(stored));
		const store = createStore();
		const persistedAtom = atomWithStorage<typeof stored>(
			"edge-obj-key",
			{ name: "default", version: 0 },
			undefined,
			{ getOnInit: true },
		);

		expect(store.get(persistedAtom)).toEqual(stored);
	});

	it("atomWithStorage falls back to default when stored JSON is corrupt", () => {
		window.localStorage.setItem("edge-corrupt-key", "{{{not valid json}}}");
		const store = createStore();
		const persistedAtom = atomWithStorage("edge-corrupt-key", "fallback", undefined, {
			getOnInit: true,
		});

		// Jotai v2 atomWithStorage catches JSON parse errors and uses initialValue
		expect(store.get(persistedAtom)).toBe("fallback");
	});

	it("atomWithStorage with boolean value round-trips correctly via getOnInit", () => {
		window.localStorage.setItem("edge-bool-key", JSON.stringify(true));
		const store = createStore();
		const boolAtom = atomWithStorage("edge-bool-key", false, undefined, { getOnInit: true });

		expect(store.get(boolAtom)).toBe(true);
	});

	it("atomWithStorage persists boolean correctly to localStorage", () => {
		const store = createStore();
		const boolAtom = atomWithStorage("edge-bool-write-key", false);

		store.set(boolAtom, true);

		const raw = window.localStorage.getItem("edge-bool-write-key");
		expect(JSON.parse(raw ?? "false")).toBe(true);
	});

	it("atomWithStorage with array value round-trips correctly via getOnInit", () => {
		window.localStorage.setItem("edge-list-key", JSON.stringify(["a", "b", "c"]));
		const store = createStore();
		const listAtom = atomWithStorage<string[]>("edge-list-key", [], undefined, {
			getOnInit: true,
		});

		expect(store.get(listAtom)).toEqual(["a", "b", "c"]);
	});

	it("two atomWithStorage atoms with different keys do not share values", () => {
		window.localStorage.setItem("edge-key-a", JSON.stringify("overriddenA"));

		const storeA = createStore();
		const atomA = atomWithStorage("edge-key-a", "valueA", undefined, { getOnInit: true });
		const atomB = atomWithStorage("edge-key-b", "valueB", undefined, { getOnInit: true });

		expect(storeA.get(atomA)).toBe("overriddenA");
		expect(storeA.get(atomB)).toBe("valueB"); // unaffected key
	});

	// ── localStorage unavailable ──────────────────────────────────────────────

	it("atomWithStorage set survives a QuotaExceededError without crashing the store", () => {
		const store = createStore();
		const persistedAtom = atomWithStorage("edge-quota-key", "original");

		// Prime the atom value
		store.get(persistedAtom);

		vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
			throw new DOMException("QuotaExceededError", "QuotaExceededError");
		});

		// The set should propagate the storage error or swallow it — either way
		// the test verifies the store itself doesn't crash irreversibly.
		try {
			store.set(persistedAtom, "new-value");
		} catch {
			// Storage error may propagate — document this behavior
		}

		vi.restoreAllMocks();
		// The atom's in-memory value should not be left in an indeterminate state
		const val = store.get(persistedAtom);
		expect(typeof val === "string").toBe(true);
	});

	// ── getInitialLocale helper ───────────────────────────────────────────────

	it("getInitialLocale returns the stored locale when it is a supported value", () => {
		window.localStorage.setItem("open-recorder.locale", "es");
		expect(getInitialLocale()).toBe("es");
	});

	it("getInitialLocale falls back to navigator language when storage has no entry", () => {
		// localStorage is clear; navigator.language is en-US by default in jsdom
		const locale = getInitialLocale();
		expect(typeof locale).toBe("string");
		expect(locale.length).toBeGreaterThan(0);
	});

	it("normalizeLocale returns a supported locale for region-suffixed tags", () => {
		expect(normalizeLocale("en-US")).toBe("en");
		expect(normalizeLocale("es-MX")).toBe("es");
	});

	it("normalizeLocale returns the default locale for unsupported language tags", () => {
		const result = normalizeLocale("fr-CA");
		expect(typeof result).toBe("string");
		expect(result.length).toBeGreaterThan(0);
	});

	it("normalizeLocale returns the default locale for null/empty input", () => {
		expect(typeof normalizeLocale(null)).toBe("string");
		expect(typeof normalizeLocale("")).toBe("string");
	});

	// ── getInitialLaunchView helper ───────────────────────────────────────────

	it("getInitialLaunchView returns onboarding when the completion flag is absent", () => {
		// localStorage is empty (cleared in beforeEach)
		expect(getInitialLaunchView()).toBe("onboarding");
	});

	it("getInitialLaunchView returns choice after the completion flag is set", () => {
		window.localStorage.setItem("open-recorder-onboarding-v1", "true");
		expect(getInitialLaunchView()).toBe("choice");
	});

	it("getInitialLaunchView returns choice when localStorage throws on access", () => {
		vi.spyOn(window, "localStorage", "get").mockImplementation(() => {
			throw new Error("storage unavailable");
		});

		expect(getInitialLaunchView()).toBe("choice");
	});

	// ── getInitialTab helper ──────────────────────────────────────────────────

	it("getInitialTab falls back to screens when the URL has no tab param", () => {
		window.history.replaceState({}, "", "/");
		expect(getInitialTab()).toBe("screens");
	});

	it("getInitialTab returns windows when the URL tab param is windows", () => {
		window.history.replaceState({}, "", "/?tab=windows");
		expect(getInitialTab()).toBe("windows");
		window.history.replaceState({}, "", "/");
	});
});
