/**
 * Jotai atom tests for launch.ts
 *
 * Tests cover:
 * - Default atom values
 * - Atom mutations (set / update)
 * - Store isolation between independent stores
 * - Subscription notifications
 */

import { createStore } from "jotai";
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

// ─── Default values ─────────────────────────────────────────────────────────

describe("launch atoms – defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("launchViewAtom defaults to 'choice'", () => {
		expect(store.get(launchViewAtom)).toBe("choice");
	});

	it("screenshotModeAtom defaults to null", () => {
		expect(store.get(screenshotModeAtom)).toBeNull();
	});

	it("isCapturingAtom defaults to false", () => {
		expect(store.get(isCapturingAtom)).toBe(false);
	});

	it("recordingStartAtom defaults to null", () => {
		expect(store.get(recordingStartAtom)).toBeNull();
	});

	it("recordingElapsedAtom defaults to 0", () => {
		expect(store.get(recordingElapsedAtom)).toBe(0);
	});

	it("selectedSourceAtom defaults to 'Main Display'", () => {
		expect(store.get(selectedSourceAtom)).toBe("Main Display");
	});

	it("hasSelectedSourceAtom defaults to true", () => {
		expect(store.get(hasSelectedSourceAtom)).toBe(true);
	});
});

// ─── Mutations ───────────────────────────────────────────────────────────────

describe("launch atoms – mutations", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can transition launchViewAtom to 'recording'", () => {
		store.set(launchViewAtom, "recording");
		expect(store.get(launchViewAtom)).toBe("recording");
	});

	it("can transition launchViewAtom to 'onboarding'", () => {
		store.set(launchViewAtom, "onboarding");
		expect(store.get(launchViewAtom)).toBe("onboarding");
	});

	it("can transition launchViewAtom to 'screenshot'", () => {
		store.set(launchViewAtom, "screenshot");
		expect(store.get(launchViewAtom)).toBe("screenshot");
	});

	it("can set screenshotModeAtom to 'screen'", () => {
		store.set(screenshotModeAtom, "screen");
		expect(store.get(screenshotModeAtom)).toBe("screen");
	});

	it("can set screenshotModeAtom to 'window'", () => {
		store.set(screenshotModeAtom, "window");
		expect(store.get(screenshotModeAtom)).toBe("window");
	});

	it("can set screenshotModeAtom to 'area'", () => {
		store.set(screenshotModeAtom, "area");
		expect(store.get(screenshotModeAtom)).toBe("area");
	});

	it("can reset screenshotModeAtom back to null", () => {
		store.set(screenshotModeAtom, "screen");
		store.set(screenshotModeAtom, null);
		expect(store.get(screenshotModeAtom)).toBeNull();
	});

	it("can mark capture as in-progress", () => {
		store.set(isCapturingAtom, true);
		expect(store.get(isCapturingAtom)).toBe(true);
	});

	it("can store a recording start timestamp", () => {
		const ts = 1_700_000_000_000;
		store.set(recordingStartAtom, ts);
		expect(store.get(recordingStartAtom)).toBe(ts);
	});

	it("can update recordingElapsedAtom to track elapsed seconds", () => {
		store.set(recordingElapsedAtom, 42);
		expect(store.get(recordingElapsedAtom)).toBe(42);
	});

	it("can change selectedSourceAtom to a window name", () => {
		store.set(selectedSourceAtom, "Safari – GitHub");
		expect(store.get(selectedSourceAtom)).toBe("Safari – GitHub");
	});

	it("can clear hasSelectedSourceAtom when no source is selected", () => {
		store.set(hasSelectedSourceAtom, false);
		expect(store.get(hasSelectedSourceAtom)).toBe(false);
	});

	it("resets recordingStartAtom back to null (unmount-cleanup pattern)", () => {
		store.set(recordingStartAtom, Date.now());
		store.set(recordingStartAtom, null);
		expect(store.get(recordingStartAtom)).toBeNull();
	});

	it("resets recordingElapsedAtom to 0 (unmount-cleanup pattern)", () => {
		store.set(recordingElapsedAtom, 99);
		store.set(recordingElapsedAtom, 0);
		expect(store.get(recordingElapsedAtom)).toBe(0);
	});
});

// ─── Store isolation ─────────────────────────────────────────────────────────

describe("launch atoms – store isolation", () => {
	it("two independent stores do not share launchViewAtom state", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(launchViewAtom, "recording");
		expect(storeB.get(launchViewAtom)).toBe("choice");
	});

	it("setting isCapturingAtom in storeA does not affect storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(isCapturingAtom, true);
		expect(storeB.get(isCapturingAtom)).toBe(false);
	});

	it("setting recordingStartAtom in storeA does not affect storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(recordingStartAtom, 12345);
		expect(storeB.get(recordingStartAtom)).toBeNull();
	});
});

// ─── Subscriptions ───────────────────────────────────────────────────────────

describe("launch atoms – subscriptions", () => {
	it("subscriber is notified when launchViewAtom changes", () => {
		const store = createStore();
		const listener = vi.fn();
		const unsub = store.sub(launchViewAtom, listener);

		store.set(launchViewAtom, "recording");
		expect(listener).toHaveBeenCalledTimes(1);

		store.set(launchViewAtom, "screenshot");
		expect(listener).toHaveBeenCalledTimes(2);

		unsub();
	});

	it("unsubscribed listener is not called after unsubscribing", () => {
		const store = createStore();
		const listener = vi.fn();
		const unsub = store.sub(launchViewAtom, listener);

		store.set(launchViewAtom, "recording");
		unsub();
		store.set(launchViewAtom, "screenshot");

		// Only the first change fires; the second is after unsub
		expect(listener).toHaveBeenCalledTimes(1);
	});

	afterEach(() => {
		vi.clearAllMocks();
	});
});
