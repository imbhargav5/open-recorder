import { fixParsedWebmDuration } from "@fix-webm-duration/fix";
import { WebmFile } from "@fix-webm-duration/parser";
import { useCallback, useEffect, useRef, useState } from "react";
import { buildEditorWindowQuery } from "@/components/video-editor/editorWindowParams";
import * as backend from "@/lib/backend";
import { createDefaultFacecamSettings, type RecordingSession } from "@/lib/recordingSession";

const TARGET_FRAME_RATE = 60;
const TARGET_WIDTH = 3840;
const TARGET_HEIGHT = 2160;
const FOUR_K_PIXELS = TARGET_WIDTH * TARGET_HEIGHT;
const QHD_WIDTH = 2560;
const QHD_HEIGHT = 1440;
const QHD_PIXELS = QHD_WIDTH * QHD_HEIGHT;
const BITRATE_4K = 45_000_000;
const BITRATE_QHD = 28_000_000;
const BITRATE_BASE = 18_000_000;
const HIGH_FRAME_RATE_THRESHOLD = 60;
const HIGH_FRAME_RATE_BOOST = 1.7;
const DEFAULT_WIDTH = 1920;
const DEFAULT_HEIGHT = 1080;
const CODEC_ALIGNMENT = 2;
const RECORDER_TIMESLICE_MS = 1000;
const BITS_PER_MEGABIT = 1_000_000;
const MIN_FRAME_RATE = 30;
const CHROME_MEDIA_SOURCE = "desktop";
const RECORDING_FILE_PREFIX = "recording-";
const VIDEO_FILE_EXTENSION = ".webm";
const FACECAM_FILE_SUFFIX = ".facecam.webm";
const AUDIO_BITRATE_VOICE = 128_000;
const AUDIO_BITRATE_SYSTEM = 192_000;
const MIC_GAIN_BOOST = 1.4;
const FACECAM_TARGET_WIDTH = 1280;
const FACECAM_TARGET_HEIGHT = 720;
const FACECAM_TARGET_FRAME_RATE = 30;
const FACECAM_BITRATE = 8_000_000;
const MAC_NATIVE_CAPTURE_START_FAILURE = "Failed to start native ScreenCaptureKit recording";

type FacecamCaptureResult = {
	path: string;
	offsetMs: number;
} | null;

type ChromeDesktopVideoConstraints = {
	mandatory: {
		chromeMediaSource: string;
		chromeMediaSourceId: string;
		maxWidth: number;
		maxHeight: number;
		maxFrameRate: number;
		minFrameRate: number;
		cursor?: "always" | "motion" | "never";
	};
};

type ChromeDesktopAudioConstraints = {
	mandatory: {
		chromeMediaSource: string;
		chromeMediaSourceId: string;
	};
};

type ChromeDesktopCaptureConstraints = {
	audio: false | ChromeDesktopAudioConstraints;
	video: ChromeDesktopVideoConstraints;
};

type DisplayMediaVideoConstraints = MediaTrackConstraints & {
	cursor?: "always" | "motion" | "never";
};

type ExtendedDisplayMediaStreamOptions = DisplayMediaStreamOptions & {
	video?: boolean | DisplayMediaVideoConstraints;
	selfBrowserSurface?: "include" | "exclude";
	surfaceSwitching?: "include" | "exclude";
};

type DesktopCaptureMediaDevices = MediaDevices & {
	getUserMedia(
		constraints: MediaStreamConstraints | ChromeDesktopCaptureConstraints,
	): Promise<MediaStream>;
	getDisplayMedia(constraints?: ExtendedDisplayMediaStreamOptions): Promise<MediaStream>;
};

type UseScreenRecorderReturn = {
	recording: boolean;
	toggleRecording: () => void;
	preparePermissions: (options?: { startup?: boolean }) => Promise<boolean>;
	isMacOS: boolean;
	microphoneEnabled: boolean;
	setMicrophoneEnabled: (enabled: boolean) => void;
	microphoneDeviceId: string | undefined;
	setMicrophoneDeviceId: (deviceId: string | undefined) => void;
	systemAudioEnabled: boolean;
	setSystemAudioEnabled: (enabled: boolean) => void;
	cameraEnabled: boolean;
	setCameraEnabled: (enabled: boolean) => void;
	cameraDeviceId: string | undefined;
	setCameraDeviceId: (deviceId: string | undefined) => void;
};

function getSelectedSourceName(source: unknown) {
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

export function useScreenRecorder(): UseScreenRecorderReturn {
	const [recording, setRecording] = useState(false);
	const [starting, setStarting] = useState(false);
	const [isMacOS, setIsMacOS] = useState(false);
	const [microphoneEnabled, setMicrophoneEnabled] = useState(false);
	const [microphoneDeviceId, setMicrophoneDeviceId] = useState<string | undefined>(undefined);
	const [systemAudioEnabled, setSystemAudioEnabled] = useState(false);
	const [cameraEnabled, setCameraEnabled] = useState(false);
	const [cameraDeviceId, setCameraDeviceId] = useState<string | undefined>(undefined);
	const mediaRecorder = useRef<MediaRecorder | null>(null);
	const stream = useRef<MediaStream | null>(null);
	const screenStream = useRef<MediaStream | null>(null);
	const microphoneStream = useRef<MediaStream | null>(null);
	const cameraStream = useRef<MediaStream | null>(null);
	const mixingContext = useRef<AudioContext | null>(null);
	const cameraRecorder = useRef<MediaRecorder | null>(null);
	const cameraRecordingStartedAt = useRef<number | null>(null);
	const screenRecordingStartedAt = useRef<number | null>(null);
	const pendingFacecamResult = useRef<Promise<FacecamCaptureResult> | null>(null);
	const startTime = useRef<number>(0);
	const nativeScreenRecording = useRef(false);
	const wgcRecording = useRef(false);
	const linuxCursorTelemetryCaptureActive = useRef(false);
	const startInFlight = useRef(false);
	const hasPromptedForReselect = useRef(false);
	const selectedSourceName = useRef<string | undefined>(undefined);
	const recordingSessionId = useRef<string>("");
	const recordingFilePath = useRef<string | null>(null);
	const facecamRecordingPath = useRef<string | null>(null);
	const recordingWriteChain = useRef<Promise<void>>(Promise.resolve());
	const facecamWriteChain = useRef<Promise<void>>(Promise.resolve());
	const recordingWriteError = useRef<Error | null>(null);
	const facecamWriteError = useRef<Error | null>(null);
	const recordingHasData = useRef(false);
	const facecamHasData = useRef(false);

	const resetStagedFileState = useCallback(
		(
			pathRef: React.MutableRefObject<string | null>,
			writeChainRef: React.MutableRefObject<Promise<void>>,
			errorRef: React.MutableRefObject<Error | null>,
			hasDataRef: React.MutableRefObject<boolean>,
		) => {
			pathRef.current = null;
			writeChainRef.current = Promise.resolve();
			errorRef.current = null;
			hasDataRef.current = false;
		},
		[],
	);

	const queueRecordingChunkWrite = useCallback(
		async (
			pathRef: React.MutableRefObject<string | null>,
			writeChainRef: React.MutableRefObject<Promise<void>>,
			errorRef: React.MutableRefObject<Error | null>,
			hasDataRef: React.MutableRefObject<boolean>,
			chunk: Blob,
		) => {
			hasDataRef.current = true;
			writeChainRef.current = writeChainRef.current.then(async () => {
				if (errorRef.current) {
					return;
				}

				const path = pathRef.current;
				if (!path) {
					errorRef.current = new Error("Recording file path is not initialized");
					return;
				}

				try {
					const arrayBuffer = await chunk.arrayBuffer();
					await backend.appendRecordingData(path, new Uint8Array(arrayBuffer));
				} catch (error) {
					errorRef.current = error instanceof Error ? error : new Error(String(error));
				}
			});

			await writeChainRef.current;
		},
		[],
	);

	const finalizeStagedWebm = useCallback(
		async (
			pathRef: React.MutableRefObject<string | null>,
			writeChainRef: React.MutableRefObject<Promise<void>>,
			errorRef: React.MutableRefObject<Error | null>,
			hasDataRef: React.MutableRefObject<boolean>,
			durationMs: number,
		): Promise<string | null> => {
			await writeChainRef.current;

			if (errorRef.current) {
				throw errorRef.current;
			}

			const path = pathRef.current;
			if (!path) {
				return null;
			}

			if (!hasDataRef.current) {
				await backend.deleteRecordingFile(path).catch(() => null);
				resetStagedFileState(pathRef, writeChainRef, errorRef, hasDataRef);
				return null;
			}

			const bytes = await backend.readLocalFile(path);
			const webmFile = new WebmFile(bytes);
			const changed = fixParsedWebmDuration(webmFile, durationMs, { logger: false });
			const outputBytes = changed ? (webmFile.source ?? bytes) : bytes;
			await backend.replaceRecordingData(path, outputBytes);

			resetStagedFileState(pathRef, writeChainRef, errorRef, hasDataRef);
			return path;
		},
		[resetStagedFileState],
	);

	const stopLinuxCursorTelemetryCapture = useCallback(async (videoPath?: string | null) => {
		if (!linuxCursorTelemetryCaptureActive.current) {
			return;
		}

		linuxCursorTelemetryCaptureActive.current = false;

		try {
			await backend.stopCursorTelemetryCapture(videoPath ?? null);
		} catch (error) {
			console.warn("Failed to persist Linux cursor telemetry:", error);
		}
	}, []);

	const preparePermissions = useCallback(
		async (options: { startup?: boolean } = {}) => {
			const platform = await backend.getPlatform();
			if (platform !== "darwin") {
				return true;
			}

			// ── Screen Recording (required) ──────────────────────────────────
			const screenStatus = await backend.getScreenRecordingPermissionStatus();
			if (screenStatus !== "granted") {
				const granted = await backend.requestScreenRecordingPermission();
				if (granted) {
					// continue to next check
				} else {
					const refreshedStatus = await backend.getScreenRecordingPermissionStatus();
					if (refreshedStatus !== "granted") {
						await backend.openScreenRecordingPreferences();
						alert(
							options.startup
								? "Open Recorder needs Screen Recording permission before you start. System Settings has been opened. After enabling it, quit and reopen Open Recorder."
								: "Screen Recording permission is still missing. System Settings has been opened again. Enable it, then quit and reopen Open Recorder before recording.",
						);
						return false;
					}
				}
			}

			// ── Accessibility (required) ─────────────────────────────────────
			const accessibilityStatus = await backend.getAccessibilityPermissionStatus();
			if (accessibilityStatus !== "granted") {
				const granted = await backend.requestAccessibilityPermission();
				if (!granted) {
					await backend.openAccessibilityPreferences();
					alert(
						options.startup
							? "Open Recorder also needs Accessibility permission for cursor tracking. System Settings has been opened. After enabling it, quit and reopen Open Recorder."
							: "Accessibility permission is still missing. System Settings has been opened again. Enable it, then quit and reopen Open Recorder before recording.",
					);
					return false;
				}
			}

			// ── Microphone (check if enabled and not yet granted) ────────────
			if (microphoneEnabled) {
				const micStatus = await backend.getMicrophonePermissionStatus().catch(() => "unknown");
				if (micStatus === "not_determined") {
					const granted = isMacOS
						? await backend.requestMicrophonePermission().catch(() => false)
						: await navigator.mediaDevices
								.getUserMedia({ audio: true, video: false })
								.then((stream) => {
									stream.getTracks().forEach((track) => track.stop());
									return true;
								})
								.catch(() => false);
					if (!granted) {
						console.warn("Microphone permission not granted during pre-recording check.");
					}
				} else if (micStatus === "denied" || micStatus === "restricted") {
					await backend.openMicrophonePreferences();
					alert(
						"Microphone access is currently denied. System Settings has been opened. Grant microphone access, then try recording again.",
					);
					return false;
				}
			}

			// ── Camera (check if enabled and not yet granted) ────────────────
			if (cameraEnabled) {
				const camStatus = await backend.getCameraPermissionStatus().catch(() => "unknown");
				if (camStatus === "not_determined") {
					const granted = isMacOS
						? await backend.requestCameraPermission().catch(() => false)
						: await navigator.mediaDevices
								.getUserMedia({ audio: false, video: true })
								.then((stream) => {
									stream.getTracks().forEach((track) => track.stop());
									return true;
								})
								.catch(() => false);
					if (!granted) {
						console.warn("Camera permission not granted during pre-recording check.");
					}
				} else if (camStatus === "denied" || camStatus === "restricted") {
					await backend.openCameraPreferences();
					alert(
						"Camera access is currently denied. System Settings has been opened. Grant camera access, then try recording again.",
					);
					return false;
				}
			}

			return true;
		},
		[microphoneEnabled, cameraEnabled, isMacOS],
	);

	const selectMimeType = useCallback(() => {
		const preferred = [
			"video/webm;codecs=av1",
			"video/webm;codecs=h264",
			"video/webm;codecs=vp9",
			"video/webm;codecs=vp8",
			"video/webm",
		];

		return preferred.find((type) => MediaRecorder.isTypeSupported(type)) ?? "video/webm";
	}, []);

	const computeBitrate = (width: number, height: number) => {
		const pixels = width * height;
		const highFrameRateBoost =
			TARGET_FRAME_RATE >= HIGH_FRAME_RATE_THRESHOLD ? HIGH_FRAME_RATE_BOOST : 1;

		if (pixels >= FOUR_K_PIXELS) {
			return Math.round(BITRATE_4K * highFrameRateBoost);
		}

		if (pixels >= QHD_PIXELS) {
			return Math.round(BITRATE_QHD * highFrameRateBoost);
		}

		return Math.round(BITRATE_BASE * highFrameRateBoost);
	};

	const cleanupCapturedMedia = useCallback(() => {
		if (stream.current) {
			stream.current.getTracks().forEach((track) => track.stop());
			stream.current = null;
		}

		if (screenStream.current) {
			screenStream.current.getTracks().forEach((track) => track.stop());
			screenStream.current = null;
		}

		if (microphoneStream.current) {
			microphoneStream.current.getTracks().forEach((track) => track.stop());
			microphoneStream.current = null;
		}

		if (cameraStream.current) {
			cameraStream.current.getTracks().forEach((track) => track.stop());
			cameraStream.current = null;
		}

		if (mixingContext.current) {
			mixingContext.current.close().catch(() => {
				// Ignore close races during teardown.
			});
			mixingContext.current = null;
		}
	}, []);

	const buildRecordingSession = useCallback(
		(screenVideoPath: string, facecamResult: FacecamCaptureResult): RecordingSession => ({
			screenVideoPath,
			...(facecamResult?.path ? { facecamVideoPath: facecamResult.path } : {}),
			...(facecamResult?.offsetMs !== undefined ? { facecamOffsetMs: facecamResult.offsetMs } : {}),
			facecamSettings: createDefaultFacecamSettings(Boolean(facecamResult?.path)),
			...(selectedSourceName.current ? { sourceName: selectedSourceName.current } : {}),
		}),
		[],
	);

	const stopFacecamCapture = useCallback(async (): Promise<FacecamCaptureResult> => {
		const recorder = cameraRecorder.current;
		const pending = pendingFacecamResult.current;

		if (recorder?.state === "recording") {
			recorder.stop();
		}

		const result = pending ? await pending : null;
		pendingFacecamResult.current = null;
		return result;
	}, []);

	const startFacecamCapture = useCallback(
		async (sessionId: string) => {
			if (!cameraEnabled) {
				pendingFacecamResult.current = Promise.resolve(null);
				return;
			}

			try {
				cameraStream.current = await navigator.mediaDevices.getUserMedia({
					video: cameraDeviceId
						? {
								deviceId: { exact: cameraDeviceId },
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

			const mimeType = selectMimeType();
			resetStagedFileState(
				facecamRecordingPath,
				facecamWriteChain,
				facecamWriteError,
				facecamHasData,
			);
			facecamRecordingPath.current = await backend.prepareRecordingFile(
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
						void queueRecordingChunkWrite(
							facecamRecordingPath,
							facecamWriteChain,
							facecamWriteError,
							facecamHasData,
							event.data,
						);
					}
				};

				recorder.onerror = () => {
					console.error("Facecam recorder failed while capturing.");
					settle(null);
				};

				recorder.onstop = async () => {
					cameraRecorder.current = null;

					try {
						const startedAt = cameraRecordingStartedAt.current ?? Date.now();
						const duration = Math.max(0, Date.now() - startedAt);
						const storedPath = await finalizeStagedWebm(
							facecamRecordingPath,
							facecamWriteChain,
							facecamWriteError,
							facecamHasData,
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
						if (facecamRecordingPath.current) {
							await backend.deleteRecordingFile(facecamRecordingPath.current).catch(() => null);
						}
						resetStagedFileState(
							facecamRecordingPath,
							facecamWriteChain,
							facecamWriteError,
							facecamHasData,
						);
						settle(null);
					}
				};
			});

			recorder.start(RECORDER_TIMESLICE_MS);
		},
		[
			cameraDeviceId,
			cameraEnabled,
			finalizeStagedWebm,
			queueRecordingChunkWrite,
			resetStagedFileState,
			selectMimeType,
		],
	);

	const stopRecording = useCallback(() => {
		if (nativeScreenRecording.current) {
			nativeScreenRecording.current = false;
			setRecording(false);

			void (async () => {
				const isWgc = wgcRecording.current;
				wgcRecording.current = false;
				const facecamResultPromise = stopFacecamCapture();

				let stoppedPath: string | null = null;
				try {
					stoppedPath = await backend.stopNativeScreenRecording();
				} catch (error) {
					console.error("Error stopping native screen recording:", error);
				}
				await backend.setRecordingState(false).catch(() => null);

				cleanupCapturedMedia();

				if (!stoppedPath) {
					console.error("Failed to stop native screen recording");
					await facecamResultPromise.catch(() => null);
					await backend.switchToEditor();
					return;
				}

				let finalPath = stoppedPath;

				if (isWgc) {
					try {
						const muxPath = await backend.muxWgcRecording();
						finalPath = muxPath ?? stoppedPath;
					} catch {
						// use original path
					}
				}

				const facecamResult = await facecamResultPromise.catch(() => null);
				const recordingSession = buildRecordingSession(finalPath, facecamResult);
				await backend.setCurrentVideoPath(finalPath).catch(() => null);
				await backend.setCurrentRecordingSession(recordingSession);
				await backend.switchToEditor(
					buildEditorWindowQuery({
						mode: "session",
						videoPath: finalPath,
						facecamVideoPath: recordingSession.facecamVideoPath ?? null,
						facecamOffsetMs: recordingSession.facecamOffsetMs,
						facecamSettings: recordingSession.facecamSettings,
						sourceName: recordingSession.sourceName,
					}),
				);
			})();
			return;
		}

		if (mediaRecorder.current?.state === "recording") {
			pendingFacecamResult.current = stopFacecamCapture();
			cleanupCapturedMedia();
			mediaRecorder.current.stop();
			setRecording(false);
			void backend.setRecordingState(false);
		}
	}, [buildRecordingSession, cleanupCapturedMedia, stopFacecamCapture]);

	useEffect(() => {
		void (async () => {
			const platform = await backend.getPlatform();
			setIsMacOS(platform === "darwin");
		})();
	}, []);

	useEffect(() => {
		let unlistenTray: (() => void) | undefined;
		let unlistenState: (() => void) | undefined;
		let unlistenInterrupted: (() => void) | undefined;

		backend
			.onStopRecordingFromTray(() => {
				stopRecording();
			})
			.then((fn) => {
				unlistenTray = fn;
			});

		backend
			.onRecordingStateChanged((isRecording) => {
				setRecording(isRecording);
			})
			.then((fn) => {
				unlistenState = fn;
			});

		backend
			.onRecordingInterrupted(() => {
				setRecording(false);
				nativeScreenRecording.current = false;
				void stopLinuxCursorTelemetryCapture(null);
				cleanupCapturedMedia();
				void backend.setRecordingState(false);
			})
			.then((fn) => {
				unlistenInterrupted = fn;
			});

		return () => {
			unlistenTray?.();
			unlistenState?.();
			unlistenInterrupted?.();

			if (nativeScreenRecording.current) {
				nativeScreenRecording.current = false;
				void backend.stopNativeScreenRecording();
			}

			if (mediaRecorder.current?.state === "recording") {
				mediaRecorder.current.stop();
			}

			if (cameraRecorder.current?.state === "recording") {
				cameraRecorder.current.stop();
			}

			void stopLinuxCursorTelemetryCapture(null);
			cleanupCapturedMedia();
			if (recordingFilePath.current) {
				void backend.deleteRecordingFile(recordingFilePath.current).catch(() => null);
			}
			if (facecamRecordingPath.current) {
				void backend.deleteRecordingFile(facecamRecordingPath.current).catch(() => null);
			}
			resetStagedFileState(
				recordingFilePath,
				recordingWriteChain,
				recordingWriteError,
				recordingHasData,
			);
			resetStagedFileState(
				facecamRecordingPath,
				facecamWriteChain,
				facecamWriteError,
				facecamHasData,
			);
		};
	}, [cleanupCapturedMedia, resetStagedFileState, stopLinuxCursorTelemetryCapture, stopRecording]);

	const startRecording = async () => {
		if (startInFlight.current) {
			return;
		}

		hasPromptedForReselect.current = false;
		startInFlight.current = true;
		setStarting(true);
		recordingSessionId.current = `${Date.now()}`;
		pendingFacecamResult.current = Promise.resolve(null);
		cameraRecordingStartedAt.current = null;
		screenRecordingStartedAt.current = null;

		try {
			const selectedSource = await backend.getSelectedSource();
			selectedSourceName.current = getSelectedSourceName(selectedSource);
			const mediaDevices = navigator.mediaDevices as DesktopCaptureMediaDevices;
			if (!selectedSource) {
				alert("Please select a source to record");
				return;
			}

			const permissionsReady = await preparePermissions();
			if (!permissionsReady) {
				return;
			}

			const platform = await backend.getPlatform();
			const useNativeMacScreenCapture =
				platform === "darwin" &&
				(selectedSource.id?.startsWith("screen:") || selectedSource.id?.startsWith("window:"));

			let useWgcCapture = false;
			if (
				platform === "win32" &&
				(selectedSource.id?.startsWith("screen:") || selectedSource.id?.startsWith("window:"))
			) {
				try {
					useWgcCapture = await backend.isWgcAvailable();
				} catch {
					useWgcCapture = false;
				}
			}

			if (useNativeMacScreenCapture || useWgcCapture) {
				let micLabel: string | undefined;
				if (useWgcCapture && microphoneEnabled) {
					try {
						const devices = await navigator.mediaDevices.enumerateDevices();
						const mic = devices.find(
							(device) => device.deviceId === microphoneDeviceId && device.kind === "audioinput",
						);
						micLabel = mic?.label || undefined;
					} catch {
						// Labels can be unavailable until permission is granted.
					}
				}

				let nativeStarted = false;
				try {
					await backend.startNativeScreenRecording(selectedSource, {
						captureCursor: false,
						capturesSystemAudio: systemAudioEnabled,
						capturesMicrophone: microphoneEnabled,
						microphoneDeviceId,
						microphoneLabel: micLabel,
					});
					nativeStarted = true;
				} catch (nativeError) {
					const errMsg = nativeError instanceof Error ? nativeError.message : String(nativeError);
					if (useWgcCapture) {
						console.warn("WGC capture failed, falling back to browser capture:", errMsg);
					} else if (errMsg === MAC_NATIVE_CAPTURE_START_FAILURE) {
						console.warn("Native macOS capture failed, falling back to browser capture:", errMsg);
					} else {
						throw new Error(errMsg || "Failed to start native screen recording");
					}
				}

				if (nativeStarted) {
					await startFacecamCapture(recordingSessionId.current);
					nativeScreenRecording.current = true;
					wgcRecording.current = useWgcCapture;
					startTime.current = Date.now();
					screenRecordingStartedAt.current = startTime.current;
					setRecording(true);
					await backend.setRecordingState(true);
					return;
				}
			}

			if (platform === "linux") {
				try {
					await backend.startCursorTelemetryCapture();
					linuxCursorTelemetryCaptureActive.current = true;
				} catch (error) {
					linuxCursorTelemetryCaptureActive.current = false;
					console.warn("Linux cursor telemetry capture is unavailable:", error);
				}
			}

			const wantsAudioCapture = microphoneEnabled || systemAudioEnabled;
			const shouldHideSourceCursor = linuxCursorTelemetryCaptureActive.current;

			try {
				await backend.hideCursor();
			} catch {
				console.warn("Could not hide OS cursor before recording.");
			}

			let videoTrack: MediaStreamTrack | undefined;
			let systemAudioIncluded = false;

			if (wantsAudioCapture) {
				const videoConstraints = {
					mandatory: {
						chromeMediaSource: CHROME_MEDIA_SOURCE,
						chromeMediaSourceId: selectedSource.id,
						maxWidth: TARGET_WIDTH,
						maxHeight: TARGET_HEIGHT,
						maxFrameRate: TARGET_FRAME_RATE,
						minFrameRate: MIN_FRAME_RATE,
						cursor: shouldHideSourceCursor ? "never" : "always",
					},
				};

				let screenMediaStream: MediaStream;

				if (systemAudioEnabled) {
					try {
						screenMediaStream = await mediaDevices.getUserMedia({
							audio: {
								mandatory: {
									chromeMediaSource: CHROME_MEDIA_SOURCE,
									chromeMediaSourceId: selectedSource.id,
								},
							},
							video: videoConstraints,
						});
					} catch (audioError) {
						console.warn("System audio capture failed, falling back to video-only:", audioError);
						alert(
							"System audio is not available for this source. Recording will continue without system audio.",
						);
						screenMediaStream = await mediaDevices.getUserMedia({
							audio: false,
							video: videoConstraints,
						});
					}
				} else {
					screenMediaStream = await mediaDevices.getUserMedia({
						audio: false,
						video: videoConstraints,
					});
				}

				screenStream.current = screenMediaStream;
				stream.current = new MediaStream();

				videoTrack = screenMediaStream.getVideoTracks()[0];
				if (!videoTrack) {
					throw new Error("Video track is not available.");
				}

				stream.current.addTrack(videoTrack);

				if (microphoneEnabled) {
					try {
						microphoneStream.current = await navigator.mediaDevices.getUserMedia({
							audio: microphoneDeviceId
								? {
										deviceId: { exact: microphoneDeviceId },
										echoCancellation: true,
										noiseSuppression: true,
										autoGainControl: true,
									}
								: {
										echoCancellation: true,
										noiseSuppression: true,
										autoGainControl: true,
									},
							video: false,
						});
					} catch (audioError) {
						console.warn("Failed to get microphone access:", audioError);
						alert(
							"Microphone access was denied. Recording will continue without microphone audio.",
						);
						setMicrophoneEnabled(false);
					}
				}

				const systemAudioTrack = screenMediaStream.getAudioTracks()[0];
				const micAudioTrack = microphoneStream.current?.getAudioTracks()[0];

				if (systemAudioTrack && micAudioTrack) {
					const context = new AudioContext();
					mixingContext.current = context;
					const systemSource = context.createMediaStreamSource(new MediaStream([systemAudioTrack]));
					const micSource = context.createMediaStreamSource(new MediaStream([micAudioTrack]));
					const micGain = context.createGain();
					micGain.gain.value = MIC_GAIN_BOOST;
					const destination = context.createMediaStreamDestination();

					systemSource.connect(destination);
					micSource.connect(micGain).connect(destination);

					const mixedTrack = destination.stream.getAudioTracks()[0];
					if (mixedTrack) {
						stream.current.addTrack(mixedTrack);
						systemAudioIncluded = true;
					}
				} else if (systemAudioTrack) {
					stream.current.addTrack(systemAudioTrack);
					systemAudioIncluded = true;
				} else if (micAudioTrack) {
					stream.current.addTrack(micAudioTrack);
				}
			} else {
				const mediaStream = await mediaDevices.getDisplayMedia({
					audio: false,
					video: {
						displaySurface: selectedSource.id?.startsWith("window:") ? "window" : "monitor",
						width: { ideal: TARGET_WIDTH, max: TARGET_WIDTH },
						height: { ideal: TARGET_HEIGHT, max: TARGET_HEIGHT },
						frameRate: { ideal: TARGET_FRAME_RATE, max: TARGET_FRAME_RATE },
						cursor: shouldHideSourceCursor ? "never" : "always",
					},
					selfBrowserSurface: "exclude",
					surfaceSwitching: "exclude",
				});

				stream.current = mediaStream;
				videoTrack = mediaStream.getVideoTracks()[0];
			}

			if (!stream.current || !videoTrack) {
				throw new Error("Media stream is not available.");
			}

			try {
				await videoTrack.applyConstraints({
					frameRate: { ideal: TARGET_FRAME_RATE, max: TARGET_FRAME_RATE },
					width: { ideal: TARGET_WIDTH, max: TARGET_WIDTH },
					height: { ideal: TARGET_HEIGHT, max: TARGET_HEIGHT },
				} as MediaTrackConstraints);
			} catch (error) {
				console.warn(
					"Unable to lock 4K/60fps constraints, using best available track settings.",
					error,
				);
			}

			let {
				width = DEFAULT_WIDTH,
				height = DEFAULT_HEIGHT,
				frameRate = TARGET_FRAME_RATE,
			} = videoTrack.getSettings();

			width = Math.floor(width / CODEC_ALIGNMENT) * CODEC_ALIGNMENT;
			height = Math.floor(height / CODEC_ALIGNMENT) * CODEC_ALIGNMENT;

			const videoBitsPerSecond = computeBitrate(width, height);
			const mimeType = selectMimeType();

			console.log(
				`Recording at ${width}x${height} @ ${frameRate ?? TARGET_FRAME_RATE}fps using ${mimeType} / ${Math.round(
					videoBitsPerSecond / BITS_PER_MEGABIT,
				)} Mbps`,
			);

			resetStagedFileState(
				recordingFilePath,
				recordingWriteChain,
				recordingWriteError,
				recordingHasData,
			);
			const videoFileName = `${RECORDING_FILE_PREFIX}${recordingSessionId.current}${VIDEO_FILE_EXTENSION}`;
			recordingFilePath.current = await backend.prepareRecordingFile(videoFileName);
			const hasAudio = stream.current.getAudioTracks().length > 0;
			const recorder = new MediaRecorder(stream.current, {
				mimeType,
				videoBitsPerSecond,
				...(hasAudio
					? { audioBitsPerSecond: systemAudioIncluded ? AUDIO_BITRATE_SYSTEM : AUDIO_BITRATE_VOICE }
					: {}),
			});

			mediaRecorder.current = recorder;
			recorder.ondataavailable = (event) => {
				if (event.data && event.data.size > 0) {
					void queueRecordingChunkWrite(
						recordingFilePath,
						recordingWriteChain,
						recordingWriteError,
						recordingHasData,
						event.data,
					);
				}
			};
			recorder.onerror = () => {
				setRecording(false);
			};
			recorder.onstop = async () => {
				mediaRecorder.current = null;
				cleanupCapturedMedia();

				const duration = Math.max(0, Date.now() - startTime.current);

				try {
					const storedPath = await finalizeStagedWebm(
						recordingFilePath,
						recordingWriteChain,
						recordingWriteError,
						recordingHasData,
						duration,
					);
					if (!storedPath) {
						console.error("Failed to store video");
						await stopLinuxCursorTelemetryCapture(null);
						return;
					}

					await backend.setCurrentVideoPath(storedPath).catch(() => null);
					await stopLinuxCursorTelemetryCapture(storedPath);
					const facecamResult = pendingFacecamResult.current
						? await pendingFacecamResult.current
						: null;
					pendingFacecamResult.current = null;
					const recordingSession = buildRecordingSession(storedPath, facecamResult);

					await backend.setCurrentRecordingSession(recordingSession);
					await backend.switchToEditor(
						buildEditorWindowQuery({
							mode: "session",
							videoPath: storedPath,
							facecamVideoPath: recordingSession.facecamVideoPath ?? null,
							facecamOffsetMs: recordingSession.facecamOffsetMs,
							facecamSettings: recordingSession.facecamSettings,
							sourceName: recordingSession.sourceName,
						}),
					);
				} catch (error) {
					console.error("Error saving recording:", error);
					await stopLinuxCursorTelemetryCapture(null);
					if (recordingFilePath.current) {
						await backend.deleteRecordingFile(recordingFilePath.current).catch(() => null);
					}
					resetStagedFileState(
						recordingFilePath,
						recordingWriteChain,
						recordingWriteError,
						recordingHasData,
					);
				}
			};

			await startFacecamCapture(recordingSessionId.current);
			recorder.start(RECORDER_TIMESLICE_MS);
			startTime.current = Date.now();
			screenRecordingStartedAt.current = startTime.current;
			setRecording(true);
			await backend.setRecordingState(true);
		} catch (error) {
			console.error("Failed to start recording:", error);
			alert(
				error instanceof Error
					? `Failed to start recording: ${error.message}`
					: "Failed to start recording",
			);
			setRecording(false);
			const facecamResultPromise = stopFacecamCapture();
			await stopLinuxCursorTelemetryCapture(recordingFilePath.current);
			cleanupCapturedMedia();
			if (recordingFilePath.current) {
				await backend.deleteRecordingFile(recordingFilePath.current).catch(() => null);
			}
			if (facecamRecordingPath.current) {
				await backend.deleteRecordingFile(facecamRecordingPath.current).catch(() => null);
			}
			resetStagedFileState(
				recordingFilePath,
				recordingWriteChain,
				recordingWriteError,
				recordingHasData,
			);
			resetStagedFileState(
				facecamRecordingPath,
				facecamWriteChain,
				facecamWriteError,
				facecamHasData,
			);
			await facecamResultPromise.catch(() => null);
		} finally {
			startInFlight.current = false;
			setStarting(false);
		}
	};

	const toggleRecording = () => {
		if (starting) {
			return;
		}

		recording ? stopRecording() : void startRecording();
	};

	return {
		recording,
		toggleRecording,
		preparePermissions,
		isMacOS,
		microphoneEnabled,
		setMicrophoneEnabled,
		microphoneDeviceId,
		setMicrophoneDeviceId,
		systemAudioEnabled,
		setSystemAudioEnabled,
		cameraEnabled,
		setCameraEnabled,
		cameraDeviceId,
		setCameraDeviceId,
	};
}
