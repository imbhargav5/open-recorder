import { useCallback, useEffect, useMemo, useRef } from "react";
import * as backend from "@/lib/backend";
import {
	type FacecamCaptureResult,
	type FacecamRecorderController,
	selectPreferredMimeType,
} from "./screenRecorderShared";
import {
	createStagedRecordingFileState,
	finalizeStagedRecordingFile,
	queueStagedRecordingChunk,
	resetStagedRecordingFile,
} from "./stagedRecordingFile";

const RECORDING_FILE_PREFIX = "recording-";
const FACECAM_FILE_SUFFIX = ".facecam.webm";
const RECORDER_TIMESLICE_MS = 1000;
const FACECAM_TARGET_WIDTH = 1280;
const FACECAM_TARGET_HEIGHT = 720;
const FACECAM_TARGET_FRAME_RATE = 30;
const FACECAM_BITRATE = 8_000_000;

type UseFacecamRecorderOptions = {
	cameraEnabled: boolean;
	cameraDeviceId: string | undefined;
	setCameraEnabled: (enabled: boolean) => void;
};

export function useFacecamRecorder({
	cameraEnabled,
	cameraDeviceId,
	setCameraEnabled,
}: UseFacecamRecorderOptions): FacecamRecorderController {
	const cameraStream = useRef<MediaStream | null>(null);
	const cameraRecorder = useRef<MediaRecorder | null>(null);
	const cameraRecordingStartedAt = useRef<number | null>(null);
	const screenRecordingStartedAt = useRef<number | null>(null);
	const cameraEnabledRef = useRef(cameraEnabled);
	const cameraDeviceIdRef = useRef(cameraDeviceId);
	const pendingFacecamResult = useRef<Promise<FacecamCaptureResult> | null>(null);
	const facecamRecordingFile = useRef(createStagedRecordingFileState());
	const facecamPendingWrites = useRef<Promise<void>[]>([]);

	useEffect(() => {
		cameraEnabledRef.current = cameraEnabled;
		cameraDeviceIdRef.current = cameraDeviceId;
	}, [cameraDeviceId, cameraEnabled]);

	const prepareForNewSession = useCallback(() => {
		pendingFacecamResult.current = Promise.resolve(null);
		cameraRecordingStartedAt.current = null;
		screenRecordingStartedAt.current = null;
	}, []);

	const setScreenStartedAt = useCallback((startedAt: number) => {
		screenRecordingStartedAt.current = startedAt;
	}, []);

	const cleanup = useCallback(() => {
		if (cameraRecorder.current?.state === "recording") {
			cameraRecorder.current.stop();
		}
		cameraRecorder.current = null;

		if (cameraStream.current) {
			cameraStream.current.getTracks().forEach((track) => track.stop());
			cameraStream.current = null;
		}

		if (facecamRecordingFile.current.path) {
			void backend.deleteRecordingFile(facecamRecordingFile.current.path).catch(() => null);
		}
		resetStagedRecordingFile(facecamRecordingFile.current);
		facecamPendingWrites.current = [];
		pendingFacecamResult.current = Promise.resolve(null);
		cameraRecordingStartedAt.current = null;
		screenRecordingStartedAt.current = null;
	}, []);

	const stop = useCallback(async (): Promise<FacecamCaptureResult> => {
		const recorder = cameraRecorder.current;
		const pending = pendingFacecamResult.current;

		if (recorder?.state === "recording") {
			recorder.stop();
		}

		const result = pending ? await pending : null;
		pendingFacecamResult.current = null;
		return result;
	}, []);

	const start = useCallback(
		async (sessionId: string) => {
			if (!cameraEnabledRef.current) {
				pendingFacecamResult.current = Promise.resolve(null);
				return;
			}

			const selectedCameraDeviceId = cameraDeviceIdRef.current;
			try {
				cameraStream.current = await navigator.mediaDevices.getUserMedia({
					video: selectedCameraDeviceId
						? {
								deviceId: { exact: selectedCameraDeviceId },
								width: { ideal: FACECAM_TARGET_WIDTH, max: FACECAM_TARGET_WIDTH },
								height: { ideal: FACECAM_TARGET_HEIGHT, max: FACECAM_TARGET_HEIGHT },
								frameRate: { ideal: FACECAM_TARGET_FRAME_RATE, max: FACECAM_TARGET_FRAME_RATE },
							}
						: {
								width: { ideal: FACECAM_TARGET_WIDTH, max: FACECAM_TARGET_WIDTH },
								height: { ideal: FACECAM_TARGET_HEIGHT, max: FACECAM_TARGET_HEIGHT },
								frameRate: { ideal: FACECAM_TARGET_FRAME_RATE, max: FACECAM_TARGET_FRAME_RATE },
							},
					audio: false,
				});
			} catch (error) {
				console.warn("Failed to get camera access:", error);
				alert("Camera access was denied. Recording will continue without facecam.");
				setCameraEnabled(false);
				pendingFacecamResult.current = Promise.resolve(null);
				return;
			}

			const mimeType = selectPreferredMimeType();
			resetStagedRecordingFile(facecamRecordingFile.current);
			facecamPendingWrites.current = [];
			facecamRecordingFile.current.path = await backend.prepareRecordingFile(
				`${RECORDING_FILE_PREFIX}${sessionId}${FACECAM_FILE_SUFFIX}`,
			);

			const recorder = new MediaRecorder(cameraStream.current, {
				mimeType,
				videoBitsPerSecond: FACECAM_BITRATE,
			});
			cameraRecorder.current = recorder;

			pendingFacecamResult.current = new Promise<FacecamCaptureResult>((resolve) => {
				let settled = false;

				const settle = (result: FacecamCaptureResult) => {
					if (settled) {
						return;
					}

					settled = true;
					resolve(result);
				};

				recorder.onstart = () => {
					cameraRecordingStartedAt.current = Date.now();
				};

				recorder.ondataavailable = (event) => {
					if (event.data && event.data.size > 0) {
						const writePromise = queueStagedRecordingChunk(
							facecamRecordingFile.current,
							backend,
							event.data,
						);
						facecamPendingWrites.current.push(writePromise);
					}
				};

				recorder.onerror = () => {
					console.error("Facecam recorder failed while capturing.");
					settle(null);
				};

				recorder.onstop = async () => {
					cameraRecorder.current = null;

					await Promise.all(facecamPendingWrites.current);
					facecamPendingWrites.current = [];

					try {
						const startedAt = cameraRecordingStartedAt.current ?? Date.now();
						const duration = Math.max(0, Date.now() - startedAt);
						const storedPath = await finalizeStagedRecordingFile(
							facecamRecordingFile.current,
							backend,
							duration,
						);

						if (!storedPath) {
							console.error("Failed to store facecam recording");
							settle(null);
							return;
						}

						const screenStartedAt = screenRecordingStartedAt.current ?? startedAt;
						settle({
							path: storedPath,
							offsetMs: Math.round(startedAt - screenStartedAt),
						});
					} catch (error) {
						console.error("Failed to save facecam recording:", error);
						if (facecamRecordingFile.current.path) {
							await backend
								.deleteRecordingFile(facecamRecordingFile.current.path)
								.catch(() => null);
						}
						resetStagedRecordingFile(facecamRecordingFile.current);
						settle(null);
					}
				};
			});

			recorder.start(RECORDER_TIMESLICE_MS);
		},
		[setCameraEnabled],
	);

	return useMemo(
		() => ({
			prepareForNewSession,
			setScreenStartedAt,
			start,
			stop,
			cleanup,
		}),
		[cleanup, prepareForNewSession, setScreenStartedAt, start, stop],
	);
}
