import {
	type PermissionAwareMediaDevicesResult,
	type SelectableMediaDevice,
	usePermissionAwareMediaDevices,
} from "./usePermissionAwareMediaDevices";

export interface CameraDevice extends SelectableMediaDevice {}

export interface UseCameraDevicesResult extends PermissionAwareMediaDevicesResult {
	devices: CameraDevice[];
}

export function useCameraDevices(enabled: boolean = true): UseCameraDevicesResult {
	return usePermissionAwareMediaDevices({
		enabled,
		kind: "videoinput",
		fallbackLabelPrefix: "Camera",
		unavailableMessage: "Camera device listing is unavailable in this window",
		autoSelectFirstDevice: true,
	});
}
