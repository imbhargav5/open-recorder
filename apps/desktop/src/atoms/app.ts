import { atom } from "jotai";

export const windowTypeAtom = atom<string>("");
export const appNameAtom = atom<string>("Open Recorder");
export const isMacOSAtom = atom<boolean>(false);
