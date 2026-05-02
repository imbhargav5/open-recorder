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
export const selectedSourceAtom = atom<string>("Main Display");
export const hasSelectedSourceAtom = atom<boolean>(true);
export const sourceCheckErrorAtom = atom<Error | null>(null);
export const permissionOnboardingStepAtom = atom<OnboardingStep>("welcome");
export const permissionOnboardingRequestingAtom = atom<boolean>(false);
export const screenRecordingAwaitingRelaunchAtom = atom<boolean>(false);
export const resetPermissionOnboardingAtom = atom(null, (_get, set) => {
	set(permissionOnboardingStepAtom, "welcome");
	set(permissionOnboardingRequestingAtom, false);
	set(screenRecordingAwaitingRelaunchAtom, false);
});
