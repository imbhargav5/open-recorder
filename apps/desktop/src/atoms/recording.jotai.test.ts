/**
 * Jotai atom tests for recording.ts and sourceSelector.ts
 *
 * Tests cover:
 * - Default values
 * - Enabling / disabling devices
 * - Switching source selector tabs
 * - Managing the source list
 * - Store isolation
 */

import { createStore } from "jotai";
import { beforeEach, describe, expect, it } from "vitest";
import {
	cameraDeviceIdAtom,
	cameraEnabledAtom,
	microphoneDeviceIdAtom,
	microphoneEnabledAtom,
	recordingActiveAtom,
	systemAudioEnabledAtom,
} from "./recording";
import {
	selectedDesktopSourceAtom,
	sourceSelectorTabAtom,
	sourcesAtom,
	sourcesLoadingAtom,
	windowsLoadingAtom,
} from "./sourceSelector";

// ─── recording.ts – defaults ─────────────────────────────────────────────────

describe("recording atoms – defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("recordingActiveAtom defaults to false", () => {
		expect(store.get(recordingActiveAtom)).toBe(false);
	});

	it("microphoneEnabledAtom defaults to false", () => {
		expect(store.get(microphoneEnabledAtom)).toBe(false);
	});

	it("microphoneDeviceIdAtom defaults to undefined", () => {
		expect(store.get(microphoneDeviceIdAtom)).toBeUndefined();
	});

	it("systemAudioEnabledAtom defaults to false", () => {
		expect(store.get(systemAudioEnabledAtom)).toBe(false);
	});

	it("cameraEnabledAtom defaults to false", () => {
		expect(store.get(cameraEnabledAtom)).toBe(false);
	});

	it("cameraDeviceIdAtom defaults to undefined", () => {
		expect(store.get(cameraDeviceIdAtom)).toBeUndefined();
	});
});

// ─── recording.ts – mutations ────────────────────────────────────────────────

describe("recording atoms – mutations", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can activate recording", () => {
		store.set(recordingActiveAtom, true);
		expect(store.get(recordingActiveAtom)).toBe(true);
	});

	it("can enable microphone", () => {
		store.set(microphoneEnabledAtom, true);
		expect(store.get(microphoneEnabledAtom)).toBe(true);
	});

	it("can set a specific microphone device ID", () => {
		store.set(microphoneDeviceIdAtom, "mic-device-123");
		expect(store.get(microphoneDeviceIdAtom)).toBe("mic-device-123");
	});

	it("can enable system audio", () => {
		store.set(systemAudioEnabledAtom, true);
		expect(store.get(systemAudioEnabledAtom)).toBe(true);
	});

	it("can enable camera", () => {
		store.set(cameraEnabledAtom, true);
		expect(store.get(cameraEnabledAtom)).toBe(true);
	});

	it("can set a specific camera device ID", () => {
		store.set(cameraDeviceIdAtom, "cam-device-456");
		expect(store.get(cameraDeviceIdAtom)).toBe("cam-device-456");
	});

	it("can disable all devices after enabling them", () => {
		store.set(microphoneEnabledAtom, true);
		store.set(cameraEnabledAtom, true);
		store.set(systemAudioEnabledAtom, true);

		store.set(microphoneEnabledAtom, false);
		store.set(cameraEnabledAtom, false);
		store.set(systemAudioEnabledAtom, false);

		expect(store.get(microphoneEnabledAtom)).toBe(false);
		expect(store.get(cameraEnabledAtom)).toBe(false);
		expect(store.get(systemAudioEnabledAtom)).toBe(false);
	});
});

// ─── recording.ts – store isolation ──────────────────────────────────────────

describe("recording atoms – store isolation", () => {
	it("enabling microphone in storeA does not affect storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(microphoneEnabledAtom, true);
		expect(storeB.get(microphoneEnabledAtom)).toBe(false);
	});

	it("activating recording in storeA does not affect storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(recordingActiveAtom, true);
		expect(storeB.get(recordingActiveAtom)).toBe(false);
	});
});

// ─── sourceSelector.ts – defaults ────────────────────────────────────────────

describe("sourceSelector atoms – defaults", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("sourcesAtom defaults to an empty array", () => {
		expect(store.get(sourcesAtom)).toEqual([]);
	});

	it("selectedDesktopSourceAtom defaults to null", () => {
		expect(store.get(selectedDesktopSourceAtom)).toBeNull();
	});

	it("sourceSelectorTabAtom defaults to 'screens'", () => {
		expect(store.get(sourceSelectorTabAtom)).toBe("screens");
	});

	it("sourcesLoadingAtom defaults to true", () => {
		expect(store.get(sourcesLoadingAtom)).toBe(true);
	});

	it("windowsLoadingAtom defaults to true", () => {
		expect(store.get(windowsLoadingAtom)).toBe(true);
	});
});

// ─── sourceSelector.ts – mutations ───────────────────────────────────────────

describe("sourceSelector atoms – mutations", () => {
	let store: ReturnType<typeof createStore>;

	beforeEach(() => {
		store = createStore();
	});

	it("can switch selector tab to 'windows'", () => {
		store.set(sourceSelectorTabAtom, "windows");
		expect(store.get(sourceSelectorTabAtom)).toBe("windows");
	});

	it("can switch selector tab back to 'screens'", () => {
		store.set(sourceSelectorTabAtom, "windows");
		store.set(sourceSelectorTabAtom, "screens");
		expect(store.get(sourceSelectorTabAtom)).toBe("screens");
	});

	it("can populate sources list", () => {
		const fakeSource = {
			id: "screen:1",
			name: "Display 1",
			thumbnail: null,
			display_id: "1",
			appIcon: null,
			originalName: "Display 1",
			sourceType: "screen" as const,
		};
		store.set(sourcesAtom, [fakeSource]);
		expect(store.get(sourcesAtom)).toHaveLength(1);
		expect(store.get(sourcesAtom)[0].id).toBe("screen:1");
	});

	it("can select a desktop source", () => {
		const fakeSource = {
			id: "screen:1",
			name: "Display 1",
			thumbnail: null,
			display_id: "1",
			appIcon: null,
			originalName: "Display 1",
			sourceType: "screen" as const,
		};
		store.set(selectedDesktopSourceAtom, fakeSource);
		expect(store.get(selectedDesktopSourceAtom)?.id).toBe("screen:1");
	});

	it("can mark sources as loaded (sourcesLoadingAtom)", () => {
		store.set(sourcesLoadingAtom, false);
		expect(store.get(sourcesLoadingAtom)).toBe(false);
	});

	it("can mark windows as loaded (windowsLoadingAtom)", () => {
		store.set(windowsLoadingAtom, false);
		expect(store.get(windowsLoadingAtom)).toBe(false);
	});
});

// ─── sourceSelector.ts – store isolation ─────────────────────────────────────

describe("sourceSelector atoms – store isolation", () => {
	it("switching tab in storeA does not affect storeB", () => {
		const storeA = createStore();
		const storeB = createStore();
		storeA.set(sourceSelectorTabAtom, "windows");
		expect(storeB.get(sourceSelectorTabAtom)).toBe("screens");
	});
});
