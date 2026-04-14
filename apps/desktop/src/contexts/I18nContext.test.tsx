// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { I18nProvider, useI18n } from "./I18nContext";

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

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

afterEach(() => {
	document.body.innerHTML = "";
	window.localStorage.clear();
	document.documentElement.lang = "en";
});

describe("I18nContext", () => {
	it("syncs the document language and resolves translations from the active locale", async () => {
		const harness = await mountI18nHarness();

		expect(document.documentElement.lang).toBe("en");
		expect(harness.getCurrent().t("common.app.subtitle")).toBe("Screen recording and editing");

		await act(async () => {
			harness.getCurrent().setLocale("es");
		});
		await flushEffects();

		expect(document.documentElement.lang).toBe("es");
		expect(harness.getCurrent().t("common.app.subtitle")).toBe("Grabacion de pantalla y edicion");
		expect(harness.getCurrent().t("missing.key", "Fallback text")).toBe("Fallback text");

		await harness.unmount();
	});

	it("throws when useI18n is used outside the provider", async () => {
		function BrokenConsumer() {
			useI18n();
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
		}

		expect(caughtError).toBeDefined();
		expect(String(caughtError)).toContain("useI18n must be used within <I18nProvider>");
	});
});
