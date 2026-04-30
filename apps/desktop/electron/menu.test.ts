import { beforeEach, describe, expect, it, vi } from "vitest";

const buildFromTemplate = vi.fn();
const setApplicationMenu = vi.fn();
const resolveEditorWindow = vi.fn();
const resolveHudWindow = vi.fn();
const resolveProjectLoadWindow = vi.fn();
const resolveUpdateWindow = vi.fn();
const sendToWindow = vi.fn();

vi.mock("electron", () => ({
	Menu: {
		buildFromTemplate,
		setApplicationMenu,
	},
	app: {
		name: "Open Recorder",
	},
}));

vi.mock("./window-routing.js", () => ({
	resolveEditorWindow,
	resolveHudWindow,
	resolveProjectLoadWindow,
	resolveUpdateWindow,
	sendToWindow,
}));

describe("setupMenu", () => {
	beforeEach(() => {
		buildFromTemplate.mockReset();
		setApplicationMenu.mockReset();
		resolveEditorWindow.mockReset();
		resolveHudWindow.mockReset();
		resolveProjectLoadWindow.mockReset();
		resolveUpdateWindow.mockReset();
		sendToWindow.mockReset();
	});

	it("delivers save-project only to the resolved editor window", async () => {
		buildFromTemplate.mockImplementation((template) => template);
		const sourceWindow = { windowLabel: "editor-2" };
		const editorWindow = { windowLabel: "editor-2" };
		resolveEditorWindow.mockReturnValue(editorWindow);

		const { setupMenu } = await import("./menu");
		setupMenu();

		const template = buildFromTemplate.mock.calls[0][0];
		const fileMenu = template.find((item: { label?: string }) => item.label === "File");
		const saveProject = fileMenu.submenu.find(
			(item: { label?: string }) => item.label === "Save Project",
		);

		saveProject.click({}, sourceWindow);

		expect(resolveEditorWindow).toHaveBeenCalledWith(sourceWindow);
		expect(sendToWindow).toHaveBeenCalledWith(editorWindow, "menu-save-project", null);
		expect(sendToWindow).toHaveBeenCalledTimes(1);
	});

	it("routes load-project to the focused editor instead of broadcasting to the HUD", async () => {
		buildFromTemplate.mockImplementation((template) => template);
		const sourceWindow = { windowLabel: "editor-1" };
		const editorWindow = { windowLabel: "editor-1" };
		resolveProjectLoadWindow.mockReturnValue(editorWindow);

		const { setupMenu } = await import("./menu");
		setupMenu();

		const template = buildFromTemplate.mock.calls[0][0];
		const fileMenu = template.find((item: { label?: string }) => item.label === "File");
		const loadProject = fileMenu.submenu.find(
			(item: { label?: string }) => item.label === "Load Project…",
		);

		loadProject.click({}, sourceWindow);

		expect(resolveProjectLoadWindow).toHaveBeenCalledWith(sourceWindow);
		expect(sendToWindow).toHaveBeenCalledWith(editorWindow, "menu-load-project", null);
		expect(sendToWindow).toHaveBeenCalledTimes(1);
	});
});
