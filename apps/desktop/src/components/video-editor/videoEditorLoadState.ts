import { fromFileUrl } from "@/lib/fileUrl";
import type { FacecamSettings } from "@/lib/recordingSession";
import { parseEditorWindowLaunchParams } from "./editorWindowParams";

type LoadedProjectFile = {
	data?: unknown;
	filePath?: string | null;
} | null;

type RecordingSessionLike = {
	screenVideoPath?: string | null;
	facecamVideoPath?: string | null;
	facecamOffsetMs?: number | null;
	facecamSettings?: Partial<FacecamSettings> | null;
	sourceName?: string | null;
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
			sourceName: string | null;
	  }
	| {
			kind: "video";
			sourcePath: string;
			sourceName: string | null;
	  }
	| {
			kind: "empty";
	  };

export interface LoadInitialVideoEditorStateDependencies {
	loadCurrentProjectFile: () => Promise<LoadedProjectFile>;
	getCurrentVideoPath: () => Promise<string | null>;
	getCurrentRecordingSession: () => Promise<RecordingSessionLike>;
	readLocalFile?: (path: string) => Promise<Uint8Array>;
	fileUrlToPath?: (value: string) => string;
	search?: string | URLSearchParams;
}

async function loadProjectFileAtPath(
	projectPath: string,
	readLocalFile?: (path: string) => Promise<Uint8Array>,
): Promise<LoadedProjectFile> {
	if (!readLocalFile) {
		return null;
	}

	try {
		const bytes = await readLocalFile(projectPath);
		const text = new TextDecoder().decode(bytes);
		return {
			data: JSON.parse(text),
			filePath: projectPath,
		};
	} catch {
		return null;
	}
}

export async function loadInitialVideoEditorState({
	loadCurrentProjectFile,
	getCurrentVideoPath,
	getCurrentRecordingSession,
	readLocalFile,
	fileUrlToPath = fromFileUrl,
	search,
}: LoadInitialVideoEditorStateDependencies): Promise<InitialVideoEditorLoadResult> {
	const launchParams = search ? parseEditorWindowLaunchParams(search) : null;
	if (launchParams?.mode === "project") {
		const projectResult = await loadProjectFileAtPath(launchParams.projectPath, readLocalFile);
		if (projectResult?.data) {
			return {
				kind: "project",
				data: projectResult.data,
				filePath: projectResult.filePath ?? null,
			};
		}
	}

	if (launchParams?.mode === "session") {
		return {
			kind: "session",
			sourcePath: launchParams.videoPath,
			facecamSourcePath: launchParams.facecamVideoPath ?? null,
			facecamOffsetMs: launchParams.facecamOffsetMs ?? 0,
			facecamSettings: launchParams.facecamSettings,
			sourceName: launchParams.sourceName ?? null,
		};
	}

	if (launchParams?.mode === "video") {
		return {
			kind: "video",
			sourcePath: launchParams.videoPath,
			sourceName: launchParams.sourceName ?? null,
		};
	}

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
			sourceName: typeof session.sourceName === "string" ? session.sourceName : null,
		};
	}

	if (videoPathResult) {
		return {
			kind: "video",
			sourcePath: fileUrlToPath(videoPathResult),
			sourceName: null,
		};
	}

	return {
		kind: "empty",
	};
}
