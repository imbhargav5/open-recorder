// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
	bindingsEqual,
	DEFAULT_SHORTCUTS,
	findConflict,
	formatBinding,
	matchesShortcut,
	mergeWithDefaults,
	type ShortcutBinding,
	type ShortcutsConfig,
} from "@/lib/shortcuts";
import { ShortcutsProvider, useShortcuts } from "./ShortcutsContext";

// ─── Mocks ────────────────────────────────────────────────────────────────────

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

// ─── Harness ─────────────────────────────────────────────────────────────────

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

// ─── Setup / Teardown ────────────────────────────────────────────────────────

beforeEach(() => {
	vi.resetAllMocks();
	platformUtils.isMac.mockResolvedValue(false);
	backend.getShortcuts.mockResolvedValue(null);
});

afterEach(() => {
	document.body.innerHTML = "";
});

// ─── ShortcutsContext behavior ────────────────────────────────────────────────

describe("ShortcutsContext – additional coverage", () => {
	describe("initial state", () => {
		it("starts with DEFAULT_SHORTCUTS when backend returns null", async () => {
			const harness = await mountShortcutsHarness();
			expect(harness.getCurrent().shortcuts).toEqual(DEFAULT_SHORTCUTS);
			await harness.unmount();
		});

		it("starts with isMac=false when platform detection returns false", async () => {
			const harness = await mountShortcutsHarness();
			expect(harness.getCurrent().isMac).toBe(false);
			await harness.unmount();
		});

		it("reflects isMac=true when platform is macOS", async () => {
			platformUtils.isMac.mockResolvedValue(true);

			const harness = await mountShortcutsHarness();
			expect(harness.getCurrent().isMac).toBe(true);
			await harness.unmount();
		});
	});

	describe("error handling", () => {
		it("keeps DEFAULT_SHORTCUTS when backend getShortcuts rejects", async () => {
			backend.getShortcuts.mockRejectedValue(new Error("Storage error"));

			const harness = await mountShortcutsHarness();
			expect(harness.getCurrent().shortcuts).toEqual(DEFAULT_SHORTCUTS);
			await harness.unmount();
		});

		it("keeps isMac=false when platform detection rejects", async () => {
			platformUtils.isMac.mockRejectedValue(new Error("Platform error"));

			const harness = await mountShortcutsHarness();
			expect(harness.getCurrent().isMac).toBe(false);
			await harness.unmount();
		});

		it("does not throw when persistShortcuts fails", async () => {
			backend.saveShortcuts.mockRejectedValue(new Error("Save failed"));

			const harness = await mountShortcutsHarness();

			await act(async () => {
				try {
					await harness.getCurrent().persistShortcuts();
				} catch {
					// expected to fail – just verify no unhandled crash
				}
			});

			expect(backend.saveShortcuts).toHaveBeenCalled();
			await harness.unmount();
		});
	});

	describe("setShortcuts", () => {
		it("immediately updates the shortcuts state in the atom", async () => {
			const harness = await mountShortcutsHarness();

			const newShortcuts: ShortcutsConfig = {
				...DEFAULT_SHORTCUTS,
				addZoom: { key: "q" },
			};

			await act(async () => {
				harness.getCurrent().setShortcuts(newShortcuts);
			});

			expect(harness.getCurrent().shortcuts.addZoom).toEqual({ key: "q" });
			await harness.unmount();
		});

		it("does not persist to backend until persistShortcuts is explicitly called", async () => {
			const harness = await mountShortcutsHarness();

			await act(async () => {
				harness.getCurrent().setShortcuts({ ...DEFAULT_SHORTCUTS, addTrim: { key: "x" } });
			});

			expect(backend.saveShortcuts).not.toHaveBeenCalled();
			await harness.unmount();
		});
	});

	describe("persistShortcuts", () => {
		it("saves current shortcuts when called without arguments", async () => {
			const harness = await mountShortcutsHarness();

			await act(async () => {
				await harness.getCurrent().persistShortcuts();
			});

			expect(backend.saveShortcuts).toHaveBeenCalledWith(harness.getCurrent().shortcuts);
			await harness.unmount();
		});

		it("saves the explicitly provided shortcuts config", async () => {
			const harness = await mountShortcutsHarness();

			const customShortcuts: ShortcutsConfig = {
				...DEFAULT_SHORTCUTS,
				playPause: { key: "k" },
			};

			await act(async () => {
				await harness.getCurrent().persistShortcuts(customShortcuts);
			});

			expect(backend.saveShortcuts).toHaveBeenCalledWith(customShortcuts);
			await harness.unmount();
		});

		it("calls saveShortcuts once per persistShortcuts call", async () => {
			const harness = await mountShortcutsHarness();

			await act(async () => {
				await harness.getCurrent().persistShortcuts();
				await harness.getCurrent().persistShortcuts();
			});

			expect(backend.saveShortcuts).toHaveBeenCalledTimes(2);
			await harness.unmount();
		});
	});

	describe("config dialog state", () => {
		it("isConfigOpen starts as false", async () => {
			const harness = await mountShortcutsHarness();
			expect(harness.getCurrent().isConfigOpen).toBe(false);
			await harness.unmount();
		});

		it("openConfig sets isConfigOpen=true, closeConfig sets it back to false", async () => {
			const harness = await mountShortcutsHarness();

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
	});

	describe("shortcuts merging from backend", () => {
		it("overrides only the provided keys and keeps defaults for the rest", async () => {
			backend.getShortcuts.mockResolvedValue({ addZoom: { key: "q" } });

			const harness = await mountShortcutsHarness();

			expect(harness.getCurrent().shortcuts.addZoom).toEqual({ key: "q" });
			expect(harness.getCurrent().shortcuts.playPause).toEqual(DEFAULT_SHORTCUTS.playPause);

			await harness.unmount();
		});

		it("merges multiple overrides correctly", async () => {
			backend.getShortcuts.mockResolvedValue({
				addZoom: { key: "1" },
				addTrim: { key: "2" },
				playPause: { key: "p", ctrl: true },
			});

			const harness = await mountShortcutsHarness();

			expect(harness.getCurrent().shortcuts.addZoom).toEqual({ key: "1" });
			expect(harness.getCurrent().shortcuts.addTrim).toEqual({ key: "2" });
			expect(harness.getCurrent().shortcuts.playPause).toEqual({ key: "p", ctrl: true });

			await harness.unmount();
		});
	});

	describe("useShortcuts outside provider", () => {
		it("throws when used outside <ShortcutsProvider>", async () => {
			function BrokenConsumer() {
				useShortcuts();
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
			expect(String(caughtError)).toContain(
				"useShortcuts must be used within <ShortcutsProvider>",
			);
		});
	});
});

// ─── shortcuts lib utility functions ─────────────────────────────────────────

describe("bindingsEqual", () => {
	it("returns true for identical bindings", () => {
		const a: ShortcutBinding = { key: "z", ctrl: true, shift: false };
		const b: ShortcutBinding = { key: "z", ctrl: true, shift: false };
		expect(bindingsEqual(a, b)).toBe(true);
	});

	it("returns false when keys differ", () => {
		expect(bindingsEqual({ key: "z" }, { key: "x" })).toBe(false);
	});

	it("returns false when ctrl modifier differs", () => {
		expect(bindingsEqual({ key: "z", ctrl: true }, { key: "z" })).toBe(false);
	});

	it("returns false when shift modifier differs", () => {
		expect(bindingsEqual({ key: "z", shift: true }, { key: "z" })).toBe(false);
	});

	it("returns false when alt modifier differs", () => {
		expect(bindingsEqual({ key: "z", alt: true }, { key: "z" })).toBe(false);
	});

	it("is case-insensitive for key comparison", () => {
		expect(bindingsEqual({ key: "Z" }, { key: "z" })).toBe(true);
	});

	it("treats undefined and false as equivalent for modifier flags", () => {
		expect(bindingsEqual({ key: "a", ctrl: false }, { key: "a" })).toBe(true);
	});
});

describe("findConflict", () => {
	it("returns null when there is no conflict", () => {
		const result = findConflict({ key: "q" }, "addZoom", DEFAULT_SHORTCUTS);
		expect(result).toBeNull();
	});

	it("detects a conflict with a fixed shortcut (tab key)", () => {
		const result = findConflict({ key: "tab" }, "addZoom", DEFAULT_SHORTCUTS);
		expect(result).not.toBeNull();
		expect(result?.type).toBe("fixed");
	});

	it("detects a conflict with another configurable action", () => {
		// addTrim default is 't' — assigning 't' to addZoom should conflict with addTrim
		const result = findConflict({ key: "t" }, "addZoom", DEFAULT_SHORTCUTS);
		expect(result).not.toBeNull();
		expect(result?.type).toBe("configurable");
		expect((result as { type: "configurable"; action: string }).action).toBe("addTrim");
	});

	it("does not flag a self-conflict when the action keeps its own binding", () => {
		const result = findConflict(DEFAULT_SHORTCUTS.addZoom, "addZoom", DEFAULT_SHORTCUTS);
		expect(result).toBeNull();
	});
});

describe("formatBinding", () => {
	it("formats a simple key on non-macOS", () => {
		expect(formatBinding({ key: "z" }, false)).toBe("Z");
	});

	it("formats Ctrl modifier on non-macOS", () => {
		expect(formatBinding({ key: "z", ctrl: true }, false)).toBe("Ctrl + Z");
	});

	it("formats ⌘ (Cmd) modifier on macOS", () => {
		expect(formatBinding({ key: "z", ctrl: true }, true)).toBe("⌘ + Z");
	});

	it("formats Shift+Alt combination on non-macOS", () => {
		expect(formatBinding({ key: "a", shift: true, alt: true }, false)).toBe("Shift + Alt + A");
	});

	it("uses the human-readable label for space key", () => {
		expect(formatBinding({ key: " " }, false)).toBe("Space");
	});
});

describe("matchesShortcut", () => {
	function makeKeyboardEvent(
		key: string,
		{
			ctrlKey = false,
			metaKey = false,
			shiftKey = false,
			altKey = false,
		}: Partial<{
			ctrlKey: boolean;
			metaKey: boolean;
			shiftKey: boolean;
			altKey: boolean;
		}> = {},
	): KeyboardEvent {
		return { key, ctrlKey, metaKey, shiftKey, altKey } as KeyboardEvent;
	}

	it("matches a simple key press", () => {
		expect(matchesShortcut(makeKeyboardEvent("z"), { key: "z" }, false)).toBe(true);
	});

	it("returns false for wrong key", () => {
		expect(matchesShortcut(makeKeyboardEvent("x"), { key: "z" }, false)).toBe(false);
	});

	it("matches Ctrl+key on non-macOS using ctrlKey", () => {
		expect(
			matchesShortcut(makeKeyboardEvent("z", { ctrlKey: true }), { key: "z", ctrl: true }, false),
		).toBe(true);
	});

	it("matches Cmd+key on macOS using metaKey", () => {
		expect(
			matchesShortcut(makeKeyboardEvent("z", { metaKey: true }), { key: "z", ctrl: true }, true),
		).toBe(true);
	});

	it("returns false when modifier is required but not pressed", () => {
		expect(matchesShortcut(makeKeyboardEvent("z"), { key: "z", ctrl: true }, false)).toBe(false);
	});

	it("is case-insensitive for the key comparison", () => {
		expect(matchesShortcut(makeKeyboardEvent("Z"), { key: "z" }, false)).toBe(true);
	});
});

describe("mergeWithDefaults", () => {
	it("returns all DEFAULT_SHORTCUTS when partial is empty", () => {
		expect(mergeWithDefaults({})).toEqual(DEFAULT_SHORTCUTS);
	});

	it("overrides a specific action while keeping the rest as defaults", () => {
		const result = mergeWithDefaults({ addZoom: { key: "q" } });
		expect(result.addZoom).toEqual({ key: "q" });
		expect(result.addTrim).toEqual(DEFAULT_SHORTCUTS.addTrim);
	});

	it("does not mutate the DEFAULT_SHORTCUTS object", () => {
		const before = { ...DEFAULT_SHORTCUTS };
		mergeWithDefaults({ addZoom: { key: "q" } });
		expect(DEFAULT_SHORTCUTS).toEqual(before);
	});

	it("merges multiple partial overrides in one call", () => {
		const result = mergeWithDefaults({
			addZoom: { key: "1" },
			addTrim: { key: "2" },
		});
		expect(result.addZoom).toEqual({ key: "1" });
		expect(result.addTrim).toEqual({ key: "2" });
		expect(result.playPause).toEqual(DEFAULT_SHORTCUTS.playPause);
	});
});
