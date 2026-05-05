import { atom } from "jotai";

export type LaunchView = "onboarding" | "choice" | "screenshot" | "recording";
export type ScreenshotMode = "screen" | "window" | "area";
export type OnboardingStep = "welcome" | "screen_recording" | "microphone" | "camera" | "done";

export function getInitialLaunchView(): LaunchView {
	try {
		return localStorage.getItem("open-recorder-onboarding-v1") === "true" ? "choice" : "onboarding";
	} catch {
		return "choice";
	}
}

export const launchViewAtom = atom<LaunchView>("choice");
export const screenshotModeAtom = atom<ScreenshotMode | null>(null);
export const isCapturingAtom = atom<boolean>(false);
export const recordingStartAtom = atom<number | null>(null);
export const recordingElapsedAtom = atom<number>(0);
export type SelectedSourceStatus = {
	name: string | null;
	available: boolean;
	error: Error | null;
};

export const selectedSourceStatusAtom = atom<SelectedSourceStatus>({
	name: "Main Display",
	available: true,
	error: null,
});
export const selectedSourceAtom = atom(
	(get) => get(selectedSourceStatusAtom).name ?? "",
	(get, set, name: string) => {
		const previous = get(selectedSourceStatusAtom);
		set(selectedSourceStatusAtom, {
			...previous,
			name,
			available: name.length > 0,
		});
	},
);
export const hasSelectedSourceAtom = atom(
	(get) => get(selectedSourceStatusAtom).available,
	(get, set, available: boolean) => {
		const previous = get(selectedSourceStatusAtom);
		set(selectedSourceStatusAtom, {
			...previous,
			available,
		});
	},
);
export const sourceCheckErrorAtom = atom(
	(get) => get(selectedSourceStatusAtom).error,
	(get, set, error: Error | null) => {
		const previous = get(selectedSourceStatusAtom);
		set(selectedSourceStatusAtom, {
			...previous,
			error,
		});
	},
);
export const permissionOnboardingStepAtom = atom<OnboardingStep>("welcome");
export const permissionOnboardingRequestingAtom = atom<boolean>(false);
export const screenRecordingAwaitingRelaunchAtom = atom<boolean>(false);
export const resetPermissionOnboardingAtom = atom(null, (_get, set) => {
	set(permissionOnboardingStepAtom, "welcome");
	set(permissionOnboardingRequestingAtom, false);
	set(screenRecordingAwaitingRelaunchAtom, false);
});
