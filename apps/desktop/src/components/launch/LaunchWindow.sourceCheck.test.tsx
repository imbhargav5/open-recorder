// @vitest-environment jsdom
/**
 * Tests for the source-checking interval error handling in LaunchWindow.
 *
 * Covers Issue #16: silent error swallowing in the setInterval callback.
 * When backend.getSelectedSource() rejects the error must be:
 *   1. Logged via console.warn
 *   2. Surfaced in sourceCheckErrorAtom (not silently dropped)
 *   3. Not cause the component to crash
 *
 * NOTE: checkSelectedSource() is invoked immediately on mount AND on each
 * interval tick. All tests validate the on-mount invocation so that no timer
 * manipulation is needed (avoiding the act()+fakeTimers deadlock).
 */

import { createStore, Provider, useAtom } from "jotai";
import { act, useEffect } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { hasSelectedSourceAtom, selectedSourceAtom, sourceCheckErrorAtom } from "@/atoms/launch";
import { resolveSelectedSourceState } from "./launchWindowState";

// ─── Mock backend ─────────────────────────────────────────────────────────────

vi.mock("@/lib/backend", () => ({
	getSelectedSource: vi.fn(),
}));

// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const backend = vi.mocked(await import("@/lib/backend"));

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function flushMicrotasks() {
	await act(async () => {
		// Drain microtasks then a macro-task so async effects settle
		await Promise.resolve();
		await new Promise<void>((resolve) => setTimeout(resolve, 0));
	});
}

/**
 * Minimal harness that replicates only the source-checking useEffect from
 * LaunchWindow so we can test its error-handling behaviour in isolation.
 *
 * `intervalMs` defaults to 500 (matching the real component) but can be
 * reduced in tests that need to observe the interval tick without fake timers.
 */
// biome-ignore lint/style/useComponentExportOnlyModules: Test-only harness mirrors LaunchWindow's source-check effect.
function SourceCheckHarness({ intervalMs = 500 }: { intervalMs?: number }) {
	const [, setSelectedSource] = useAtom(selectedSourceAtom);
	const [, setHasSelectedSource] = useAtom(hasSelectedSourceAtom);
	const [, setSourceCheckError] = useAtom(sourceCheckErrorAtom);

	useEffect(() => {
		const checkSelectedSource = async () => {
			try {
				const source = await backend.getSelectedSource();
				const nextState = resolveSelectedSourceState(source);
				setSelectedSource(nextState.selectedSource);
				setHasSelectedSource(nextState.hasSelectedSource);
				setSourceCheckError(null);
			} catch (err) {
				const error = err instanceof Error ? err : new Error(String(err));
				console.warn("[LaunchWindow] source check failed:", error);
				setSourceCheckError(error);
			}
		};

		void checkSelectedSource();
		const interval = setInterval(checkSelectedSource, intervalMs);
		return () => clearInterval(interval);
	}, [intervalMs, setHasSelectedSource, setSelectedSource, setSourceCheckError]);

	return null;
}

// ─── Mount helper ─────────────────────────────────────────────────────────────

type Harness = {
	store: ReturnType<typeof createStore>;
	unmount: () => Promise<void>;
};

async function mountHarness(opts: { intervalMs?: number } = {}): Promise<Harness> {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);
	const store = createStore();

	await act(async () => {
		root.render(
			<Provider store={store}>
				<SourceCheckHarness intervalMs={opts.intervalMs} />
			</Provider>,
		);
	});
	// Let the immediate async checkSelectedSource() call settle
	await flushMicrotasks();

	return {
		store,
		unmount: async () => {
			await act(async () => {
				root.unmount();
				container.remove();
			});
		},
	};
}

// ─── Tests ────────────────────────────────────────────────────────────────────

afterEach(() => {
	vi.restoreAllMocks();
});

describe("LaunchWindow source-check interval – error handling", () => {
	it("logs a warning when getSelectedSource rejects", async () => {
		const networkError = new Error("IPC call failed");
		backend.getSelectedSource.mockRejectedValue(networkError);
		const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => undefined);

		const { unmount } = await mountHarness();

		expect(warnSpy).toHaveBeenCalledWith("[LaunchWindow] source check failed:", networkError);

		await unmount();
	});

	it("sets sourceCheckErrorAtom when getSelectedSource rejects", async () => {
		const networkError = new Error("IPC call failed");
		backend.getSelectedSource.mockRejectedValue(networkError);
		vi.spyOn(console, "warn").mockImplementation(() => undefined);

		const { store, unmount } = await mountHarness();

		const storedError = store.get(sourceCheckErrorAtom);
		expect(storedError).toBeInstanceOf(Error);
		expect(storedError?.message).toBe("IPC call failed");

		await unmount();
	});

	it("does not crash the component when getSelectedSource rejects", async () => {
		backend.getSelectedSource.mockRejectedValue(new Error("backend down"));
		vi.spyOn(console, "warn").mockImplementation(() => undefined);

		// Should resolve without throwing – the component must stay alive
		const { unmount } = await mountHarness();
		await expect(unmount()).resolves.toBeUndefined();
	});

	it("clears sourceCheckErrorAtom when a subsequent call succeeds", async () => {
		const networkError = new Error("transient failure");
		backend.getSelectedSource
			.mockRejectedValueOnce(networkError)
			.mockResolvedValue({ name: "Display 1" });
		vi.spyOn(console, "warn").mockImplementation(() => undefined);

		// Keep the interval comfortably above mount/flush time so the initial error
		// can be observed before the recovery tick runs on slower CI hosts.
		const { store, unmount } = await mountHarness();

		// Initial (on-mount) call failed – error must be set
		expect(store.get(sourceCheckErrorAtom)).toBeInstanceOf(Error);

		// Wait for the interval to fire at least once (>500 ms) and flush React
		await act(async () => {
			await new Promise<void>((resolve) => setTimeout(resolve, 550));
		});
		await flushMicrotasks();

		// After the successful interval tick the error must be cleared
		expect(store.get(sourceCheckErrorAtom)).toBeNull();
		expect(store.get(selectedSourceAtom)).toBe("Display 1");

		await unmount();
	});

	it("does not warn or set error when getSelectedSource succeeds", async () => {
		backend.getSelectedSource.mockResolvedValue({ name: "Screen 2" });
		const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => undefined);

		const { store, unmount } = await mountHarness();

		expect(warnSpy).not.toHaveBeenCalled();
		expect(store.get(sourceCheckErrorAtom)).toBeNull();
		expect(store.get(selectedSourceAtom)).toBe("Screen 2");

		await unmount();
	});
});
