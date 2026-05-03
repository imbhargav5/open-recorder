import type { DesktopSource } from "@/components/launch/sourceSelectorState";
import { buildEditorWindowQuery } from "@/components/video-editor/editorWindowParams";
import * as backend from "@/lib/backend";
import { createDefaultFacecamSettings, type RecordingSession } from "@/lib/recordingSession";

export type MutableRef<T> = {
	current: T;
};

export type FacecamCaptureResult = {
	path: string;
	offsetMs: number;
} | null;

export type RecorderStartInput = {
	source: DesktopSource;
	sessionId: string;
	microphoneEnabled: boolean;
	microphoneDeviceId?: string;
	systemAudioEnabled: boolean;
	cameraEnabled: boolean;
	cameraDeviceId?: string;
};

export type RecorderController = {
	isActive: () => boolean;
	start: (input: RecorderStartInput) => Promise<void>;
	stop: () => void;
	cleanup: () => void;
};

export type FacecamRecorderController = {
	prepareForNewSession: () => void;
	setScreenStartedAt: (startedAt: number) => void;
	start: (sessionId: string) => Promise<void>;
	stop: () => Promise<FacecamCaptureResult>;
	cleanup: () => void;
};

export function isScreenOrWindowSource(source: DesktopSource): boolean {
	return source.id?.startsWith("screen:") || source.id?.startsWith("window:");
}

export function getSelectedSourceName(source: unknown) {
	if (!source || typeof source !== "object") {
		return undefined;
	}

	const candidate = source as {
		name?: unknown;
		windowTitle?: unknown;
		window_title?: unknown;
	};
	if (typeof candidate.name === "string" && candidate.name.trim()) {
		return candidate.name;
	}
	if (typeof candidate.windowTitle === "string" && candidate.windowTitle.trim()) {
		return candidate.windowTitle;
	}
	if (typeof candidate.window_title === "string" && candidate.window_title.trim()) {
		return candidate.window_title;
	}
	return undefined;
}

export function selectPreferredMimeType() {
	const preferred = [
		"video/webm;codecs=av1",
		"video/webm;codecs=h264",
		"video/webm;codecs=vp9",
		"video/webm;codecs=vp8",
		"video/webm",
	];

	return preferred.find((type) => MediaRecorder.isTypeSupported(type)) ?? "video/webm";
}

export function buildRecordingSession(
	screenVideoPath: string,
	facecamResult: FacecamCaptureResult,
	sourceName: string | undefined,
	showCursorOverlay: boolean,
): RecordingSession {
	return {
		screenVideoPath,
		...(facecamResult?.path ? { facecamVideoPath: facecamResult.path } : {}),
		...(facecamResult?.offsetMs !== undefined ? { facecamOffsetMs: facecamResult.offsetMs } : {}),
		facecamSettings: createDefaultFacecamSettings(Boolean(facecamResult?.path)),
		...(sourceName ? { sourceName } : {}),
		showCursorOverlay,
	};
}

export async function openRecordingSessionInEditor(session: RecordingSession): Promise<void> {
	await backend.switchToEditor(
		buildEditorWindowQuery({
			mode: "session",
			videoPath: session.screenVideoPath,
			facecamVideoPath: session.facecamVideoPath ?? null,
			facecamOffsetMs: session.facecamOffsetMs,
			facecamSettings: session.facecamSettings,
			sourceName: session.sourceName,
			showCursorOverlay: session.showCursorOverlay,
		}),
	);
}
