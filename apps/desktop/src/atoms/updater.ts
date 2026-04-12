import { atom } from "jotai";

export type UpdateStatus =
	| "idle"
	| "checking"
	| "up-to-date"
	| "available"
	| "downloading"
	| "ready"
	| "error";

export const updaterStatusAtom = atom<UpdateStatus>("idle");
export const updaterDialogOpenAtom = atom<boolean>(false);
export const updaterVersionAtom = atom<string | null>(null);
export const updaterReleaseNotesAtom = atom<string | null>(null);
export const updaterDownloadProgressAtom = atom<number>(0);
export const updaterErrorAtom = atom<string | null>(null);
