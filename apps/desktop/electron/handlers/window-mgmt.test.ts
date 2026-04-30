import { describe, expect, it, vi } from "vitest";
import { createDefaultState } from "../state";
import { registerWindowMgmtHandlers } from "./window-mgmt";

vi.mock("electron", () => {
	const BrowserWindow = {
		getAllWindows: vi.fn(() => []),
		fromWebContents: vi.fn(),
	};

	return {
		BrowserWindow,
		screen: {
			getPrimaryDisplay: vi.fn(() => ({
				workAreaSize: { width: 1440, height: 900 },
			})),
		},
	};
});

describe("window-mgmt unsaved state tracking", () => {
	it("attributes unsaved state to the sender editor window without a renderer label", async () => {
		const handlers = new Map<string, (event: { sender: unknown }, args: unknown) => unknown>();
		const state = createDefaultState();

		registerWindowMgmtHandlers(
			() => {},
			(channel, handler) => {
				handlers.set(channel, handler);
			},
			(updater) => updater(state),
			() => "http://localhost:5789",
			"/tmp/preload.cjs",
		);

		const { BrowserWindow } = await import("electron");
		vi.mocked(BrowserWindow.fromWebContents).mockReturnValue({
			windowLabel: "editor-2",
			isDestroyed: () => false,
		} as never);

		const handler = handlers.get("set_has_unsaved_changes");
		expect(handler).toBeTypeOf("function");

		handler?.({ sender: { id: "sender-1" } }, { hasChanges: true });

		expect(state.unsavedEditorWindows).toEqual(new Set(["editor-2"]));
		expect(state.hasUnsavedChanges).toBe(true);

		handler?.({ sender: { id: "sender-1" } }, { hasChanges: false });

		expect(state.unsavedEditorWindows.size).toBe(0);
		expect(state.hasUnsavedChanges).toBe(false);
	});

	it("ignores unsaved state updates from non-editor windows", async () => {
		const handlers = new Map<string, (event: { sender: unknown }, args: unknown) => unknown>();
		const state = createDefaultState();

		registerWindowMgmtHandlers(
			() => {},
			(channel, handler) => {
				handlers.set(channel, handler);
			},
			(updater) => updater(state),
			() => "http://localhost:5789",
			"/tmp/preload.cjs",
		);

		const { BrowserWindow } = await import("electron");
		vi.mocked(BrowserWindow.fromWebContents).mockReturnValue({
			windowLabel: "hud-overlay",
			isDestroyed: () => false,
		} as never);

		handlers.get("set_has_unsaved_changes")?.(
			{ sender: { id: "sender-2" } },
			{ hasChanges: true },
		);

		expect(state.unsavedEditorWindows.size).toBe(0);
		expect(state.hasUnsavedChanges).toBe(false);
	});
});
