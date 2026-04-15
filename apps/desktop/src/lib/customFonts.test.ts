// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Use a counter so each test gets a unique font ID, bypassing the module-level loadedFonts cache
let fontCounter = 0;

function makeTestFont() {
	fontCounter++;
	return {
		id: `test-font-${fontCounter}`,
		name: `Test Font ${fontCounter}`,
		fontFamily: `TestFont${fontCounter}`,
		importUrl: `https://fonts.googleapis.com/css2?family=TestFont${fontCounter}&display=swap`,
	};
}

function mockFontsApi(opts: { resolves: boolean; available: boolean }) {
	const descriptor = Object.getOwnPropertyDescriptor(document, "fonts");
	Object.defineProperty(document, "fonts", {
		configurable: true,
		value: {
			load: vi.fn(() =>
				opts.resolves ? Promise.resolve([]) : new Promise(() => {}),
			),
			check: vi.fn(() => opts.available),
		},
	});
	return descriptor;
}

function restoreFontsApi(descriptor: PropertyDescriptor | undefined) {
	if (descriptor) {
		Object.defineProperty(document, "fonts", descriptor);
	} else {
		// @ts-expect-error - restoring prototype-inherited property
		delete document.fonts;
	}
}

describe("customFonts", () => {
	let { loadFont, loadAllCustomFonts } = {} as typeof import("./customFonts");
	let originalFontsDescriptor: PropertyDescriptor | undefined;

	beforeEach(async () => {
		document.head.innerHTML = "";
		localStorage.clear();
		originalFontsDescriptor = Object.getOwnPropertyDescriptor(document, "fonts");
		({ loadFont, loadAllCustomFonts } = await import("./customFonts"));
	});

	afterEach(() => {
		vi.useRealTimers();
		vi.restoreAllMocks();
		restoreFontsApi(originalFontsDescriptor);
	});

	describe("waitForFont (via loadFont)", () => {
		it("rejects after timeout when font.load never resolves", async () => {
			vi.useFakeTimers();
			mockFontsApi({ resolves: false, available: false });

			const font = makeTestFont();
			const promise = loadFont(font);
			// Attach a no-op rejection handler before advancing timers so that
			// Vitest's unhandled-rejection detector doesn't fire while
			// vi.advanceTimersByTimeAsync runs (the expect() handler is added after).
			promise.catch(() => {});

			// Advance past the 5 000 ms timeout inside waitForFont
			await vi.advanceTimersByTimeAsync(6000);

			await expect(promise).rejects.toThrow("Font load timeout");
		});

		it("rejects when font.load resolves but the font is not actually available", async () => {
			mockFontsApi({ resolves: true, available: false });

			const font = makeTestFont();

			await expect(loadFont(font)).rejects.toThrow(
				`Font "${font.fontFamily}" failed to load`,
			);
		});

		it("resolves when font loads and is confirmed available", async () => {
			mockFontsApi({ resolves: true, available: true });

			const font = makeTestFont();

			await expect(loadFont(font)).resolves.toBeUndefined();
		});

		it("resolves immediately for a font that was already loaded", async () => {
			mockFontsApi({ resolves: true, available: true });

			const font = makeTestFont();

			// First load registers the font
			await loadFont(font);

			// Second call should short-circuit without touching document.fonts again
			const loadSpy = (document.fonts as { load: ReturnType<typeof vi.fn> }).load;
			loadSpy.mockClear();

			await expect(loadFont(font)).resolves.toBeUndefined();
			expect(loadSpy).not.toHaveBeenCalled();
		});
	});

	describe("loadAllCustomFonts", () => {
		it("resolves with an array of voids when all fonts load", async () => {
			mockFontsApi({ resolves: true, available: true });

			const font = makeTestFont();
			localStorage.setItem("open_recorder_custom_fonts", JSON.stringify([font]));

			await expect(loadAllCustomFonts()).resolves.toEqual([undefined]);
		});

		it("rejects when any font fails to load — callers learn about the failure", async () => {
			mockFontsApi({ resolves: true, available: false });

			const font = makeTestFont();
			localStorage.setItem("open_recorder_custom_fonts", JSON.stringify([font]));

			await expect(loadAllCustomFonts()).rejects.toThrow(
				`Font "${font.fontFamily}" failed to load`,
			);
		});

		it("resolves with an empty array when no fonts are stored", async () => {
			await expect(loadAllCustomFonts()).resolves.toEqual([]);
		});
	});
});
