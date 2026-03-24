/**
 * Central hook for checking and requesting all application permissions.
 * Works across macOS, Windows, and Linux.
 *
 * On macOS, uses native AVFoundation / CoreGraphics APIs via Tauri commands.
 * On other platforms, permissions are assumed granted (system handles them
 * transparently via getUserMedia / getDisplayMedia prompts).
 */

import { useCallback, useEffect, useRef, useState } from "react";
import * as backend from "@/lib/backend";

export type PermissionStatus = "granted" | "denied" | "not_determined" | "restricted" | "unknown" | "checking";

export interface PermissionState {
	screenRecording: PermissionStatus;
	microphone: PermissionStatus;
	camera: PermissionStatus;
	accessibility: PermissionStatus;
}

export interface UsePermissionsResult {
	permissions: PermissionState;
	isMacOS: boolean;
	isChecking: boolean;
	/** Re-check all permission statuses from the OS */
	refreshPermissions: () => Promise<PermissionState>;
	/** Request microphone permission via getUserMedia (triggers OS prompt if not_determined) */
	requestMicrophoneAccess: () => Promise<boolean>;
	/** Request camera permission via getUserMedia (triggers OS prompt if not_determined) */
	requestCameraAccess: () => Promise<boolean>;
	/** Request screen recording permission (macOS-specific) */
	requestScreenRecordingAccess: () => Promise<boolean>;
	/** Open the OS settings pane for a specific permission */
	openPermissionSettings: (permission: keyof PermissionState) => Promise<void>;
	/** True when all required permissions (screen recording, accessibility) are granted */
	allRequiredPermissionsGranted: boolean;
	/** True when all permissions including optional ones are granted */
	allPermissionsGranted: boolean;
}

const INITIAL_STATE: PermissionState = {
	screenRecording: "checking",
	microphone: "checking",
	camera: "checking",
	accessibility: "checking",
};

export function usePermissions(): UsePermissionsResult {
	const [permissions, setPermissions] = useState<PermissionState>(INITIAL_STATE);
	const [isMacOS, setIsMacOS] = useState(false);
	const [isChecking, setIsChecking] = useState(true);
	const mountedRef = useRef(true);

	const refreshPermissions = useCallback(async (): Promise<PermissionState> => {
		const platform = await backend.getPlatform();
		const mac = platform === "darwin";

		if (mountedRef.current) {
			setIsMacOS(mac);
		}

		if (!mac) {
			// On non-macOS, all permissions are implicitly granted
			const granted: PermissionState = {
				screenRecording: "granted",
				microphone: "granted",
				camera: "granted",
				accessibility: "granted",
			};
			if (mountedRef.current) {
				setPermissions(granted);
				setIsChecking(false);
			}
			return granted;
		}

		// Fetch all statuses in parallel on macOS
		const [screenStatus, micStatus, camStatus, accessStatus] = await Promise.all([
			backend.getScreenRecordingPermissionStatus().catch(() => "unknown"),
			backend.getMicrophonePermissionStatus().catch(() => "unknown"),
			backend.getCameraPermissionStatus().catch(() => "unknown"),
			backend.getAccessibilityPermissionStatus().catch(() => "unknown"),
		]);

		const state: PermissionState = {
			screenRecording: screenStatus as PermissionStatus,
			microphone: micStatus as PermissionStatus,
			camera: camStatus as PermissionStatus,
			accessibility: accessStatus as PermissionStatus,
		};

		if (mountedRef.current) {
			setPermissions(state);
			setIsChecking(false);
		}

		return state;
	}, []);

	const requestMicrophoneAccess = useCallback(async (): Promise<boolean> => {
		try {
			const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
			stream.getTracks().forEach((track) => track.stop());
			// Refresh status after granting
			const state = await refreshPermissions();
			return state.microphone === "granted";
		} catch {
			// Permission denied or error — refresh to get accurate status
			await refreshPermissions();
			return false;
		}
	}, [refreshPermissions]);

	const requestCameraAccess = useCallback(async (): Promise<boolean> => {
		try {
			const stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: true });
			stream.getTracks().forEach((track) => track.stop());
			const state = await refreshPermissions();
			return state.camera === "granted";
		} catch {
			await refreshPermissions();
			return false;
		}
	}, [refreshPermissions]);

	const requestScreenRecordingAccess = useCallback(async (): Promise<boolean> => {
		const granted = await backend.requestScreenRecordingPermission().catch(() => false);
		if (granted) {
			await refreshPermissions();
			return true;
		}
		// Check again in case the status changed
		const state = await refreshPermissions();
		return state.screenRecording === "granted";
	}, [refreshPermissions]);

	const openPermissionSettings = useCallback(
		async (permission: keyof PermissionState): Promise<void> => {
			switch (permission) {
				case "screenRecording":
					await backend.openScreenRecordingPreferences();
					break;
				case "microphone":
					await backend.openMicrophonePreferences();
					break;
				case "camera":
					await backend.openCameraPreferences();
					break;
				case "accessibility":
					await backend.openAccessibilityPreferences();
					break;
			}
		},
		[],
	);

	// Check permissions on mount
	useEffect(() => {
		mountedRef.current = true;
		void refreshPermissions();
		return () => {
			mountedRef.current = false;
		};
	}, [refreshPermissions]);

	const allRequiredPermissionsGranted =
		permissions.screenRecording === "granted" && permissions.accessibility === "granted";

	const allPermissionsGranted =
		allRequiredPermissionsGranted &&
		permissions.microphone === "granted" &&
		permissions.camera === "granted";

	return {
		permissions,
		isMacOS,
		isChecking,
		refreshPermissions,
		requestMicrophoneAccess,
		requestCameraAccess,
		requestScreenRecordingAccess,
		openPermissionSettings,
		allRequiredPermissionsGranted,
		allPermissionsGranted,
	};
}
