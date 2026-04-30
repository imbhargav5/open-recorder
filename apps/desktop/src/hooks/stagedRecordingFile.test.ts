import { beforeEach, describe, expect, it, vi } from "vitest";
import {
	createStagedRecordingFileState,
	finalizeStagedRecordingFile,
	queueStagedRecordingChunk,
	resetStagedRecordingFile,
} from "./stagedRecordingFile";

describe("stagedRecordingFile", () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	it("appends chunk bytes to the staged file path", async () => {
		const state = createStagedRecordingFileState();
		const appendRecordingData = vi.fn().mockResolvedValue(undefined);
		state.path = "/tmp/recording.webm";

		await queueStagedRecordingChunk(
			state,
			{ appendRecordingData },
			new Blob([Uint8Array.from([1, 2, 3])]),
		);

		expect(appendRecordingData).toHaveBeenCalledWith(
			"/tmp/recording.webm",
			Uint8Array.from([1, 2, 3]),
		);
		expect(state.hasData).toBe(true);
		expect(state.error).toBeNull();
	});

	it("records a missing-path error and skips writes", async () => {
		const state = createStagedRecordingFileState();
		const appendRecordingData = vi.fn().mockResolvedValue(undefined);

		await queueStagedRecordingChunk(
			state,
			{ appendRecordingData },
			new Blob([Uint8Array.from([1])]),
		);

		expect(appendRecordingData).not.toHaveBeenCalled();
		expect(state.error?.message).toBe("Recording file path is not initialized");
	});

	it("deletes empty staged files during finalize", async () => {
		const state = createStagedRecordingFileState();
		state.path = "/tmp/empty.webm";
		const deleteRecordingFile = vi.fn().mockResolvedValue(undefined);
		const readLocalFile = vi.fn();
		const replaceRecordingData = vi.fn();

		const result = await finalizeStagedRecordingFile(
			state,
			{ deleteRecordingFile, readLocalFile, replaceRecordingData, appendRecordingData: vi.fn() },
			1000,
		);

		expect(result).toBeNull();
		expect(deleteRecordingFile).toHaveBeenCalledWith("/tmp/empty.webm");
		expect(readLocalFile).not.toHaveBeenCalled();
		expect(state.path).toBeNull();
		expect(state.hasData).toBe(false);
	});

	it("resets staged file state explicitly", () => {
		const state = createStagedRecordingFileState();
		state.path = "/tmp/test.webm";
		state.error = new Error("boom");
		state.hasData = true;
		state.writeChain = Promise.resolve();

		resetStagedRecordingFile(state);

		expect(state.path).toBeNull();
		expect(state.error).toBeNull();
		expect(state.hasData).toBe(false);
	});
});
