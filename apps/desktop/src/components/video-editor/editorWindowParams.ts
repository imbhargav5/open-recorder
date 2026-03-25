import { fromFileUrl, toFileUrl } from "@/lib/fileUrl";
import type { FacecamSettings } from "@/lib/recordingSession";

export type EditorWindowLaunchParams =
	| {
			mode: "project";
			projectPath: string;
	  }
	| {
			mode: "video";
			videoPath: string;
			sourceName?: string | null;
	  }
	| {
			mode: "session";
			videoPath: string;
			facecamVideoPath?: string | null;
			facecamOffsetMs?: number;
			facecamSettings?: Partial<FacecamSettings> | null;
			sourceName?: string | null;
	  };

function normalizeSourceName(value: string | null | undefined) {
	if (typeof value !== "string") {
		return undefined;
	}

	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : undefined;
}

function getDecodedFilePath(value: string | null) {
	if (!value) {
		return null;
	}

	return fromFileUrl(value);
}

function parseJson<T>(value: string | null): T | undefined {
	if (!value) {
		return undefined;
	}

	try {
		return JSON.parse(value) as T;
	} catch {
		return undefined;
	}
}

function basenameWithoutExtension(filePath: string) {
	const normalized = filePath.replace(/\\/g, "/");
	const basename = normalized.split("/").pop() ?? normalized;
	return basename.replace(/\.[^.]+$/, "") || basename;
}

export function buildEditorWindowQuery(params: EditorWindowLaunchParams) {
	const searchParams = new URLSearchParams();
	searchParams.set("windowType", "editor");
	searchParams.set("editorMode", params.mode);

	if (params.mode === "project") {
		searchParams.set("projectPath", toFileUrl(params.projectPath));
		return searchParams.toString();
	}

	searchParams.set("videoPath", toFileUrl(params.videoPath));

	const sourceName = normalizeSourceName(params.sourceName);
	if (sourceName) {
		searchParams.set("sourceName", sourceName);
	}

	if (params.mode === "session") {
		if (params.facecamVideoPath) {
			searchParams.set("facecamVideoPath", toFileUrl(params.facecamVideoPath));
		}
		if (typeof params.facecamOffsetMs === "number" && Number.isFinite(params.facecamOffsetMs)) {
			searchParams.set("facecamOffsetMs", String(params.facecamOffsetMs));
		}
		if (params.facecamSettings) {
			searchParams.set("facecamSettings", JSON.stringify(params.facecamSettings));
		}
	}

	return searchParams.toString();
}

export function parseEditorWindowLaunchParams(
	search: string | URLSearchParams,
): EditorWindowLaunchParams | null {
	const searchParams =
		search instanceof URLSearchParams
			? search
			: new URLSearchParams(search.startsWith("?") ? search.slice(1) : search);
	const mode = searchParams.get("editorMode");

	if (mode === "project") {
		const projectPath = getDecodedFilePath(searchParams.get("projectPath"));
		return projectPath ? { mode, projectPath } : null;
	}

	if (mode === "video") {
		const videoPath = getDecodedFilePath(searchParams.get("videoPath"));
		return videoPath
			? {
					mode,
					videoPath,
					sourceName: normalizeSourceName(searchParams.get("sourceName")) ?? null,
				}
			: null;
	}

	if (mode === "session") {
		const videoPath = getDecodedFilePath(searchParams.get("videoPath"));
		if (!videoPath) {
			return null;
		}

		const rawOffset = Number(searchParams.get("facecamOffsetMs"));
		return {
			mode,
			videoPath,
			facecamVideoPath: getDecodedFilePath(searchParams.get("facecamVideoPath")),
			facecamOffsetMs: Number.isFinite(rawOffset) ? rawOffset : undefined,
			facecamSettings: parseJson<Partial<FacecamSettings>>(searchParams.get("facecamSettings")),
			sourceName: normalizeSourceName(searchParams.get("sourceName")) ?? null,
		};
	}

	return null;
}

export function buildVideoEditorNavbarTitle(options: {
	projectPath?: string | null;
	videoPath?: string | null;
	sourceName?: string | null;
	fallbackTitle?: string;
}) {
	const projectTitle =
		typeof options.projectPath === "string" && options.projectPath.trim()
			? basenameWithoutExtension(options.projectPath)
			: null;
	const videoTitle =
		typeof options.videoPath === "string" && options.videoPath.trim()
			? basenameWithoutExtension(options.videoPath)
			: null;
	const sourceName = normalizeSourceName(options.sourceName) ?? null;
	const primaryTitle =
		projectTitle ?? videoTitle ?? sourceName ?? options.fallbackTitle ?? "Open Recorder";

	if (
		!sourceName ||
		sourceName.localeCompare(primaryTitle, undefined, { sensitivity: "accent" }) === 0
	) {
		return primaryTitle;
	}

	return `${primaryTitle} | ${sourceName}`;
}
