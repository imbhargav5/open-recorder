import { atomWithStorage } from "jotai/utils";

export type InternalView = "editor" | "projects";

const INTERNAL_VIEW_STORAGE_KEY = "open-recorder.internal-view";
const SIDEBAR_EXPANDED_STORAGE_KEY = "open-recorder.sidebar-expanded";

export const internalViewAtom = atomWithStorage<InternalView>(INTERNAL_VIEW_STORAGE_KEY, "editor");

export const sidebarExpandedAtom = atomWithStorage<boolean>(SIDEBAR_EXPANDED_STORAGE_KEY, false);
