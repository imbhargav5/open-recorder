import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
	hasSelectedSourceAtom,
	isCapturingAtom,
	type LaunchView,
	launchViewAtom,
	type OnboardingStep,
	permissionOnboardingRequestingAtom,
	permissionOnboardingStepAtom,
	recordingElapsedAtom,
	recordingStartAtom,
	resetPermissionOnboardingAtom,
	type ScreenshotMode,
	screenRecordingAwaitingRelaunchAtom,
	screenshotModeAtom,
	selectedSourceAtom,
} from "./launch";

describe("launch atoms – write / read", () => {
	it("launchViewAtom can be set to every LaunchView value", () => {
		const views: LaunchView[] = ["onboarding", "choice", "screenshot", "recording"];
		const store = createStore();
		for (const view of views) {
			store.set(launchViewAtom, view);
			expect(store.get(launchViewAtom)).toBe(view);
		}
	});

	it("screenshotModeAtom can be set to every ScreenshotMode value", () => {
		const modes: ScreenshotMode[] = ["screen", "window", "area"];
		const store = createStore();
		for (const mode of modes) {
			store.set(screenshotModeAtom, mode);
			expect(store.get(screenshotModeAtom)).toBe(mode);
		}
	});

	it("screenshotModeAtom can be cleared back to null", () => {
		const store = createStore();
		store.set(screenshotModeAtom, "screen");
		store.set(screenshotModeAtom, null);
		expect(store.get(screenshotModeAtom)).toBeNull();
	});

	it("isCapturingAtom can be toggled to true and back", () => {
		const store = createStore();
		store.set(isCapturingAtom, true);
		expect(store.get(isCapturingAtom)).toBe(true);
		store.set(isCapturingAtom, false);
		expect(store.get(isCapturingAtom)).toBe(false);
	});

	it("recordingStartAtom can be set to a Unix timestamp", () => {
		const store = createStore();
		const now = Date.now();
		store.set(recordingStartAtom, now);
		expect(store.get(recordingStartAtom)).toBe(now);
	});

	it("recordingStartAtom can be reset to null when recording stops", () => {
		const store = createStore();
		store.set(recordingStartAtom, Date.now());
		store.set(recordingStartAtom, null);
		expect(store.get(recordingStartAtom)).toBeNull();
	});

	it("recordingElapsedAtom can be incremented", () => {
		const store = createStore();
		store.set(recordingElapsedAtom, 1000);
		expect(store.get(recordingElapsedAtom)).toBe(1000);
		store.set(recordingElapsedAtom, 2000);
		expect(store.get(recordingElapsedAtom)).toBe(2000);
	});

	it("recordingElapsedAtom can be reset to 0", () => {
		const store = createStore();
		store.set(recordingElapsedAtom, 5000);
		store.set(recordingElapsedAtom, 0);
		expect(store.get(recordingElapsedAtom)).toBe(0);
	});

	it("selectedSourceAtom can be changed to a different display", () => {
		const store = createStore();
		store.set(selectedSourceAtom, "Display 2");
		expect(store.get(selectedSourceAtom)).toBe("Display 2");
	});

	it("selectedSourceAtom accepts empty string", () => {
		const store = createStore();
		store.set(selectedSourceAtom, "");
		expect(store.get(selectedSourceAtom)).toBe("");
	});

	it("hasSelectedSourceAtom can be set to false when no source is selected", () => {
		const store = createStore();
		store.set(hasSelectedSourceAtom, false);
		expect(store.get(hasSelectedSourceAtom)).toBe(false);
	});

	it("permissionOnboardingStepAtom can be set to every OnboardingStep value", () => {
		const steps: OnboardingStep[] = ["welcome", "screen_recording", "microphone", "camera", "done"];
		const store = createStore();
		for (const step of steps) {
			store.set(permissionOnboardingStepAtom, step);
			expect(store.get(permissionOnboardingStepAtom)).toBe(step);
		}
	});

	it("permission onboarding request flags can be reset together", () => {
		const store = createStore();
		store.set(permissionOnboardingStepAtom, "camera");
		store.set(permissionOnboardingRequestingAtom, true);
		store.set(screenRecordingAwaitingRelaunchAtom, true);
		store.set(resetPermissionOnboardingAtom);
		expect(store.get(permissionOnboardingStepAtom)).toBe("welcome");
		expect(store.get(permissionOnboardingRequestingAtom)).toBe(false);
		expect(store.get(screenRecordingAwaitingRelaunchAtom)).toBe(false);
	});

	it("writes to one store do not affect another store", () => {
		const storeA = createStore();
		const storeB = createStore();

		storeA.set(launchViewAtom, "recording");
		storeA.set(isCapturingAtom, true);
		storeA.set(recordingStartAtom, 12345);
		storeA.set(recordingElapsedAtom, 3000);

		expect(storeB.get(launchViewAtom)).toBe("choice");
		expect(storeB.get(isCapturingAtom)).toBe(false);
		expect(storeB.get(recordingStartAtom)).toBeNull();
		expect(storeB.get(recordingElapsedAtom)).toBe(0);
	});
});
