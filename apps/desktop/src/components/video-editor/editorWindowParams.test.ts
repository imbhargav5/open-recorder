import { describe, expect, it } from "vitest";
import {
	buildEditorWindowQuery,
	buildVideoEditorNavbarTitle,
	parseEditorWindowLaunchParams,
} from "./editorWindowParams";

describe("editorWindowParams", () => {
	it("round-trips a recording session query with source metadata", () => {
		const query = buildEditorWindowQuery({
			mode: "session",
			videoPath: "/Users/demo/Videos/recording one.mp4",
			facecamVideoPath: "/Users/demo/Videos/recording one.facecam.webm",
			facecamOffsetMs: 240,
			facecamSettings: { enabled: true, shape: "circle" },
			sourceName: "Browser Window",
			showCursorOverlay: true,
		});

		expect(parseEditorWindowLaunchParams(query)).toEqual({
			mode: "session",
			videoPath: "/Users/demo/Videos/recording one.mp4",
			facecamVideoPath: "/Users/demo/Videos/recording one.facecam.webm",
			facecamOffsetMs: 240,
			facecamSettings: { enabled: true, shape: "circle" },
			sourceName: "Browser Window",
			showCursorOverlay: true,
		});
	});

	it("defaults legacy recording session queries to the non-doubled cursor behavior", () => {
		expect(
			parseEditorWindowLaunchParams(
				"?windowType=editor&editorMode=session&videoPath=file%3A%2F%2F%2FUsers%2Fdemo%2Fsession.mov",
			),
		).toEqual({
			mode: "session",
			videoPath: "/Users/demo/session.mov",
			facecamVideoPath: null,
			facecamOffsetMs: 0,
			facecamSettings: undefined,
			sourceName: null,
			showCursorOverlay: false,
		});
	});

	it("round-trips a project query", () => {
		const query = buildEditorWindowQuery({
			mode: "project",
			projectPath: "C:\\Users\\demo\\Videos\\My Edit.openrecorder",
		});

		expect(parseEditorWindowLaunchParams(query)).toEqual({
			mode: "project",
			projectPath: "C:/Users/demo/Videos/My Edit.openrecorder",
		});
	});

	it("builds a centered editor title from project/video and source names", () => {
		expect(
			buildVideoEditorNavbarTitle({
				projectPath: "/Users/demo/Edits/Launch Clip.openrecorder",
				sourceName: "Safari",
			}),
		).toBe("Launch Clip | Safari");

		expect(
			buildVideoEditorNavbarTitle({
				videoPath: "/Users/demo/Videos/Screen Capture.mov",
				sourceName: "Screen Capture",
			}),
		).toBe("Screen Capture");

		expect(
			buildVideoEditorNavbarTitle({
				sourceName: "Display 1",
			}),
		).toBe("Display 1");
	});
});
