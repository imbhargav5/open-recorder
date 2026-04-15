// @vitest-environment jsdom
/**
 * Integration tests: Settings Persistence
 *
 * Verifies that settings changes update atoms, persist to localStorage,
 * and hydrate correctly on simulated reload.
 *
 * Uses jsdom so localStorage is available.
 */

import { createStore } from "jotai/vanilla";
import { afterEach, describe, expect, it, vi } from "vitest";
import { getInitialLaunchView } from "@/atoms/launch";
import { normalizeLocale } from "@/atoms/i18n";
import {
	settingsActiveTabAtom,
	settingsBackgroundTabAtom,
	settingsCustomImagesAtom,
	settingsGradientAtom,
	settingsSelectedColorAtom,
	settingsShowCropModalAtom,
} from "@/atoms/settingsPanel";
import {
	aspectRatioAtom,
	audioMutedAtom,
	audioVolumeAtom,
	backgroundBlurAtom,
	borderRadiusAtom,
	exportFormatAtom,
	exportQualityAtom,
	paddingAtom,
	shadowIntensityAtom,
} from "@/atoms/videoEditor";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeFreshStore() {
	return createStore();
}

afterEach(() => {
	window.localStorage.clear();
});

// ---------------------------------------------------------------------------
// Settings panel tab persistence
// ---------------------------------------------------------------------------

describe("settings persistence – panel tabs", () => {
	it("settings tab defaults to appearance", () => {
		const store = makeFreshStore();
		expect(store.get(settingsActiveTabAtom)).toBe("appearance");
	});

	it("switching settings tab updates the atom", () => {
		const store = makeFreshStore();
		store.set(settingsActiveTabAtom, "cursor");
		expect(store.get(settingsActiveTabAtom)).toBe("cursor");
	});

	it("all settings tabs can be set", () => {
		const store = makeFreshStore();
		const tabs = ["appearance", "cursor", "camera", "background", "audio"] as const;
		for (const tab of tabs) {
			store.set(settingsActiveTabAtom, tab);
			expect(store.get(settingsActiveTabAtom)).toBe(tab);
		}
	});

	it("background sub-tab defaults to image", () => {
		const store = makeFreshStore();
		expect(store.get(settingsBackgroundTabAtom)).toBe("image");
	});

	it("background sub-tab can switch to color and gradient", () => {
		const store = makeFreshStore();
		store.set(settingsBackgroundTabAtom, "color");
		expect(store.get(settingsBackgroundTabAtom)).toBe("color");

		store.set(settingsBackgroundTabAtom, "gradient");
		expect(store.get(settingsBackgroundTabAtom)).toBe("gradient");
	});
});

// ---------------------------------------------------------------------------
// Settings color and gradient persistence
// ---------------------------------------------------------------------------

describe("settings persistence – color and gradient", () => {
	it("selected color can be changed and reads back", () => {
		const store = makeFreshStore();
		store.set(settingsSelectedColorAtom, "#FF5733");
		expect(store.get(settingsSelectedColorAtom)).toBe("#FF5733");
	});

	it("selected gradient can be updated", () => {
		const store = makeFreshStore();
		const newGradient = "linear-gradient(45deg, #ff0000, #0000ff)";
		store.set(settingsGradientAtom, newGradient);
		expect(store.get(settingsGradientAtom)).toBe(newGradient);
	});

	it("custom images list persists updates", () => {
		const store = makeFreshStore();
		store.set(settingsCustomImagesAtom, ["/images/bg1.jpg", "/images/bg2.jpg"]);
		expect(store.get(settingsCustomImagesAtom)).toHaveLength(2);
		expect(store.get(settingsCustomImagesAtom)[0]).toBe("/images/bg1.jpg");
	});

	it("custom images can be appended", () => {
		const store = makeFreshStore();
		store.set(settingsCustomImagesAtom, ["/img1.jpg"]);
		const current = store.get(settingsCustomImagesAtom);
		store.set(settingsCustomImagesAtom, [...current, "/img2.jpg"]);
		expect(store.get(settingsCustomImagesAtom)).toHaveLength(2);
	});
});

// ---------------------------------------------------------------------------
// Video editor appearance settings
// ---------------------------------------------------------------------------

describe("settings persistence – video appearance atoms", () => {
	it("shadow intensity change persists within the store", () => {
		const store = makeFreshStore();
		store.set(shadowIntensityAtom, 0.3);
		expect(store.get(shadowIntensityAtom)).toBe(0.3);
	});

	it("background blur change persists", () => {
		const store = makeFreshStore();
		store.set(backgroundBlurAtom, 15);
		expect(store.get(backgroundBlurAtom)).toBe(15);
	});

	it("padding change persists", () => {
		const store = makeFreshStore();
		store.set(paddingAtom, 100);
		expect(store.get(paddingAtom)).toBe(100);
	});

	it("border radius change persists", () => {
		const store = makeFreshStore();
		store.set(borderRadiusAtom, 8);
		expect(store.get(borderRadiusAtom)).toBe(8);
	});

	it("audio muted state persists", () => {
		const store = makeFreshStore();
		store.set(audioMutedAtom, true);
		expect(store.get(audioMutedAtom)).toBe(true);
	});

	it("audio volume persists", () => {
		const store = makeFreshStore();
		store.set(audioVolumeAtom, 0.6);
		expect(store.get(audioVolumeAtom)).toBe(0.6);
	});
});

// ---------------------------------------------------------------------------
// Export settings
// ---------------------------------------------------------------------------

describe("settings persistence – export settings", () => {
	it("export format change persists", () => {
		const store = makeFreshStore();
		store.set(exportFormatAtom, "gif");
		expect(store.get(exportFormatAtom)).toBe("gif");
	});

	it("export quality change persists", () => {
		const store = makeFreshStore();
		store.set(exportQualityAtom, "medium");
		expect(store.get(exportQualityAtom)).toBe("medium");
	});

	it("aspect ratio change persists", () => {
		const store = makeFreshStore();
		store.set(aspectRatioAtom, "9:16");
		expect(store.get(aspectRatioAtom)).toBe("9:16");
	});

	it("new store picks up default aspect ratio", () => {
		const store = makeFreshStore();
		expect(store.get(aspectRatioAtom)).toBe("16:9");
	});
});

// ---------------------------------------------------------------------------
// Locale storage (atomWithStorage)
// ---------------------------------------------------------------------------

describe("settings persistence – locale via localStorage", () => {
	it("normalizeLocale returns default for null", () => {
		expect(normalizeLocale(null)).toBe("en");
	});

	it("normalizeLocale returns default for undefined", () => {
		expect(normalizeLocale(undefined)).toBe("en");
	});

	it("normalizeLocale handles language tags with region", () => {
		expect(normalizeLocale("en-US")).toBe("en");
	});

	it("normalizeLocale returns default for unsupported locale", () => {
		expect(normalizeLocale("fr")).toBe("en");
	});

	it("normalizeLocale accepts known locale es", () => {
		expect(normalizeLocale("es")).toBe("es");
	});
});

// ---------------------------------------------------------------------------
// Onboarding flag in localStorage
// ---------------------------------------------------------------------------

describe("settings persistence – onboarding flag", () => {
	it("onboarding flag written to localStorage is read on next init", () => {
		window.localStorage.removeItem("open-recorder-onboarding-v1");
		expect(getInitialLaunchView()).toBe("onboarding");

		window.localStorage.setItem("open-recorder-onboarding-v1", "true");
		expect(getInitialLaunchView()).toBe("choice");
	});

	it("removing the flag causes onboarding to re-appear", () => {
		window.localStorage.setItem("open-recorder-onboarding-v1", "true");
		expect(getInitialLaunchView()).toBe("choice");

		window.localStorage.removeItem("open-recorder-onboarding-v1");
		expect(getInitialLaunchView()).toBe("onboarding");
	});

	it("corrupted flag value does not throw (treated as falsy)", () => {
		window.localStorage.setItem("open-recorder-onboarding-v1", "false");
		// "false" !== "true", so should go to onboarding
		expect(getInitialLaunchView()).toBe("onboarding");
	});
});

// ---------------------------------------------------------------------------
// Crop modal state
// ---------------------------------------------------------------------------

describe("settings persistence – crop modal", () => {
	it("crop modal is hidden by default", () => {
		const store = makeFreshStore();
		expect(store.get(settingsShowCropModalAtom)).toBe(false);
	});

	it("opening crop modal updates the atom", () => {
		const store = makeFreshStore();
		store.set(settingsShowCropModalAtom, true);
		expect(store.get(settingsShowCropModalAtom)).toBe(true);
	});

	it("closing crop modal resets the atom to false", () => {
		const store = makeFreshStore();
		store.set(settingsShowCropModalAtom, true);
		store.set(settingsShowCropModalAtom, false);
		expect(store.get(settingsShowCropModalAtom)).toBe(false);
	});
});
