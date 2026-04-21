import { useEffect, useRef, useState } from "react";

export type MediaInputKind = "audioinput" | "videoinput";

export interface SelectableMediaDevice {
	deviceId: string;
	label: string;
	groupId: string;
}

export interface PermissionAwareMediaDevicesOptions {
	enabled?: boolean;
	kind: MediaInputKind;
	fallbackLabelPrefix: string;
	unavailableMessage: string;
	autoSelectFirstDevice?: boolean;
}

export interface PermissionAwareMediaDevicesResult {
	devices: SelectableMediaDevice[];
	selectedDeviceId: string;
	setSelectedDeviceId: (deviceId: string) => void;
	isLoading: boolean;
	isRequestingAccess: boolean;
	permissionDenied: boolean;
	error: string | null;
}

const PLACEHOLDER_DEVICE_IDS = new Set(["default", "communications"]);

export function filterDevicesByKind(
	devices: MediaDeviceInfo[],
	kind: MediaInputKind,
): MediaDeviceInfo[] {
	return devices.filter((device) => device.kind === kind);
}

export function shouldRequestDeviceAccess(devices: MediaDeviceInfo[]): boolean {
	if (devices.length <= 1) {
		return true;
	}

	if (devices.some((device) => device.label.trim() === "")) {
		return true;
	}

	return devices.every((device) => PLACEHOLDER_DEVICE_IDS.has(device.deviceId));
}

export function mapSelectableDevice(
	device: MediaDeviceInfo,
	fallbackLabelPrefix: string,
): SelectableMediaDevice {
	return {
		deviceId: device.deviceId,
		label: device.label || `${fallbackLabelPrefix} ${device.deviceId.slice(0, 8)}`,
		groupId: device.groupId,
	};
}

export function resolveSelectedDeviceId(
	currentSelectedDeviceId: string,
	devices: SelectableMediaDevice[],
	autoSelectFirstDevice: boolean = false,
): string {
	const hasCurrentSelection =
		currentSelectedDeviceId !== "default" &&
		devices.some((device) => device.deviceId === currentSelectedDeviceId);

	if (hasCurrentSelection) {
		return currentSelectedDeviceId;
	}

	if (autoSelectFirstDevice) {
		return devices[0]?.deviceId ?? "default";
	}

	return "default";
}

export async function enumeratePermissionAwareDevices(
	mediaDevices: MediaDevices,
	kind: MediaInputKind,
	fallbackLabelPrefix: string,
): Promise<SelectableMediaDevice[]> {
	const devices = await mediaDevices.enumerateDevices();
	return filterDevicesByKind(devices, kind)
		.filter((device) => device.deviceId !== "")
		.map((device) => mapSelectableDevice(device, fallbackLabelPrefix));
}

function buildAccessConstraints(kind: MediaInputKind): MediaStreamConstraints {
	if (kind === "audioinput") {
		return { audio: true, video: false };
	}

	return { audio: false, video: true };
}

function isPermissionDeniedError(error: unknown): boolean {
	if (!(error instanceof DOMException)) {
		return false;
	}

	return ["NotAllowedError", "PermissionDeniedError", "SecurityError"].includes(error.name);
}

function getPermissionDeniedMessage(kind: MediaInputKind): string {
	return kind === "audioinput"
		? "Microphone access was denied. Using the system default microphone."
		: "Camera access was denied. Showing the default camera when available.";
}

export function usePermissionAwareMediaDevices({
	enabled = true,
	kind,
	fallbackLabelPrefix,
	unavailableMessage,
	autoSelectFirstDevice = false,
}: PermissionAwareMediaDevicesOptions): PermissionAwareMediaDevicesResult {
	const [devices, setDevices] = useState<SelectableMediaDevice[]>([]);
	const [selectedDeviceId, setSelectedDeviceId] = useState<string>("default");
	const [isLoading, setIsLoading] = useState(false);
	const [isRequestingAccess, setIsRequestingAccess] = useState(false);
	const [permissionDenied, setPermissionDenied] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const permissionDeniedRef = useRef(false);

	useEffect(() => {
		if (!enabled) {
			return;
		}

		const mediaDevices = navigator.mediaDevices;
		if (!mediaDevices?.enumerateDevices) {
			setDevices([]);
			setError(unavailableMessage);
			setPermissionDenied(false);
			setIsLoading(false);
			setIsRequestingAccess(false);
			return;
		}

		let mounted = true;

		const updateSelection = (nextDevices: SelectableMediaDevice[]) => {
			setSelectedDeviceId((currentSelectedDeviceId) =>
				resolveSelectedDeviceId(currentSelectedDeviceId, nextDevices, autoSelectFirstDevice),
			);
		};

		const loadDevices = async (allowPermissionPrompt: boolean) => {
			try {
				setIsLoading(true);
				setIsRequestingAccess(false);
				setError(null);

				const initialDeviceInfos = filterDevicesByKind(await mediaDevices.enumerateDevices(), kind);
				let nextDevices = initialDeviceInfos
					.filter((device) => device.deviceId !== "")
					.map((device) => mapSelectableDevice(device, fallbackLabelPrefix));

				const needsPermissionPrompt =
					allowPermissionPrompt &&
					typeof mediaDevices.getUserMedia === "function" &&
					shouldRequestDeviceAccess(initialDeviceInfos);

				if (needsPermissionPrompt) {
					let temporaryStream: MediaStream | null = null;
					setIsRequestingAccess(true);

					try {
						temporaryStream = await mediaDevices.getUserMedia(buildAccessConstraints(kind));
						permissionDeniedRef.current = false;
						setPermissionDenied(false);
						setError(null);
					} catch (permissionError) {
						if (!mounted) {
							return;
						}

						const denied = isPermissionDeniedError(permissionError);
						permissionDeniedRef.current = denied;
						setPermissionDenied(denied);
						setError(
							denied
								? getPermissionDeniedMessage(kind)
								: permissionError instanceof Error
									? permissionError.message
									: "Failed to access media devices",
						);
					} finally {
						temporaryStream?.getTracks().forEach((track) => track.stop());
						setIsRequestingAccess(false);
					}

					nextDevices = await enumeratePermissionAwareDevices(
						mediaDevices,
						kind,
						fallbackLabelPrefix,
					);
				} else if (permissionDeniedRef.current && !shouldRequestDeviceAccess(initialDeviceInfos)) {
					// We were latched as "denied" but the browser is now handing
					// us real device labels, which only happens once the OS has
					// actually granted access.  Clear the latch so callers stop
					// rendering the denied banner.
					permissionDeniedRef.current = false;
					setPermissionDenied(false);
					setError(null);
				} else {
					setPermissionDenied(permissionDeniedRef.current);
				}

				if (mounted) {
					setDevices(nextDevices);
					updateSelection(nextDevices);
					setIsLoading(false);
				}
			} catch (loadError) {
				if (mounted) {
					setDevices([]);
					setIsLoading(false);
					setIsRequestingAccess(false);
					setPermissionDenied(false);
					setError(
						loadError instanceof Error ? loadError.message : "Failed to enumerate media devices",
					);
					console.error(`Error loading ${kind} devices:`, loadError);
				}
			}
		};

		void loadDevices(true);

		const handleDeviceChange = () => {
			void loadDevices(!permissionDeniedRef.current);
		};

		// Re-probe whenever the window regains focus or becomes visible.  The
		// user may have flipped a permission toggle in macOS System Settings
		// and returned to the app — Electron does not always fire a
		// `devicechange` in that case, so the cached `permissionDeniedRef`
		// latch would otherwise stay `true` forever.  When we are latched we
		// retry with prompting allowed: `getUserMedia` resolves silently if
		// the grant is already in place and rejects immediately if it isn't,
		// so this won't surface a redundant OS dialog on every focus.
		let pendingRefresh = false;
		const maybeRefresh = () => {
			if (pendingRefresh) {
				return;
			}
			pendingRefresh = true;
			queueMicrotask(() => {
				pendingRefresh = false;
				if (!mounted) {
					return;
				}
				void loadDevices(permissionDeniedRef.current);
			});
		};
		const handleFocus = () => {
			maybeRefresh();
		};
		const handleVisibilityChange = () => {
			if (typeof document !== "undefined" && document.visibilityState === "visible") {
				maybeRefresh();
			}
		};

		mediaDevices.addEventListener?.("devicechange", handleDeviceChange);
		if (typeof window !== "undefined") {
			window.addEventListener("focus", handleFocus);
		}
		if (typeof document !== "undefined") {
			document.addEventListener("visibilitychange", handleVisibilityChange);
		}

		return () => {
			mounted = false;
			mediaDevices.removeEventListener?.("devicechange", handleDeviceChange);
			if (typeof window !== "undefined") {
				window.removeEventListener("focus", handleFocus);
			}
			if (typeof document !== "undefined") {
				document.removeEventListener("visibilitychange", handleVisibilityChange);
			}
		};
	}, [autoSelectFirstDevice, enabled, fallbackLabelPrefix, kind, unavailableMessage]);

	return {
		devices,
		selectedDeviceId,
		setSelectedDeviceId,
		isLoading,
		isRequestingAccess,
		permissionDenied,
		error,
	};
}
