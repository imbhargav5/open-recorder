import { useCallback, useMemo, useRef } from "react";
import * as backend from "@/lib/backend";
import {
	buildRecordingSession,
	type FacecamCaptureResult,
	type FacecamRecorderController,
	type MutableRef,
	openRecordingSessionInEditor,
	type RecorderController,
	type RecorderStartInput,
	selectPreferredMimeType,
} from "./screenRecorderShared";
import {
	createStagedRecordingFileState,
	finalizeStagedRecordingFile,
	queueStagedRecordingChunk,
	resetStagedRecordingFile,
} from "./stagedRecordingFile";

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
const AUDIO_BITRATE_VOICE = 128_000;
const AUDIO_BITRATE_SYSTEM = 192_000;
const MIC_GAIN_BOOST = 1.4;

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

type UseChromiumScreenRecorderOptions = {
	facecamRecorder: FacecamRecorderController;
	mountedRef: MutableRef<boolean>;
	selectedSourceNameRef: MutableRef<string | undefined>;
	setMicrophoneEnabled: (enabled: boolean) => void;
	setRecording: (recording: boolean) => void;
};

function computeBitrate(width: number, height: number) {
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
}

export function useChromiumScreenRecorder({
	facecamRecorder,
	mountedRef,
	selectedSourceNameRef,
	setMicrophoneEnabled,
	setRecording,
}: UseChromiumScreenRecorderOptions): RecorderController {
	const activeRef = useRef(false);
	const mediaRecorder = useRef<MediaRecorder | null>(null);
	const stream = useRef<MediaStream | null>(null);
	const screenStream = useRef<MediaStream | null>(null);
	const microphoneStream = useRef<MediaStream | null>(null);
	const mixingContext = useRef<AudioContext | null>(null);
	const startTime = useRef<number>(0);
	const cursorTelemetryCaptureActive = useRef(false);
	const pendingFacecamResult = useRef<Promise<FacecamCaptureResult> | null>(null);
	const recordingFile = useRef(createStagedRecordingFileState());

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

		if (mixingContext.current) {
			mixingContext.current.close().catch(() => {
				// Ignore close races during teardown.
			});
			mixingContext.current = null;
		}
	}, []);

	const cleanup = useCallback(() => {
		activeRef.current = false;

		if (mediaRecorder.current?.state === "recording") {
			mediaRecorder.current.stop();
		}
		mediaRecorder.current = null;

		void stopCursorTelemetryCapture(null);
		cleanupCapturedMedia();

		if (recordingFile.current.path) {
			void backend.deleteRecordingFile(recordingFile.current.path).catch(() => null);
		}
		resetStagedRecordingFile(recordingFile.current);
		pendingFacecamResult.current = null;
	}, [cleanupCapturedMedia, stopCursorTelemetryCapture]);

	const stop = useCallback(() => {
		if (mediaRecorder.current?.state !== "recording") {
			return;
		}

		activeRef.current = false;
		pendingFacecamResult.current = facecamRecorder.stop();
		cleanupCapturedMedia();
		mediaRecorder.current.stop();
		setRecording(false);
		void backend.setRecordingState(false);
	}, [cleanupCapturedMedia, facecamRecorder, setRecording]);

	const start = useCallback(
		async (input: RecorderStartInput) => {
			const mediaDevices = navigator.mediaDevices as DesktopCaptureMediaDevices;

			try {
				await backend.startCursorTelemetryCapture();
				cursorTelemetryCaptureActive.current = true;
			} catch (error) {
				cursorTelemetryCaptureActive.current = false;
				console.warn("Cursor telemetry capture is unavailable:", error);
			}

			const wantsAudioCapture = input.microphoneEnabled || input.systemAudioEnabled;
			const shouldHideSourceCursor = cursorTelemetryCaptureActive.current;

			try {
				await backend.hideCursor();
			} catch {
				console.warn("Could not hide OS cursor before recording.");
			}

			let videoTrack: MediaStreamTrack | undefined;
			let systemAudioIncluded = false;

			if (wantsAudioCapture) {
				const videoConstraints: ChromeDesktopVideoConstraints = {
					mandatory: {
						chromeMediaSource: CHROME_MEDIA_SOURCE,
						chromeMediaSourceId: input.source.id,
						maxWidth: TARGET_WIDTH,
						maxHeight: TARGET_HEIGHT,
						maxFrameRate: TARGET_FRAME_RATE,
						minFrameRate: MIN_FRAME_RATE,
						cursor: shouldHideSourceCursor ? "never" : "always",
					},
				};

				let screenMediaStream: MediaStream;

				if (input.systemAudioEnabled) {
					try {
						screenMediaStream = await mediaDevices.getUserMedia({
							audio: {
								mandatory: {
									chromeMediaSource: CHROME_MEDIA_SOURCE,
									chromeMediaSourceId: input.source.id,
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

				if (input.microphoneEnabled) {
					try {
						microphoneStream.current = await navigator.mediaDevices.getUserMedia({
							audio: input.microphoneDeviceId
								? {
										deviceId: { exact: input.microphoneDeviceId },
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
						displaySurface: input.source.id?.startsWith("window:") ? "window" : "monitor",
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
			const mimeType = selectPreferredMimeType();

			console.log(
				`Recording at ${width}x${height} @ ${frameRate ?? TARGET_FRAME_RATE}fps using ${mimeType} / ${Math.round(
					videoBitsPerSecond / BITS_PER_MEGABIT,
				)} Mbps`,
			);

			resetStagedRecordingFile(recordingFile.current);
			const videoFileName = `${RECORDING_FILE_PREFIX}${input.sessionId}${VIDEO_FILE_EXTENSION}`;
			recordingFile.current.path = await backend.prepareRecordingFile(videoFileName);
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
					void queueStagedRecordingChunk(recordingFile.current, backend, event.data);
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
					const storedPath = await finalizeStagedRecordingFile(
						recordingFile.current,
						backend,
						duration,
					);
					if (!storedPath) {
						console.error("Failed to store video");
						await stopCursorTelemetryCapture(null);
						return;
					}

					await backend.setCurrentVideoPath(storedPath).catch(() => null);
					await stopCursorTelemetryCapture(storedPath);
					const facecamResult = pendingFacecamResult.current
						? await pendingFacecamResult.current
						: null;
					pendingFacecamResult.current = null;
					if (!mountedRef.current) return;

					const recordingSession = buildRecordingSession(
						storedPath,
						facecamResult,
						selectedSourceNameRef.current,
						true,
					);

					await backend.setCurrentRecordingSession(recordingSession);
					if (!mountedRef.current) return;

					await openRecordingSessionInEditor(recordingSession);
				} catch (error) {
					console.error("Error saving recording:", error);
					await stopCursorTelemetryCapture(null);
					if (recordingFile.current.path) {
						await backend.deleteRecordingFile(recordingFile.current.path).catch(() => null);
					}
					resetStagedRecordingFile(recordingFile.current);
				}
			};

			await facecamRecorder.start(input.sessionId);
			recorder.start(RECORDER_TIMESLICE_MS);
			const screenStartedAt = Date.now();
			startTime.current = screenStartedAt;
			facecamRecorder.setScreenStartedAt(screenStartedAt);
			activeRef.current = true;
			setRecording(true);
			await backend.setRecordingState(true);
		},
		[
			cleanupCapturedMedia,
			facecamRecorder,
			mountedRef,
			selectedSourceNameRef,
			setMicrophoneEnabled,
			setRecording,
			stopCursorTelemetryCapture,
		],
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
