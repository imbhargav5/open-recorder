import { describe, expect, it, vi } from "vitest";
import { loadInitialVideoEditorState } from "./videoEditorLoadState";

function createDeferred<T>() {
	let resolve!: (value: T) => void;
	let reject!: (reason?: unknown) => void;

	const promise = new Promise<T>((res, rej) => {
		resolve = res;
		reject = rej;
	});

	return { promise, resolve, reject };
}

describe("loadInitialVideoEditorState", () => {
	it("starts the session and current-video lookups in parallel after the project-file branch is skipped", async () => {
		const videoPathDeferred = createDeferred<string | null>();
		const sessionDeferred = createDeferred<{
			screenVideoPath?: string | null;
			facecamVideoPath?: string | null;
			facecamOffsetMs?: number | null;
			facecamSettings?: unknown;
		} | null>();

		const getCurrentVideoPath = vi.fn(() => videoPathDeferred.promise);
		const getCurrentRecordingSession = vi.fn(() => sessionDeferred.promise);

		const pendingLoad = loadInitialVideoEditorState({
			loadCurrentProjectFile: async () => null,
			getCurrentVideoPath,
			getCurrentRecordingSession,
			fileUrlToPath: (value) => value.replace("file://", ""),
		});

		await Promise.resolve();

		expect(getCurrentVideoPath).toHaveBeenCalledTimes(1);
		expect(getCurrentRecordingSession).toHaveBeenCalledTimes(1);

		videoPathDeferred.resolve("file:///Users/demo/video.mp4");
		sessionDeferred.resolve({
			screenVideoPath: "file:///Users/demo/session.mov",
			facecamVideoPath: "file:///Users/demo/facecam.mov",
			facecamOffsetMs: 240,
			facecamSettings: { enabled: true },
		});

		await expect(pendingLoad).resolves.toEqual({
			kind: "session",
			sourcePath: "/Users/demo/session.mov",
			facecamSourcePath: "/Users/demo/facecam.mov",
			facecamOffsetMs: 240,
			facecamSettings: { enabled: true },
			sourceName: null,
		});
	});

	it("returns the resolved current video when there is no active recording session", async () => {
		await expect(
			loadInitialVideoEditorState({
				loadCurrentProjectFile: async () => null,
				getCurrentVideoPath: async () => "file:///Users/demo/video.mp4",
				getCurrentRecordingSession: async () => null,
				fileUrlToPath: (value) => value.replace("file://", ""),
			}),
		).resolves.toEqual({
			kind: "video",
			sourcePath: "/Users/demo/video.mp4",
			sourceName: null,
		});
	});

	it("prefers explicit editor window launch params over shared app state", async () => {
		await expect(
			loadInitialVideoEditorState({
				loadCurrentProjectFile: async () => ({
					data: { ignored: true },
					filePath: "/Users/demo/ignored.openrecorder",
				}),
				getCurrentVideoPath: async () => "file:///Users/demo/ignored-video.mp4",
				getCurrentRecordingSession: async () => ({
					screenVideoPath: "file:///Users/demo/ignored-session.mov",
				}),
				search:
					"?windowType=editor&editorMode=session&videoPath=file%3A%2F%2F%2FUsers%2Fdemo%2Fsession.mov&sourceName=Display%201",
			}),
		).resolves.toEqual({
			kind: "session",
			sourcePath: "/Users/demo/session.mov",
			facecamSourcePath: null,
			facecamOffsetMs: 0,
			facecamSettings: undefined,
			sourceName: "Display 1",
		});
	});

	it("loads a project from an explicit project path", async () => {
		await expect(
			loadInitialVideoEditorState({
				loadCurrentProjectFile: async () => null,
				getCurrentVideoPath: async () => null,
				getCurrentRecordingSession: async () => null,
				readLocalFile: async () =>
					new TextEncoder().encode(
						JSON.stringify({ version: 3, videoPath: "file:///demo.mov", editor: {} }),
					),
				search:
					"?windowType=editor&editorMode=project&projectPath=file%3A%2F%2F%2FUsers%2Fdemo%2Fedit.openrecorder",
			}),
		).resolves.toEqual({
			kind: "project",
			data: { version: 3, videoPath: "file:///demo.mov", editor: {} },
			filePath: "/Users/demo/edit.openrecorder",
		});
	});
});
