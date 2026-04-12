import { atom } from 'jotai'

export type PermissionStatus =
	| "granted"
	| "denied"
	| "not_determined"
	| "restricted"
	| "unknown"
	| "checking";

export interface PermissionState {
	screenRecording: PermissionStatus;
	microphone: PermissionStatus;
	camera: PermissionStatus;
	accessibility: PermissionStatus;
}

const INITIAL_PERMISSIONS: PermissionState = {
	screenRecording: "checking",
	microphone: "checking",
	camera: "checking",
	accessibility: "checking",
};

export const permissionsAtom = atom<PermissionState>(INITIAL_PERMISSIONS)
export const isCheckingPermissionsAtom = atom<boolean>(true)
