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
	it("returns the explicit project when the launch params include a readable project file", async () => {
		const readLocalFile = vi.fn(async () =>
			new TextEncoder().encode(
				JSON.stringify({ version: 3, videoPath: "file:///demo.mp4", editor: {} }),
			),
		);
		const loadCurrentProjectFile = vi.fn(async () => ({
			data: { ignored: true },
			filePath: "/tmp/ignored",
		}));
		const getCurrentVideoPath = vi.fn(async () => "file:///ignored.mp4");
		const getCurrentRecordingSession = vi.fn(async () => ({
			screenVideoPath: "file:///ignored-session.mov",
		}));

		await expect(
			loadInitialVideoEditorState({
				loadCurrentProjectFile,
				getCurrentVideoPath,
				getCurrentRecordingSession,
				readLocalFile,
				search:
					"?windowType=editor&editorMode=project&projectPath=file%3A%2F%2F%2Fdemo.openrecorder",
			}),
		).resolves.toEqual({
			kind: "project",
			data: { version: 3, videoPath: "file:///demo.mp4", editor: {} },
			filePath: "/demo.openrecorder",
		});

		expect(readLocalFile).toHaveBeenCalledTimes(1);
		expect(loadCurrentProjectFile).not.toHaveBeenCalled();
		expect(getCurrentVideoPath).not.toHaveBeenCalled();
		expect(getCurrentRecordingSession).not.toHaveBeenCalled();
	});

	it("falls back to shared state when an explicit project cannot be read", async () => {
		const loadCurrentProjectFile = vi.fn(async () => ({
			data: { version: 3, videoPath: "file:///shared.mp4", editor: { wallpaper: "#111" } },
			filePath: "/tmp/shared.openrecorder",
		}));
		const readLocalFile = vi.fn(async () => {
			throw new Error("boom");
		});

		await expect(
			loadInitialVideoEditorState({
				loadCurrentProjectFile,
				getCurrentVideoPath: async () => null,
				getCurrentRecordingSession: async () => null,
				readLocalFile,
				search:
					"?windowType=editor&editorMode=project&projectPath=file%3A%2F%2F%2Fbroken.openrecorder",
			}),
		).resolves.toEqual({
			kind: "project",
			data: { version: 3, videoPath: "file:///shared.mp4", editor: { wallpaper: "#111" } },
			filePath: "/tmp/shared.openrecorder",
		});
	});

	it("prefers explicit session launch params over shared state", async () => {
		const loadCurrentProjectFile = vi.fn(async () => ({ data: { ignored: true }, filePath: null }));
		const getCurrentVideoPath = vi.fn(async () => "file:///ignored-video.mp4");
		const getCurrentRecordingSession = vi.fn(async () => ({
			screenVideoPath: "file:///ignored-session.mov",
		}));

		await expect(
			loadInitialVideoEditorState({
				loadCurrentProjectFile,
				getCurrentVideoPath,
				getCurrentRecordingSession,
				search:
					"?windowType=editor&editorMode=session&videoPath=file%3A%2F%2F%2FUsers%2Fdemo%2Fsession.mov&facecamVideoPath=file%3A%2F%2F%2FUsers%2Fdemo%2Ffacecam.mov&facecamOffsetMs=240&sourceName=Display%201",
			}),
		).resolves.toEqual({
			kind: "session",
			sourcePath: "/Users/demo/session.mov",
			facecamSourcePath: "/Users/demo/facecam.mov",
			facecamOffsetMs: 240,
			facecamSettings: undefined,
			sourceName: "Display 1",
			showCursorOverlay: false,
		});

		expect(loadCurrentProjectFile).not.toHaveBeenCalled();
		expect(getCurrentVideoPath).not.toHaveBeenCalled();
		expect(getCurrentRecordingSession).not.toHaveBeenCalled();
	});

	it("prefers explicit video launch params over shared state", async () => {
		await expect(
			loadInitialVideoEditorState({
				loadCurrentProjectFile: async () => ({ data: { ignored: true }, filePath: "/tmp/ignored" }),
				getCurrentVideoPath: async () => "file:///shared.mp4",
				getCurrentRecordingSession: async () => ({
					screenVideoPath: "file:///shared-session.mov",
				}),
				search:
					"?windowType=editor&editorMode=video&videoPath=file%3A%2F%2F%2FUsers%2Fdemo%2Fvideo.mp4&sourceName=Display%201",
			}),
		).resolves.toEqual({
			kind: "video",
			sourcePath: "/Users/demo/video.mp4",
			sourceName: "Display 1",
		});
	});

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
			showCursorOverlay: false,
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

	it("returns empty when no project, session, or video is available", async () => {
		await expect(
			loadInitialVideoEditorState({
				loadCurrentProjectFile: async () => null,
				getCurrentVideoPath: async () => null,
				getCurrentRecordingSession: async () => null,
			}),
		).resolves.toEqual({
			kind: "empty",
		});
	});
});
