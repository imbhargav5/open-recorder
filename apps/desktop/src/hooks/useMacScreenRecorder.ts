import { useCallback, useMemo, useRef } from "react";
import * as backend from "@/lib/backend";
import {
	buildRecordingSession,
	type FacecamRecorderController,
	type MutableRef,
	openRecordingSessionInEditor,
	type RecorderController,
	type RecorderStartInput,
} from "./screenRecorderShared";

type UseMacScreenRecorderOptions = {
	facecamRecorder: FacecamRecorderController;
	mountedRef: MutableRef<boolean>;
	selectedSourceNameRef: MutableRef<string | undefined>;
	setRecording: (recording: boolean) => void;
};

export function useMacScreenRecorder({
	facecamRecorder,
	mountedRef,
	selectedSourceNameRef,
	setRecording,
}: UseMacScreenRecorderOptions): RecorderController {
	const activeRef = useRef(false);
	const cursorTelemetryCaptureActive = useRef(false);

	const stopCursorTelemetryCapture = useCallback(async (videoPath?: string | null) => {
		if (!cursorTelemetryCaptureActive.current) {
			return;
		}

		cursorTelemetryCaptureActive.current = false;

		try {
			await backend.stopCursorTelemetryCapture(videoPath ?? null);
		} catch (error) {
			console.warn("Failed to persist cursor telemetry:", error);
		}
	}, []);

	const cleanup = useCallback(() => {
		if (activeRef.current) {
			activeRef.current = false;
			void backend.stopNativeScreenRecording();
		}

		void stopCursorTelemetryCapture(null);
	}, [stopCursorTelemetryCapture]);

	const stop = useCallback(() => {
		if (!activeRef.current) {
			return;
		}

		activeRef.current = false;
		setRecording(false);

		void (async () => {
			const facecamResultPromise = facecamRecorder.stop();

			let stoppedPath: string | null = null;
			try {
				stoppedPath = await backend.stopNativeScreenRecording();
			} catch (error) {
				console.error("Error stopping native screen recording:", error);
			}

			if (!mountedRef.current) {
				await stopCursorTelemetryCapture(stoppedPath);
				await facecamResultPromise.catch(() => null);
				return;
			}

			await backend.setRecordingState(false).catch(() => null);

			if (!mountedRef.current) {
				await stopCursorTelemetryCapture(stoppedPath);
				await facecamResultPromise.catch(() => null);
				return;
			}

			if (!stoppedPath) {
				console.error("Failed to stop native screen recording");
				await stopCursorTelemetryCapture(null);
				await facecamResultPromise.catch(() => null);
				if (!mountedRef.current) return;
				await backend.switchToEditor();
				return;
			}

			await stopCursorTelemetryCapture(stoppedPath);
			const facecamResult = await facecamResultPromise.catch(() => null);
			if (!mountedRef.current) return;

			const recordingSession = buildRecordingSession(
				stoppedPath,
				facecamResult,
				selectedSourceNameRef.current,
				true,
			);
			await backend.setCurrentVideoPath(stoppedPath).catch(() => null);
			if (!mountedRef.current) return;

			await backend.setCurrentRecordingSession(recordingSession);
			if (!mountedRef.current) return;

			await openRecordingSessionInEditor(recordingSession);
		})();
	}, [
		facecamRecorder,
		mountedRef,
		selectedSourceNameRef,
		setRecording,
		stopCursorTelemetryCapture,
	]);

	const start = useCallback(
		async (input: RecorderStartInput) => {
			try {
				await backend.startCursorTelemetryCapture();
				cursorTelemetryCaptureActive.current = true;
			} catch (error) {
				cursorTelemetryCaptureActive.current = false;
				console.warn("macOS cursor telemetry capture is unavailable:", error);
			}

			const nativeRecordingPath = await backend.startNativeScreenRecording(input.source, {
				captureCursor: false,
				capturesSystemAudio: input.systemAudioEnabled,
				capturesMicrophone: input.microphoneEnabled,
				microphoneDeviceId: input.microphoneDeviceId,
			});

			if (!nativeRecordingPath) {
				await stopCursorTelemetryCapture(null);
				throw new Error("Native macOS screen recording did not return an output path.");
			}

			activeRef.current = true;
			const screenStartedAt = Date.now();
			facecamRecorder.setScreenStartedAt(screenStartedAt);
			await facecamRecorder.start(input.sessionId);

			if (!mountedRef.current) {
				cleanup();
				facecamRecorder.cleanup();
				return;
			}

			setRecording(true);
			await backend.setRecordingState(true);
		},
		[cleanup, facecamRecorder, mountedRef, setRecording, stopCursorTelemetryCapture],
	);

	const isActive = useCallback(() => activeRef.current, []);

	return useMemo(
		() => ({
			isActive,
			start,
			stop,
			cleanup,
		}),
		[cleanup, isActive, start, stop],
	);
}
