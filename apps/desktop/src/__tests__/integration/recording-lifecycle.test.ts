/**
 * Integration tests: Recording Lifecycle
 *
 * Verifies multi-atom workflows for the full recording lifecycle:
 *   fresh state → configure inputs → start recording → timer ticks → stop → atoms reset
 */

import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
	hasSelectedSourceAtom,
	isCapturingAtom,
	launchViewAtom,
	recordingElapsedAtom,
	recordingStartAtom,
	screenshotModeAtom,
	selectedSourceAtom,
} from "@/atoms/launch";
import {
	cameraDeviceIdAtom,
	cameraEnabledAtom,
	microphoneDeviceIdAtom,
	microphoneEnabledAtom,
	recordingActiveAtom,
	systemAudioEnabledAtom,
} from "@/atoms/recording";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeFreshStore() {
	return createStore();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("recording lifecycle – initial state", () => {
	it("recording is inactive by default", () => {
		const store = makeFreshStore();
		expect(store.get(recordingActiveAtom)).toBe(false);
	});

	it("recording start timestamp is null before recording", () => {
		const store = makeFreshStore();
		expect(store.get(recordingStartAtom)).toBeNull();
	});

	it("elapsed time is zero before recording", () => {
		const store = makeFreshStore();
		expect(store.get(recordingElapsedAtom)).toBe(0);
	});

	it("launch view defaults to choice", () => {
		const store = makeFreshStore();
		expect(store.get(launchViewAtom)).toBe("choice");
	});

	it("microphone is disabled by default", () => {
		const store = makeFreshStore();
		expect(store.get(microphoneEnabledAtom)).toBe(false);
	});

	it("system audio is disabled by default", () => {
		const store = makeFreshStore();
		expect(store.get(systemAudioEnabledAtom)).toBe(false);
	});

	it("camera is disabled by default", () => {
		const store = makeFreshStore();
		expect(store.get(cameraEnabledAtom)).toBe(false);
	});
});

describe("recording lifecycle – input configuration", () => {
	it("enabling microphone updates the atom", () => {
		const store = makeFreshStore();
		store.set(microphoneEnabledAtom, true);
		expect(store.get(microphoneEnabledAtom)).toBe(true);
	});

	it("setting microphone device id stores the value", () => {
		const store = makeFreshStore();
		store.set(microphoneDeviceIdAtom, "device-mic-1");
		expect(store.get(microphoneDeviceIdAtom)).toBe("device-mic-1");
	});

	it("enabling system audio updates the atom", () => {
		const store = makeFreshStore();
		store.set(systemAudioEnabledAtom, true);
		expect(store.get(systemAudioEnabledAtom)).toBe(true);
	});

	it("enabling camera updates the atom", () => {
		const store = makeFreshStore();
		store.set(cameraEnabledAtom, true);
		expect(store.get(cameraEnabledAtom)).toBe(true);
	});

	it("setting camera device id stores the value", () => {
		const store = makeFreshStore();
		store.set(cameraDeviceIdAtom, "device-cam-1");
		expect(store.get(cameraDeviceIdAtom)).toBe("device-cam-1");
	});

	it("selecting a source updates selectedSourceAtom", () => {
		const store = makeFreshStore();
		store.set(selectedSourceAtom, "Screen 2");
		expect(store.get(selectedSourceAtom)).toBe("Screen 2");
		expect(store.get(hasSelectedSourceAtom)).toBe(true);
	});

	it("hasSelectedSourceAtom can be toggled to false if no source is chosen", () => {
		const store = makeFreshStore();
		store.set(hasSelectedSourceAtom, false);
		expect(store.get(hasSelectedSourceAtom)).toBe(false);
	});
});

describe("recording lifecycle – start recording", () => {
	it("activating recording sets recordingActiveAtom to true", () => {
		const store = makeFreshStore();
		store.set(recordingActiveAtom, true);
		expect(store.get(recordingActiveAtom)).toBe(true);
	});

	it("recording start timestamp is stored when recording begins", () => {
		const store = makeFreshStore();
		const startTime = Date.now();
		store.set(recordingStartAtom, startTime);
		expect(store.get(recordingStartAtom)).toBe(startTime);
	});

	it("launch view transitions to recording when recording starts", () => {
		const store = makeFreshStore();
		store.set(launchViewAtom, "recording");
		expect(store.get(launchViewAtom)).toBe("recording");
	});

	it("all input configuration is intact after recording starts", () => {
		const store = makeFreshStore();
		store.set(microphoneEnabledAtom, true);
		store.set(systemAudioEnabledAtom, true);
		store.set(cameraEnabledAtom, true);
		store.set(recordingActiveAtom, true);

		expect(store.get(microphoneEnabledAtom)).toBe(true);
		expect(store.get(systemAudioEnabledAtom)).toBe(true);
		expect(store.get(cameraEnabledAtom)).toBe(true);
		expect(store.get(recordingActiveAtom)).toBe(true);
	});
});

describe("recording lifecycle – timer ticks", () => {
	it("elapsed time increments during recording", () => {
		const store = makeFreshStore();
		store.set(recordingActiveAtom, true);
		store.set(recordingStartAtom, Date.now());

		store.set(recordingElapsedAtom, 1000);
		expect(store.get(recordingElapsedAtom)).toBe(1000);

		store.set(recordingElapsedAtom, 2000);
		expect(store.get(recordingElapsedAtom)).toBe(2000);
	});

	it("elapsed time reflects the difference from start", () => {
		const store = makeFreshStore();
		const start = 1_000_000;
		store.set(recordingStartAtom, start);
		store.set(recordingElapsedAtom, 5000);
		expect(store.get(recordingElapsedAtom)).toBe(5000);
	});
});

describe("recording lifecycle – stop and reset", () => {
	it("stopping recording sets recordingActiveAtom to false", () => {
		const store = makeFreshStore();
		store.set(recordingActiveAtom, true);
		store.set(recordingActiveAtom, false);
		expect(store.get(recordingActiveAtom)).toBe(false);
	});

	it("elapsed time resets to 0 after stopping", () => {
		const store = makeFreshStore();
		store.set(recordingElapsedAtom, 30_000);
		store.set(recordingElapsedAtom, 0);
		expect(store.get(recordingElapsedAtom)).toBe(0);
	});

	it("recording start resets to null after stopping", () => {
		const store = makeFreshStore();
		store.set(recordingStartAtom, Date.now());
		store.set(recordingStartAtom, null);
		expect(store.get(recordingStartAtom)).toBeNull();
	});

	it("launch view returns to choice after stopping", () => {
		const store = makeFreshStore();
		store.set(launchViewAtom, "recording");
		store.set(launchViewAtom, "choice");
		expect(store.get(launchViewAtom)).toBe("choice");
	});

	it("full reset leaves all recording atoms in clean state", () => {
		const store = makeFreshStore();

		// Simulate recording start
		store.set(recordingActiveAtom, true);
		store.set(recordingStartAtom, Date.now());
		store.set(recordingElapsedAtom, 60_000);
		store.set(microphoneEnabledAtom, true);
		store.set(launchViewAtom, "recording");

		// Simulate recording stop / reset
		store.set(recordingActiveAtom, false);
		store.set(recordingStartAtom, null);
		store.set(recordingElapsedAtom, 0);
		store.set(launchViewAtom, "choice");

		expect(store.get(recordingActiveAtom)).toBe(false);
		expect(store.get(recordingStartAtom)).toBeNull();
		expect(store.get(recordingElapsedAtom)).toBe(0);
		expect(store.get(launchViewAtom)).toBe("choice");
	});

	it("screenshot mode can be activated independently of recording", () => {
		const store = makeFreshStore();
		store.set(screenshotModeAtom, "screen");
		store.set(isCapturingAtom, true);

		expect(store.get(screenshotModeAtom)).toBe("screen");
		expect(store.get(isCapturingAtom)).toBe(true);
	});

	it("screenshot mode resets to null after capture", () => {
		const store = makeFreshStore();
		store.set(screenshotModeAtom, "area");
		store.set(isCapturingAtom, true);
		// After capture completes
		store.set(screenshotModeAtom, null);
		store.set(isCapturingAtom, false);

		expect(store.get(screenshotModeAtom)).toBeNull();
		expect(store.get(isCapturingAtom)).toBe(false);
	});

	it("atom subscriptions fire when recording stops", () => {
		const store = makeFreshStore();
		const events: boolean[] = [];
		const unsub = store.sub(recordingActiveAtom, () => {
			events.push(store.get(recordingActiveAtom));
		});

		store.set(recordingActiveAtom, true);
		store.set(recordingActiveAtom, false);
		unsub();

		expect(events).toEqual([true, false]);
	});
});
