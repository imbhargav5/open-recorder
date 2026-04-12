import { atom } from "jotai";

// --- Active recording state ---
export const recordingActiveAtom = atom<boolean>(false);

// --- Microphone configuration ---
export const microphoneEnabledAtom = atom<boolean>(false);
export const microphoneDeviceIdAtom = atom<string | undefined>(undefined);

// --- System audio configuration ---
export const systemAudioEnabledAtom = atom<boolean>(false);

// --- Camera / facecam configuration ---
export const cameraEnabledAtom = atom<boolean>(false);
export const cameraDeviceIdAtom = atom<string | undefined>(undefined);
