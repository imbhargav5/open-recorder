import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
	getProjectsDir,
	ProjectLibrary,
	resolveAutomaticProjectPath,
	sanitizeProjectFileBaseName,
} from "./project-library";

const tempDirs: string[] = [];

async function makeTempDir() {
	const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "open-recorder-projects-"));
	tempDirs.push(dir);
	return dir;
}

afterEach(async () => {
	for (const dir of tempDirs.splice(0)) {
		await fs.promises.rm(dir, { recursive: true, force: true });
	}
});

describe("project-library paths", () => {
	it("places automatic project saves in the recordings Projects directory", async () => {
		const recordingsDir = await makeTempDir();

		await expect(
			resolveAutomaticProjectPath(recordingsDir, "Demo Clip.openrecorder"),
		).resolves.toBe(path.join(recordingsDir, "Projects", "Demo Clip.openrecorder"));
	});

	it("appends a numeric suffix when the automatic project name already exists", async () => {
		const recordingsDir = await makeTempDir();
		const projectsDir = getProjectsDir(recordingsDir);
		await fs.promises.mkdir(projectsDir, { recursive: true });
		await fs.promises.writeFile(path.join(projectsDir, "Recording.openrecorder"), "{}");

		await expect(
			resolveAutomaticProjectPath(recordingsDir, "Recording.openrecorder"),
		).resolves.toBe(path.join(projectsDir, "Recording 2.openrecorder"));
	});

	it("sanitizes project filenames", () => {
		expect(sanitizeProjectFileBaseName('Demo: "Main" / Screen?')).toBe("Demo Main Screen");
		expect(sanitizeProjectFileBaseName("...")).toBe("Untitled");
	});
});

describe("ProjectLibrary", () => {
	it("indexes saved projects and sorts by most recent open time", async () => {
		const configDir = await makeTempDir();
		const library = new ProjectLibrary(configDir);

		try {
			const older = path.join(configDir, "older.openrecorder");
			const newer = path.join(configDir, "newer.openrecorder");
			await fs.promises.writeFile(older, "{}");
			await fs.promises.writeFile(newer, "{}");

			library.upsertProject(
				older,
				{ title: "Older", recordingPath: "/recordings/older.webm", sourceName: "Display 1" },
				new Date("2026-01-01T00:00:00.000Z"),
			);
			library.upsertProject(
				newer,
				{ title: "Newer", recordingPath: "/recordings/newer.webm", sourceName: "Display 2" },
				new Date("2026-01-02T00:00:00.000Z"),
			);

			expect(library.listProjects().map((project) => project.title)).toEqual(["Newer", "Older"]);
		} finally {
			library.close();
		}
	});

	it("marks indexed projects as missing without deleting them", async () => {
		const configDir = await makeTempDir();
		const library = new ProjectLibrary(configDir);

		try {
			const projectPath = path.join(configDir, "missing.openrecorder");
			library.upsertProject(projectPath, {
				title: "Missing",
				recordingPath: null,
				sourceName: null,
			});

			expect(library.listProjects()).toMatchObject([{ path: projectPath, missing: true }]);
			expect(library.listProjects()).toHaveLength(1);
		} finally {
			library.close();
		}
	});

	it("updates last opened time without changing saved updated time", async () => {
		const configDir = await makeTempDir();
		const library = new ProjectLibrary(configDir);

		try {
			const projectPath = path.join(configDir, "demo.openrecorder");
			await fs.promises.writeFile(projectPath, "{}");

			library.upsertProject(
				projectPath,
				{ title: "Demo", recordingPath: null, sourceName: null },
				new Date("2026-01-01T00:00:00.000Z"),
			);
			library.markOpened(
				projectPath,
				{ title: "Demo", recordingPath: null, sourceName: null },
				new Date("2026-01-02T00:00:00.000Z"),
			);

			expect(library.listProjects()[0]).toMatchObject({
				updatedAt: "2026-01-01T00:00:00.000Z",
				lastOpenedAt: "2026-01-02T00:00:00.000Z",
			});
		} finally {
			library.close();
		}
	});
});
