import { atom } from "jotai";

import type { DesktopSource } from "@/components/launch/sourceSelectorState";

export type SourceSelectorTab = "screens" | "windows" | "area";
export type SourceSelectorContext = "recording" | "screenshot";

export function getInitialTab(): SourceSelectorTab {
	try {
		const params = new URLSearchParams(window.location.search);
		if (params.get("tab") === "area") return "area";
		return params.get("tab") === "windows" ? "windows" : "screens";
	} catch {
		return "screens";
	}
}

export function getInitialContext(): SourceSelectorContext {
	try {
		const params = new URLSearchParams(window.location.search);
		return params.get("context") === "screenshot" ? "screenshot" : "recording";
	} catch {
		return "recording";
	}
}

export const sourcesAtom = atom<DesktopSource[]>([]);
export const selectedDesktopSourceAtom = atom<DesktopSource | null>(null);
export const sourceSelectorTabAtom = atom<SourceSelectorTab>("screens");
export const sourceSelectorContextAtom = atom<SourceSelectorContext>("recording");
export const sourcesLoadingAtom = atom<boolean>(true);
export const windowsLoadingAtom = atom<boolean>(true);
