import { fixParsedWebmDuration } from "@fix-webm-duration/fix";
import { WebmFile } from "@fix-webm-duration/parser";

export interface StagedRecordingFileBackend {
	appendRecordingData(path: string, data: Uint8Array): Promise<void>;
	deleteRecordingFile(path: string): Promise<void>;
	readLocalFile(path: string): Promise<Uint8Array>;
	replaceRecordingData(path: string, data: Uint8Array): Promise<string>;
}

export type StagedRecordingFileState = {
	path: string | null;
	writeChain: Promise<void>;
	error: Error | null;
	hasData: boolean;
};

export function createStagedRecordingFileState(): StagedRecordingFileState {
	return {
		path: null,
		writeChain: Promise.resolve(),
		error: null,
		hasData: false,
	};
}

export function resetStagedRecordingFile(state: StagedRecordingFileState): void {
	state.path = null;
	state.writeChain = Promise.resolve();
	state.error = null;
	state.hasData = false;
}

export async function queueStagedRecordingChunk(
	state: StagedRecordingFileState,
	backend: Pick<StagedRecordingFileBackend, "appendRecordingData">,
	chunk: Blob,
): Promise<void> {
	state.hasData = true;
	state.writeChain = state.writeChain.then(async () => {
		if (state.error) {
			return;
		}

		if (!state.path) {
			state.error = new Error("Recording file path is not initialized");
			return;
		}

		try {
			const arrayBuffer = await chunk.arrayBuffer();
			await backend.appendRecordingData(state.path, new Uint8Array(arrayBuffer));
		} catch (error) {
			state.error = error instanceof Error ? error : new Error(String(error));
		}
	});

	await state.writeChain;
}

export async function finalizeStagedRecordingFile(
	state: StagedRecordingFileState,
	backend: StagedRecordingFileBackend,
	durationMs: number,
): Promise<string | null> {
	await state.writeChain;

	if (state.error) {
		throw state.error;
	}

	if (!state.path) {
		return null;
	}

	const path = state.path;
	if (!state.hasData) {
		await backend.deleteRecordingFile(path).catch(() => null);
		resetStagedRecordingFile(state);
		return null;
	}

	const bytes = await backend.readLocalFile(path);
	const webmFile = new WebmFile(bytes);
	const changed = fixParsedWebmDuration(webmFile, durationMs, { logger: false });
	const outputBytes = changed ? (webmFile.source ?? bytes) : bytes;
	await backend.replaceRecordingData(path, outputBytes);

	resetStagedRecordingFile(state);
	return path;
}
