import { beforeEach, describe, expect, it, vi } from "vitest";
import { createDefaultState } from "./state";

const createFromPath = vi.fn();
const createEmpty = vi.fn();
const buildFromTemplate = vi.fn();
const quit = vi.fn();
const setToolTip = vi.fn();
const setContextMenu = vi.fn();
const resolveHudWindow = vi.fn();
const sendToWindow = vi.fn();

const Tray = vi.fn(() => ({
	setToolTip,
	setContextMenu,
}));

vi.mock("electron", () => ({
	Tray,
	Menu: {
		buildFromTemplate,
	},
	nativeImage: {
		createFromPath,
		createEmpty,
	},
	app: {
		quit,
	},
}));

vi.mock("./window-routing.js", () => ({
	resolveHudWindow,
	sendToWindow,
}));

describe("tray routing", () => {
	beforeEach(() => {
		createFromPath.mockReset();
		createEmpty.mockReset();
		buildFromTemplate.mockReset();
		quit.mockReset();
		setToolTip.mockReset();
		setContextMenu.mockReset();
		resolveHudWindow.mockReset();
		sendToWindow.mockReset();

		createFromPath.mockReturnValue({ isEmpty: () => false });
		createEmpty.mockReturnValue({});
		buildFromTemplate.mockImplementation((template) => template);
	});

	it("delivers new-recording tray actions only to the HUD window", async () => {
		const hudWindow = { windowLabel: "hud-overlay" };
		resolveHudWindow.mockReturnValue(hudWindow);
		const { setupTray } = await import("./tray");
		const state = createDefaultState();

		setupTray("/tmp/icon.png", () => state);

		const contextMenu = buildFromTemplate.mock.calls.at(-1)?.[0];
		const newRecording = contextMenu[0];
		newRecording.click();

		expect(resolveHudWindow).toHaveBeenCalled();
		expect(sendToWindow).toHaveBeenCalledWith(hudWindow, "new-recording-from-tray", null);
		expect(sendToWindow).toHaveBeenCalledTimes(1);
	});

	it("delivers stop-recording tray actions only to the HUD window", async () => {
		const hudWindow = { windowLabel: "hud-overlay" };
		resolveHudWindow.mockReturnValue(hudWindow);
		const { updateTrayMenu, setupTray } = await import("./tray");
		const state = createDefaultState();

		setupTray("/tmp/icon.png", () => state);
		state.nativeScreenRecordingActive = true;
		updateTrayMenu(() => state);

		const contextMenu = buildFromTemplate.mock.calls.at(-1)?.[0];
		const stopRecording = contextMenu[0];
		stopRecording.click();

		expect(resolveHudWindow).toHaveBeenCalled();
		expect(sendToWindow).toHaveBeenCalledWith(hudWindow, "stop-recording-from-tray", null);
		expect(sendToWindow).toHaveBeenCalledTimes(1);
	});
});
