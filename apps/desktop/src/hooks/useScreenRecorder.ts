import { useAtom, useSetAtom, useStore } from "jotai";
import { useCallback, useEffect, useRef } from "react";
import { isMacOSAtom } from "@/atoms/app";
import {
	cameraDeviceIdAtom,
	cameraEnabledAtom,
	microphoneDeviceIdAtom,
	microphoneEnabledAtom,
	recordingActiveAtom,
	recordingPhaseAtom,
	systemAudioEnabledAtom,
} from "@/atoms/recording";
import * as backend from "@/lib/backend";
import { getSelectedSourceName, isScreenOrWindowSource } from "./screenRecorderShared";
import { useChromiumScreenRecorder } from "./useChromiumScreenRecorder";
import { useFacecamRecorder } from "./useFacecamRecorder";
import { useMacScreenRecorder } from "./useMacScreenRecorder";

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

export function useScreenRecorder(): UseScreenRecorderReturn {
	const jotaiStore = useStore();
	const [recording, setRecording] = useAtom(recordingActiveAtom);
	const setRecordingPhase = useSetAtom(recordingPhaseAtom);
	const [isMacOS, setIsMacOS] = useAtom(isMacOSAtom);
	const [microphoneEnabled, setMicrophoneEnabled] = useAtom(microphoneEnabledAtom);
	const [microphoneDeviceId, setMicrophoneDeviceId] = useAtom(microphoneDeviceIdAtom);
	const [systemAudioEnabled, setSystemAudioEnabled] = useAtom(systemAudioEnabledAtom);
	const [cameraEnabled, setCameraEnabled] = useAtom(cameraEnabledAtom);
	const [cameraDeviceId, setCameraDeviceId] = useAtom(cameraDeviceIdAtom);

	const mountedRef = useRef(true);
	const recordingSessionId = useRef("");
	const selectedSourceName = useRef<string | undefined>(undefined);

	const facecamRecorder = useFacecamRecorder({
		cameraEnabled,
		cameraDeviceId,
		setCameraEnabled,
	});
	const macRecorder = useMacScreenRecorder({
		facecamRecorder,
		mountedRef,
		selectedSourceNameRef: selectedSourceName,
		setRecording,
	});
	const chromiumRecorder = useChromiumScreenRecorder({
		facecamRecorder,
		mountedRef,
		selectedSourceNameRef: selectedSourceName,
		setMicrophoneEnabled,
		setRecording,
	});

	const preparePermissions = useCallback(
		async (options: { startup?: boolean } = {}) => {
			const platform = await backend.getPlatform();
			if (platform !== "darwin") {
				return true;
			}

			const screenStatus = await backend.getEffectiveScreenRecordingPermissionStatus();
			if (screenStatus !== "granted") {
				const granted = await backend.requestScreenRecordingPermission();
				if (!granted) {
					const refreshedStatus = await backend.getEffectiveScreenRecordingPermissionStatus();
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

	const stopRecording = useCallback(() => {
		if (macRecorder.isActive()) {
			setRecordingPhase("stopping");
			macRecorder.stop();
			return;
		}

		if (chromiumRecorder.isActive()) {
			setRecordingPhase("stopping");
			chromiumRecorder.stop();
			return;
		}

		setRecordingPhase("idle");
	}, [chromiumRecorder, macRecorder, setRecordingPhase]);

	useEffect(() => {
		void (async () => {
			const platform = await backend.getPlatform();
			setIsMacOS(platform === "darwin");
		})();
	}, [setIsMacOS]);

	useEffect(() => {
		mountedRef.current = true;
		return () => {
			mountedRef.current = false;
		};
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
				setRecordingPhase("interrupted");
				setRecording(false);
				macRecorder.cleanup();
				chromiumRecorder.cleanup();
				facecamRecorder.cleanup();
				void backend.setRecordingState(false);
				setRecordingPhase("idle");
			})
			.then((fn) => {
				unlistenInterrupted = fn;
			});

		return () => {
			unlistenTray?.();
			unlistenState?.();
			unlistenInterrupted?.();

			macRecorder.cleanup();
			chromiumRecorder.cleanup();
			facecamRecorder.cleanup();
		};
	}, [
		chromiumRecorder,
		facecamRecorder,
		macRecorder,
		stopRecording,
		setRecording,
		setRecordingPhase,
	]);

	const startRecording = async () => {
		if (jotaiStore.get(recordingPhaseAtom) !== "idle") {
			return;
		}

		setRecordingPhase("starting");
		recordingSessionId.current = `${Date.now()}`;
		facecamRecorder.prepareForNewSession();

		let recorderForCleanup = chromiumRecorder;

		try {
			const selectedSource = await backend.getSelectedSource();
			selectedSourceName.current = getSelectedSourceName(selectedSource);
			if (!selectedSource) {
				alert("Please select a source to record");
				setRecordingPhase("idle");
				return;
			}

			const permissionsReady = await preparePermissions();
			if (!permissionsReady) {
				setRecordingPhase("idle");
				return;
			}

			const platform = await backend.getPlatform();
			const useNativeMacScreenCapture =
				platform === "darwin" && isScreenOrWindowSource(selectedSource);
			recorderForCleanup = useNativeMacScreenCapture ? macRecorder : chromiumRecorder;

			await recorderForCleanup.start({
				source: selectedSource,
				sessionId: recordingSessionId.current,
				microphoneEnabled,
				microphoneDeviceId,
				systemAudioEnabled,
				cameraEnabled,
				cameraDeviceId,
			});
		} catch (error) {
			console.error("Failed to start recording:", error);
			alert(
				error instanceof Error
					? `Failed to start recording: ${error.message}`
					: "Failed to start recording",
			);
			setRecording(false);
			recorderForCleanup.cleanup();
			facecamRecorder.cleanup();
			setRecordingPhase("idle");
		}
	};

	const toggleRecording = () => {
		const currentPhase = jotaiStore.get(recordingPhaseAtom);
		if (currentPhase === "starting" || currentPhase === "stopping") {
			return;
		}

		jotaiStore.get(recordingActiveAtom) ? stopRecording() : void startRecording();
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
