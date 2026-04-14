// @vitest-environment jsdom

import * as fc from "fast-check";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DEFAULT_LOCALE, SUPPORTED_LOCALES } from "@/i18n/config";
import { getInitialLocale, normalizeLocale } from "./i18n";

function setNavigatorLanguage(language: string) {
	Object.defineProperty(navigator, "language", {
		configurable: true,
		value: language,
	});
}

afterEach(() => {
	window.localStorage.clear();
	setNavigatorLanguage("en-US");
	vi.restoreAllMocks();
});

describe("i18n atom helpers", () => {
	it("normalizes supported locales with region suffixes", () => {
		expect(normalizeLocale("en-GB")).toBe("en");
		expect(normalizeLocale("es-MX")).toBe("es");
	});

	it("falls back to the default locale for unsupported values", () => {
		expect(normalizeLocale("fr-FR")).toBe(DEFAULT_LOCALE);
		expect(normalizeLocale("")).toBe(DEFAULT_LOCALE);
		expect(normalizeLocale(null)).toBe(DEFAULT_LOCALE);
	});

	it("prefers a stored locale over the browser locale", () => {
		window.localStorage.setItem("open-recorder.locale", "es");
		setNavigatorLanguage("en-US");

		expect(getInitialLocale()).toBe("es");
	});

	it("uses the browser locale when storage is empty", () => {
		setNavigatorLanguage("es-MX");

		expect(getInitialLocale()).toBe("es");
	});

	it("falls back to the default locale when both storage and browser locale are unsupported", () => {
		setNavigatorLanguage("fr-FR");

		expect(getInitialLocale()).toBe(DEFAULT_LOCALE);
	});

	it("maps arbitrary language tags to supported locales or the default locale", () => {
		fc.assert(
			fc.property(fc.string(), (locale) => {
				const normalized = normalizeLocale(locale);
				expect(SUPPORTED_LOCALES.includes(normalized)).toBe(true);
			}),
			{ numRuns: 500 },
		);
	});
});
