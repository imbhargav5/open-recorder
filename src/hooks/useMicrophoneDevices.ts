import {
	type PermissionAwareMediaDevicesResult,
	type SelectableMediaDevice,
	usePermissionAwareMediaDevices,
} from "./usePermissionAwareMediaDevices";

export interface MicrophoneDevice extends SelectableMediaDevice {}

export interface UseMicrophoneDevicesResult extends PermissionAwareMediaDevicesResult {
	devices: MicrophoneDevice[];
}

export function useMicrophoneDevices(enabled: boolean = true): UseMicrophoneDevicesResult {
	return usePermissionAwareMediaDevices({
		enabled,
		kind: "audioinput",
		fallbackLabelPrefix: "Microphone",
		unavailableMessage: "Microphone device listing is unavailable in this window",
	});
}
