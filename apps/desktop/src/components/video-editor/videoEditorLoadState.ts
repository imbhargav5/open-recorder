import { fromFileUrl } from "@/lib/fileUrl";
import type { FacecamSettings } from "@/lib/recordingSession";

type LoadedProjectFile = {
	data?: unknown;
	filePath?: string | null;
} | null;

type RecordingSessionLike = {
	screenVideoPath?: string | null;
	facecamVideoPath?: string | null;
	facecamOffsetMs?: number | null;
	facecamSettings?: Partial<FacecamSettings> | null;
} | null;

export type InitialVideoEditorLoadResult =
	| {
			kind: "project";
			data: unknown;
			filePath: string | null;
	  }
	| {
			kind: "session";
			sourcePath: string;
			facecamSourcePath: string | null;
			facecamOffsetMs: number;
			facecamSettings: Partial<FacecamSettings> | null | undefined;
	  }
	| {
			kind: "video";
			sourcePath: string;
	  }
	| {
			kind: "empty";
	  };

export interface LoadInitialVideoEditorStateDependencies {
	loadCurrentProjectFile: () => Promise<LoadedProjectFile>;
	getCurrentVideoPath: () => Promise<string | null>;
	getCurrentRecordingSession: () => Promise<RecordingSessionLike>;
	fileUrlToPath?: (value: string) => string;
}

export async function loadInitialVideoEditorState({
	loadCurrentProjectFile,
	getCurrentVideoPath,
	getCurrentRecordingSession,
	fileUrlToPath = fromFileUrl,
}: LoadInitialVideoEditorStateDependencies): Promise<InitialVideoEditorLoadResult> {
	const currentProjectResult = await loadCurrentProjectFile();
	if (currentProjectResult?.data) {
		return {
			kind: "project",
			data: currentProjectResult.data,
			filePath: currentProjectResult.filePath ?? null,
		};
	}

	const [videoPathResult, session] = await Promise.all([
		getCurrentVideoPath(),
		getCurrentRecordingSession(),
	]);

	if (session?.screenVideoPath) {
		return {
			kind: "session",
			sourcePath: fileUrlToPath(session.screenVideoPath),
			facecamSourcePath: session.facecamVideoPath ? fileUrlToPath(session.facecamVideoPath) : null,
			facecamOffsetMs: session.facecamOffsetMs ?? 0,
			facecamSettings: session.facecamSettings,
		};
	}

	if (videoPathResult) {
		return {
			kind: "video",
			sourcePath: fileUrlToPath(videoPathResult),
		};
	}

	return {
		kind: "empty",
	};
}
