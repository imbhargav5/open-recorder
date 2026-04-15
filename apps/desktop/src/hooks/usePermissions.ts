/**
 * Central hook for checking and requesting all application permissions.
 * Works across macOS, Windows, and Linux.
 *
 * On macOS, uses native AVFoundation / CoreGraphics APIs via Tauri commands.
 * On other platforms, permissions are assumed granted (system handles them
 * transparently via getUserMedia / getDisplayMedia prompts).
 */

import { useAtom } from "jotai";
import { useCallback, useEffect, useRef } from "react";
import { isMacOSAtom } from "@/atoms/app";
import {
	isCheckingPermissionsAtom,
	type PermissionState,
	type PermissionStatus,
	permissionsAtom,
} from "@/atoms/permissions";
import * as backend from "@/lib/backend";

export type { PermissionState, PermissionStatus } from "@/atoms/permissions";

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

export function usePermissions(): UsePermissionsResult {
	const [permissions, setPermissions] = useAtom(permissionsAtom);
	const [isMacOS, setIsMacOS] = useAtom(isMacOSAtom);
	const [isChecking, setIsChecking] = useAtom(isCheckingPermissionsAtom);
	const mountedRef = useRef(true);

	const refreshPermissions = useCallback(async (): Promise<PermissionState> => {
		const platform = await backend.getPlatform();
		const mac = platform === "darwin";

		if (mountedRef.current) {
			setIsMacOS(mac);
		}

		let result: PermissionState;

		if (!mac) {
			// On non-macOS, all permissions are implicitly granted
			result = {
				screenRecording: "granted",
				microphone: "granted",
				camera: "granted",
				accessibility: "granted",
			};
		} else {
			// Fetch all statuses in parallel on macOS
			const [screenStatus, micStatus, camStatus, accessStatus] = await Promise.all([
				backend.getScreenRecordingPermissionStatus().catch(() => "unknown"),
				backend.getMicrophonePermissionStatus().catch(() => "unknown"),
				backend.getCameraPermissionStatus().catch(() => "unknown"),
				backend.getAccessibilityPermissionStatus().catch(() => "unknown"),
			]);

			result = {
				screenRecording: screenStatus as PermissionStatus,
				microphone: micStatus as PermissionStatus,
				camera: camStatus as PermissionStatus,
				accessibility: accessStatus as PermissionStatus,
			};
		}

		// Single atomic commit regardless of which code path ran above
		if (mountedRef.current) {
			setPermissions(result);
			setIsChecking(false);
		}

		return result;
	}, [setIsMacOS, setPermissions, setIsChecking]);

	const requestBrowserMediaAccess = useCallback(
		async (constraints: MediaStreamConstraints, permission: "microphone" | "camera") => {
			try {
				const stream = await navigator.mediaDevices.getUserMedia(constraints);
				stream.getTracks().forEach((track) => track.stop());
				const state = await refreshPermissions();
				return state[permission] === "granted";
			} catch {
				await refreshPermissions();
				return false;
			}
		},
		[refreshPermissions],
	);

	const requestMicrophoneAccess = useCallback(async (): Promise<boolean> => {
		if (isMacOS) {
			try {
				const granted = await backend.requestMicrophonePermission();
				const state = await refreshPermissions();
				return granted || state.microphone === "granted";
			} catch {
				// Fall back to getUserMedia when the native request path is unavailable.
			}
		}

		return requestBrowserMediaAccess({ audio: true, video: false }, "microphone");
	}, [isMacOS, refreshPermissions, requestBrowserMediaAccess]);

	const requestCameraAccess = useCallback(async (): Promise<boolean> => {
		if (isMacOS) {
			try {
				const granted = await backend.requestCameraPermission();
				const state = await refreshPermissions();
				return granted || state.camera === "granted";
			} catch {
				// Fall back to getUserMedia when the native request path is unavailable.
			}
		}

		return requestBrowserMediaAccess({ audio: false, video: true }, "camera");
	}, [isMacOS, refreshPermissions, requestBrowserMediaAccess]);

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
