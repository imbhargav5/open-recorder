// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DEFAULT_SHORTCUTS } from "@/lib/shortcuts";
import { ShortcutsProvider, useShortcuts } from "./ShortcutsContext";

vi.mock("@/lib/backend", () => ({
	getShortcuts: vi.fn(),
	saveShortcuts: vi.fn(),
}));

vi.mock("@/utils/platformUtils", () => ({
	isMac: vi.fn(),
}));

// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const backend = vi.mocked(await import("@/lib/backend"));
// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const platformUtils = vi.mocked(await import("@/utils/platformUtils"));

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

type HarnessResult = {
	getCurrent: () => ReturnType<typeof useShortcuts>;
	unmount: () => Promise<void>;
};

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function mountShortcutsHarness(): Promise<HarnessResult> {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);
	const store = createStore();
	let currentValue!: ReturnType<typeof useShortcuts>;

	function Harness() {
		currentValue = useShortcuts();
		return null;
	}

	await act(async () => {
		root.render(
			<Provider store={store}>
				<ShortcutsProvider>
					<Harness />
				</ShortcutsProvider>
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

beforeEach(() => {
	vi.clearAllMocks();
	platformUtils.isMac.mockResolvedValue(false);
	backend.getShortcuts.mockResolvedValue(null);
});

afterEach(() => {
	document.body.innerHTML = "";
});

describe("ShortcutsContext", () => {
	it("hydrates shortcuts from storage and tracks the detected platform", async () => {
		platformUtils.isMac.mockResolvedValue(true);
		backend.getShortcuts.mockResolvedValue({
			addZoom: { key: "x" },
			playPause: { key: "p", ctrl: true },
		});

		const harness = await mountShortcutsHarness();

		expect(harness.getCurrent().isMac).toBe(true);
		expect(harness.getCurrent().shortcuts).toMatchObject({
			...DEFAULT_SHORTCUTS,
			addZoom: { key: "x" },
			playPause: { key: "p", ctrl: true },
		});

		await harness.unmount();
	});

	it("keeps the config dialog state in Jotai-backed atoms", async () => {
		const harness = await mountShortcutsHarness();

		expect(harness.getCurrent().isConfigOpen).toBe(false);

		await act(async () => {
			harness.getCurrent().openConfig();
		});
		expect(harness.getCurrent().isConfigOpen).toBe(true);

		await act(async () => {
			harness.getCurrent().closeConfig();
		});
		expect(harness.getCurrent().isConfigOpen).toBe(false);

		await harness.unmount();
	});

	it("persists the current or explicitly provided shortcut config", async () => {
		const harness = await mountShortcutsHarness();

		await act(async () => {
			await harness.getCurrent().persistShortcuts();
		});
		expect(backend.saveShortcuts).toHaveBeenCalledWith(harness.getCurrent().shortcuts);

		const customShortcuts = {
			...DEFAULT_SHORTCUTS,
			addZoom: { key: "q" },
		};

		await act(async () => {
			await harness.getCurrent().persistShortcuts(customShortcuts);
		});
		expect(backend.saveShortcuts).toHaveBeenLastCalledWith(customShortcuts);

		await harness.unmount();
	});
});
