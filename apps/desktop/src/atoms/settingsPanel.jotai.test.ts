/**
 * Jotai atom tests for settingsPanel.ts
 *
 * Tests cover:
 * - Default values for all settings atoms
 * - Tab switching (sidebar + background sub-tabs)
 * - Custom image list management
 * - Color / gradient updates
 * - Crop modal visibility
 * - Store isolation
 */

import { createStore } from "jotai";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
	settingsActiveTabAtom,
	settingsBackgroundTabAtom,
	settingsCustomImagesAtom,
	settingsGradientAtom,
	settingsSelectedColorAtom,
	settingsShowCropModalAtom,
} from "./settingsPanel";

// ─── Default values ─────────────────────────────────────────────────────────

describe("settingsPanel atoms – defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("settingsActiveTabAtom defaults to 'appearance'", () => {
		expect(store.get(settingsActiveTabAtom)).toBe("appearance");
	});

	it("settingsBackgroundTabAtom defaults to 'image'", () => {
		expect(store.get(settingsBackgroundTabAtom)).toBe("image");
	});

	it("settingsCustomImagesAtom defaults to an empty array", () => {
		expect(store.get(settingsCustomImagesAtom)).toEqual([]);
	});

	it("settingsSelectedColorAtom defaults to '#ADADAD'", () => {
		expect(store.get(settingsSelectedColorAtom)).toBe("#ADADAD");
	});

	it("settingsGradientAtom defaults to a non-empty CSS string", () => {
		const gradient = store.get(settingsGradientAtom);
		expect(typeof gradient).toBe("string");
		expect(gradient.length).toBeGreaterThan(0);
		expect(gradient).toContain("linear-gradient");
	});

	it("settingsShowCropModalAtom defaults to false", () => {
		expect(store.get(settingsShowCropModalAtom)).toBe(false);
	});
});

// ─── Tab switching ───────────────────────────────────────────────────────────

describe("settingsPanel atoms – sidebar tab switching", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can switch active tab to 'cursor'", () => {
		store.set(settingsActiveTabAtom, "cursor");
		expect(store.get(settingsActiveTabAtom)).toBe("cursor");
	});

	it("can switch active tab to 'camera'", () => {
		store.set(settingsActiveTabAtom, "camera");
		expect(store.get(settingsActiveTabAtom)).toBe("camera");
	});

	it("can switch active tab to 'background'", () => {
		store.set(settingsActiveTabAtom, "background");
		expect(store.get(settingsActiveTabAtom)).toBe("background");
	});

	it("can switch active tab to 'audio'", () => {
		store.set(settingsActiveTabAtom, "audio");
		expect(store.get(settingsActiveTabAtom)).toBe("audio");
	});

	it("can switch back to 'appearance' from any tab", () => {
		store.set(settingsActiveTabAtom, "audio");
		store.set(settingsActiveTabAtom, "appearance");
		expect(store.get(settingsActiveTabAtom)).toBe("appearance");
	});
});

describe("settingsPanel atoms – background sub-tab switching", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can switch background sub-tab to 'gradient'", () => {
		store.set(settingsBackgroundTabAtom, "gradient");
		expect(store.get(settingsBackgroundTabAtom)).toBe("gradient");
	});

	it("can switch background sub-tab to 'color'", () => {
		store.set(settingsBackgroundTabAtom, "color");
		expect(store.get(settingsBackgroundTabAtom)).toBe("color");
	});

	it("can switch background sub-tab back to 'image'", () => {
		store.set(settingsBackgroundTabAtom, "gradient");
		store.set(settingsBackgroundTabAtom, "image");
		expect(store.get(settingsBackgroundTabAtom)).toBe("image");
	});
});

// ─── Custom images ───────────────────────────────────────────────────────────

describe("settingsPanel atoms – custom images", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can add custom image paths", () => {
		store.set(settingsCustomImagesAtom, ["/uploads/img1.png", "/uploads/img2.jpg"]);
		expect(store.get(settingsCustomImagesAtom)).toHaveLength(2);
	});

	it("can clear custom images back to empty array", () => {
		store.set(settingsCustomImagesAtom, ["/uploads/img1.png"]);
		store.set(settingsCustomImagesAtom, []);
		expect(store.get(settingsCustomImagesAtom)).toHaveLength(0);
	});
});

// ─── Color / gradient ────────────────────────────────────────────────────────

describe("settingsPanel atoms – color and gradient", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can update selected color to a new hex string", () => {
		store.set(settingsSelectedColorAtom, "#FF0000");
		expect(store.get(settingsSelectedColorAtom)).toBe("#FF0000");
	});

	it("can replace the gradient string", () => {
		const newGradient = "linear-gradient(to right, #f00, #00f)";
		store.set(settingsGradientAtom, newGradient);
		expect(store.get(settingsGradientAtom)).toBe(newGradient);
	});
});

// ─── Crop modal ──────────────────────────────────────────────────────────────

describe("settingsPanel atoms – crop modal visibility", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can open the crop modal", () => {
		store.set(settingsShowCropModalAtom, true);
		expect(store.get(settingsShowCropModalAtom)).toBe(true);
	});

	it("can close the crop modal after opening", () => {
		store.set(settingsShowCropModalAtom, true);
		store.set(settingsShowCropModalAtom, false);
		expect(store.get(settingsShowCropModalAtom)).toBe(false);
	});
});

// ─── Store isolation ─────────────────────────────────────────────────────────

describe("settingsPanel atoms – store isolation", () => {
	it("changing tab in storeA does not affect storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(settingsActiveTabAtom, "audio");
		expect(storeB.get(settingsActiveTabAtom)).toBe("appearance");
	});

	it("opening crop modal in storeA does not affect storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(settingsShowCropModalAtom, true);
		expect(storeB.get(settingsShowCropModalAtom)).toBe(false);
	});
});
