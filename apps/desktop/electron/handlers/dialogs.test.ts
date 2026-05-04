import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createDefaultState } from "../state";
import { registerDialogHandlers } from "./dialogs";

const mocks = vi.hoisted(() => ({
	showSaveDialog: vi.fn(),
	showOpenDialog: vi.fn(),
}));

vi.mock("electron", () => ({
	dialog: {
		showSaveDialog: mocks.showSaveDialog,
		showOpenDialog: mocks.showOpenDialog,
	},
}));

const tempDirs: string[] = [];
const cleanups: Array<() => void> = [];

async function makeTempDir() {
	const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "open-recorder-dialogs-"));
	tempDirs.push(dir);
	return dir;
}

async function registerHandlers() {
	const handlers = new Map<string, (args: unknown) => unknown>();
	const state = createDefaultState();
	const recordingsDir = await makeTempDir();
	const configDir = await makeTempDir();

	const cleanup = registerDialogHandlers(
		(channel, handler) => {
			handlers.set(channel, handler);
		},
		() => state,
		(updater) => updater(state),
		() => recordingsDir,
		() => configDir,
	);
	cleanups.push(cleanup.close);

	return { handlers, state, recordingsDir };
}

afterEach(async () => {
	for (const cleanup of cleanups.splice(0)) {
		cleanup();
	}
	for (const dir of tempDirs.splice(0)) {
		await fs.promises.rm(dir, { recursive: true, force: true });
	}
});

beforeEach(() => {
	mocks.showSaveDialog.mockReset();
	mocks.showOpenDialog.mockReset();
});

describe("dialog project handlers", () => {
	it("saves a new project to the standard Projects directory without prompting", async () => {
		const { handlers, state, recordingsDir } = await registerHandlers();
		const saveProject = handlers.get("save_project_file");

		const savedPath = await saveProject?.({
			data: JSON.stringify({ version: 4, videoPath: "/recordings/demo.webm", editor: {} }),
			suggestedName: "Demo.webm",
		});

		expect(mocks.showSaveDialog).not.toHaveBeenCalled();
		expect(savedPath).toBe(path.join(recordingsDir, "Projects", "Demo.openrecorder"));
		expect(state.currentProjectPath).toBe(savedPath);
		await expect(fs.promises.readFile(String(savedPath), "utf-8")).resolves.toContain(
			"/recordings/demo.webm",
		);
	});

	it("prompts for Save As even when no existing path is present", async () => {
		const { handlers } = await registerHandlers();
		const chosenPath = path.join(await makeTempDir(), "Chosen.openrecorder");
		mocks.showSaveDialog.mockResolvedValue({ canceled: false, filePath: chosenPath });

		const savedPath = await handlers.get("save_project_file")?.({
			data: JSON.stringify({ version: 4, videoPath: "/recordings/demo.webm", editor: {} }),
			suggestedName: "Demo.openrecorder",
			forceSaveAs: true,
		});

		expect(mocks.showSaveDialog).toHaveBeenCalledTimes(1);
		expect(savedPath).toBe(chosenPath);
	});

	it("overwrites an existing path without prompting", async () => {
		const { handlers } = await registerHandlers();
		const existingPath = path.join(await makeTempDir(), "Existing.openrecorder");
		await fs.promises.writeFile(existingPath, "old");

		const savedPath = await handlers.get("save_project_file")?.({
			data: JSON.stringify({ version: 4, videoPath: "/recordings/new.webm", editor: {} }),
			suggestedName: "New.openrecorder",
			existingPath,
		});

		expect(mocks.showSaveDialog).not.toHaveBeenCalled();
		expect(savedPath).toBe(existingPath);
		await expect(fs.promises.readFile(existingPath, "utf-8")).resolves.toContain(
			"/recordings/new.webm",
		);
	});

	it("indexes saved projects and marks deleted files as missing", async () => {
		const { handlers } = await registerHandlers();
		const savedPath = String(
			await handlers.get("save_project_file")?.({
				data: JSON.stringify({ version: 4, videoPath: "/recordings/demo.webm", editor: {} }),
				suggestedName: "Demo.openrecorder",
			}),
		);

		await fs.promises.unlink(savedPath);
		const projects = await handlers.get("list_projects")?.({});

		expect(projects).toMatchObject([{ path: savedPath, title: "Demo", missing: true }]);
	});
});
