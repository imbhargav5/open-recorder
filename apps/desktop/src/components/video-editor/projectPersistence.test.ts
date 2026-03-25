import { describe, expect, it } from "vitest";
import { createProjectData, normalizeProjectEditor, PROJECT_VERSION } from "./projectPersistence";

describe("projectPersistence", () => {
	it("defaults audio settings when loading older editor snapshots", () => {
		const normalized = normalizeProjectEditor({
			wallpaper: "#000000",
		});

		expect(normalized.audioMuted).toBe(false);
		expect(normalized.audioVolume).toBe(1);
	});

	it("persists audio settings in created project data", () => {
		const editor = normalizeProjectEditor({
			wallpaper: "#111111",
			audioMuted: true,
			audioVolume: 0.35,
		});

		const project = createProjectData("/tmp/demo.mp4", editor);

		expect(project.version).toBe(PROJECT_VERSION);
		expect(project.editor.audioMuted).toBe(true);
		expect(project.editor.audioVolume).toBe(0.35);
	});

	it("persists source metadata for reopened editor titles", () => {
		const project = createProjectData(
			"/tmp/demo.mp4",
			normalizeProjectEditor({ wallpaper: "#000" }),
			{
				sourceName: "Display 1",
			},
		);

		expect(project.sourceName).toBe("Display 1");
	});
});
