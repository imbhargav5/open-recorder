import { atom } from "jotai";

import type { DesktopSource } from "@/components/launch/sourceSelectorState";

export type SourceSelectorTab = "screens" | "windows";

export function getInitialTab(): SourceSelectorTab {
	try {
		const params = new URLSearchParams(window.location.search);
		return params.get("tab") === "windows" ? "windows" : "screens";
	} catch {
		return "screens";
	}
}

export const sourcesAtom = atom<DesktopSource[]>([]);
export const selectedDesktopSourceAtom = atom<DesktopSource | null>(null);
export const sourceSelectorTabAtom = atom<SourceSelectorTab>("screens");
export const sourcesLoadingAtom = atom<boolean>(true);
export const windowsLoadingAtom = atom<boolean>(true);
