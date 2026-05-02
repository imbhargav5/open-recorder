import { atom } from "jotai";
import {
	DEFAULT_SHORTCUTS,
	type ShortcutAction,
	type ShortcutBinding,
	type ShortcutConflict,
	type ShortcutsConfig,
} from "@/lib/shortcuts";

export type ShortcutConflictState = {
	forAction: ShortcutAction;
	pending: ShortcutBinding;
	conflictWith: ShortcutConflict;
} | null;

export const shortcutsAtom = atom<ShortcutsConfig>(DEFAULT_SHORTCUTS);
export const isShortcutsConfigOpenAtom = atom<boolean>(false);
export const shortcutsDraftAtom = atom<ShortcutsConfig>(DEFAULT_SHORTCUTS);
export const shortcutCaptureForAtom = atom<ShortcutAction | null>(null);
export const shortcutConflictAtom = atom<ShortcutConflictState>(null);
export const resetShortcutsConfigDraftAtom = atom(null, (_get, set, shortcuts: ShortcutsConfig) => {
	set(shortcutsDraftAtom, shortcuts);
	set(shortcutCaptureForAtom, null);
	set(shortcutConflictAtom, null);
});
