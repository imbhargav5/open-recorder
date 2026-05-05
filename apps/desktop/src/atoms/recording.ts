import { atom } from "jotai";

// --- Active recording state ---
export type RecordingPhase = "idle" | "starting" | "recording" | "stopping" | "interrupted";

export const recordingPhaseAtom = atom<RecordingPhase>("idle");
export const recordingActiveAtom = atom(
	(get) => get(recordingPhaseAtom) === "recording",
	(_get, set, recording: boolean) => {
		set(recordingPhaseAtom, recording ? "recording" : "idle");
	},
);

// --- Microphone configuration ---
export const microphoneEnabledAtom = atom<boolean>(false);
export const microphoneDeviceIdAtom = atom<string | undefined>(undefined);

// --- System audio configuration ---
export const systemAudioEnabledAtom = atom<boolean>(false);

// --- Camera / facecam configuration ---
export const cameraEnabledAtom = atom<boolean>(false);
export const cameraDeviceIdAtom = atom<string | undefined>(undefined);
