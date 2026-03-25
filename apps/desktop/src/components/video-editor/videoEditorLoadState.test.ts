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
		});
	});
});
