// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { normalizeLocale } from "@/atoms/i18n";
import type { I18nNamespace } from "@/i18n/config";
import { I18nProvider, useI18n, useScopedT } from "./I18nContext";

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// ─── Harness ─────────────────────────────────────────────────────────────────

type HarnessResult = {
	getCurrent: () => ReturnType<typeof useI18n>;
	unmount: () => Promise<void>;
};

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function mountI18nHarness(): Promise<HarnessResult> {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);
	const store = createStore();
	let currentValue!: ReturnType<typeof useI18n>;

	function Harness() {
		currentValue = useI18n();
		return null;
	}

	await act(async () => {
		root.render(
			<Provider store={store}>
				<I18nProvider>
					<Harness />
				</I18nProvider>
			</Provider>,
		);
	});
	await flushEffects();

	return {
		getCurrent: () => currentValue,
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
			container.remove();
		},
	};
}

async function mountScopedTHarness(namespace: I18nNamespace) {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);
	const store = createStore();
	let scopedT!: ReturnType<typeof useScopedT>;

	function Harness() {
		scopedT = useScopedT(namespace);
		return null;
	}

	await act(async () => {
		root.render(
			<Provider store={store}>
				<I18nProvider>
					<Harness />
				</I18nProvider>
			</Provider>,
		);
	});
	await flushEffects();

	return {
		t: () => scopedT,
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
			container.remove();
		},
	};
}

// ─── Setup / Teardown ────────────────────────────────────────────────────────

afterEach(() => {
	document.body.innerHTML = "";
	window.localStorage.clear();
	document.documentElement.lang = "en";
});

// ─── I18nContext behavior ─────────────────────────────────────────────────────

describe("I18nContext – additional coverage", () => {
	describe("default locale", () => {
		it("starts with locale 'en'", async () => {
			const harness = await mountI18nHarness();
			expect(harness.getCurrent().locale).toBe("en");
			await harness.unmount();
		});

		it("sets document.documentElement.lang to 'en' on initial mount", async () => {
			const harness = await mountI18nHarness();
			expect(document.documentElement.lang).toBe("en");
			await harness.unmount();
		});
	});

	describe("translation function t()", () => {
		it("resolves a known top-level English key", async () => {
			const harness = await mountI18nHarness();
			expect(harness.getCurrent().t("common.app.name")).toBe("Open Recorder");
			await harness.unmount();
		});

		it("resolves a deeply nested key", async () => {
			const harness = await mountI18nHarness();
			expect(harness.getCurrent().t("common.app.editorTitle")).toBe("Open Recorder Editor");
			await harness.unmount();
		});

		it("returns the explicit fallback string for a missing key", async () => {
			const harness = await mountI18nHarness();
			expect(harness.getCurrent().t("totally.missing.key", "Fallback Value")).toBe(
				"Fallback Value",
			);
			await harness.unmount();
		});

		it("returns the key itself when no fallback is provided and key is missing", async () => {
			const harness = await mountI18nHarness();
			expect(harness.getCurrent().t("no.such.key")).toBe("no.such.key");
			await harness.unmount();
		});

		it("interpolates {{ variable }} placeholders in the fallback string", async () => {
			const harness = await mountI18nHarness();
			const result = harness.getCurrent().t("missing.key", "Hello {{ name }}!", { name: "World" });
			expect(result).toBe("Hello World!");
			await harness.unmount();
		});

		it("interpolates numeric variables", async () => {
			const harness = await mountI18nHarness();
			const result = harness.getCurrent().t("missing.key", "Count: {{ count }}", { count: 42 });
			expect(result).toBe("Count: 42");
			await harness.unmount();
		});

		it("replaces a missing variable with an empty string", async () => {
			const harness = await mountI18nHarness();
			const result = harness
				.getCurrent()
				.t("missing.key", "Hello {{ name }}!", {} as Record<string, string>);
			expect(result).toBe("Hello !");
			await harness.unmount();
		});

		it("falls back to English when a key is absent in the active locale", async () => {
			const harness = await mountI18nHarness();

			await act(async () => {
				harness.getCurrent().setLocale("es");
			});
			await flushEffects();

			// common.app.name exists in both locales as "Open Recorder"
			expect(harness.getCurrent().t("common.app.name")).toBe("Open Recorder");
			await harness.unmount();
		});
	});

	describe("locale switching", () => {
		it("switches locale from en to es and updates the atom", async () => {
			const harness = await mountI18nHarness();
			expect(harness.getCurrent().locale).toBe("en");

			await act(async () => {
				harness.getCurrent().setLocale("es");
			});
			await flushEffects();

			expect(harness.getCurrent().locale).toBe("es");
			await harness.unmount();
		});

		it("updates document.documentElement.lang when locale changes", async () => {
			const harness = await mountI18nHarness();

			await act(async () => {
				harness.getCurrent().setLocale("es");
			});
			await flushEffects();

			expect(document.documentElement.lang).toBe("es");
			await harness.unmount();
		});

		it("t() returns the Spanish translation after switching to es", async () => {
			const harness = await mountI18nHarness();

			await act(async () => {
				harness.getCurrent().setLocale("es");
			});
			await flushEffects();

			expect(harness.getCurrent().t("common.app.subtitle")).toBe(
				"Grabacion de pantalla y edicion",
			);
			await harness.unmount();
		});

		it("can switch back from es to en and restores English translations", async () => {
			const harness = await mountI18nHarness();

			await act(async () => {
				harness.getCurrent().setLocale("es");
			});
			await flushEffects();

			await act(async () => {
				harness.getCurrent().setLocale("en");
			});
			await flushEffects();

			expect(harness.getCurrent().locale).toBe("en");
			expect(harness.getCurrent().t("common.app.subtitle")).toBe("Screen recording and editing");
			await harness.unmount();
		});
	});
});

// ── useScopedT ───────────────────────────────────────────────────────────────

describe("useScopedT", () => {
	it("prepends the namespace to the key so scoped lookups resolve correctly", async () => {
		const h = await mountScopedTHarness("common");
		// "app.name" under the "common" namespace → "Open Recorder"
		expect(h.t()("app.name")).toBe("Open Recorder");
		await h.unmount();
	});

	it("passes through the fallback parameter", async () => {
		const h = await mountScopedTHarness("common");
		expect(h.t()("nonexistent.key", "My Fallback")).toBe("My Fallback");
		await h.unmount();
	});

	it("passes through the vars parameter for interpolation", async () => {
		const h = await mountScopedTHarness("common");
		expect(h.t()("missing", "Hello {{ who }}", { who: "Test" })).toBe("Hello Test");
		await h.unmount();
	});

	it("throws when used outside <I18nProvider>", async () => {
		function BrokenConsumer() {
			useScopedT("common");
			return null;
		}

		const container = document.createElement("div");
		const root = createRoot(container);
		const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);
		let caughtError: unknown;

		try {
			await act(async () => {
				root.render(<BrokenConsumer />);
			});
		} catch (error) {
			caughtError = error;
		} finally {
			consoleError.mockRestore();
			await act(async () => {
				root.unmount();
			});
		}

		expect(caughtError).toBeDefined();
		expect(String(caughtError)).toContain("useI18n must be used within <I18nProvider>");
	});
});

// ── normalizeLocale ──────────────────────────────────────────────────────────

describe("normalizeLocale", () => {
	it("returns 'en' for null input", () => {
		expect(normalizeLocale(null)).toBe("en");
	});

	it("returns 'en' for undefined input", () => {
		expect(normalizeLocale(undefined)).toBe("en");
	});

	it("returns 'en' for empty string", () => {
		expect(normalizeLocale("")).toBe("en");
	});

	it("normalizes 'en' to 'en'", () => {
		expect(normalizeLocale("en")).toBe("en");
	});

	it("normalizes 'es' to 'es'", () => {
		expect(normalizeLocale("es")).toBe("es");
	});

	it("strips the subtag from 'en-US' to produce 'en'", () => {
		expect(normalizeLocale("en-US")).toBe("en");
	});

	it("strips the subtag from 'es-MX' to produce 'es'", () => {
		expect(normalizeLocale("es-MX")).toBe("es");
	});

	it("falls back to 'en' for an unsupported locale ('fr')", () => {
		expect(normalizeLocale("fr")).toBe("en");
	});

	it("is case-insensitive ('EN' normalizes to 'en')", () => {
		expect(normalizeLocale("EN")).toBe("en");
	});

	it("is case-insensitive ('ES' normalizes to 'es')", () => {
		expect(normalizeLocale("ES")).toBe("es");
	});
});
