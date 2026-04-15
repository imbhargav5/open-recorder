// @vitest-environment jsdom
/**
 * Integration tests: Onboarding Flow
 *
 * Verifies multi-atom workflows for onboarding:
 *   fresh state → permission checks → grant permissions → onboarding complete → view switches
 */

import { createStore } from "jotai/vanilla";
import { afterEach, describe, expect, it, vi } from "vitest";
import { getInitialLaunchView, launchViewAtom } from "@/atoms/launch";
import {
	isCheckingPermissionsAtom,
	type PermissionState,
	permissionsAtom,
} from "@/atoms/permissions";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeFreshStore() {
	return createStore();
}

const ALL_CHECKING: PermissionState = {
	screenRecording: "checking",
	microphone: "checking",
	camera: "checking",
	accessibility: "checking",
};

const ALL_GRANTED: PermissionState = {
	screenRecording: "granted",
	microphone: "granted",
	camera: "granted",
	accessibility: "granted",
};

const PARTIAL_DENIED: PermissionState = {
	screenRecording: "granted",
	microphone: "denied",
	camera: "not_determined",
	accessibility: "granted",
};

// ---------------------------------------------------------------------------
// Initial state
// ---------------------------------------------------------------------------

describe("onboarding – initial permissions state", () => {
	afterEach(() => {
		window.localStorage.clear();
	});

	it("all permissions start in checking state", () => {
		const store = makeFreshStore();
		expect(store.get(permissionsAtom)).toEqual(ALL_CHECKING);
	});

	it("isCheckingPermissionsAtom is true on startup", () => {
		const store = makeFreshStore();
		expect(store.get(isCheckingPermissionsAtom)).toBe(true);
	});

	it("onboarding view shown for fresh install (no localStorage flag)", () => {
		window.localStorage.removeItem("open-recorder-onboarding-v1");
		expect(getInitialLaunchView()).toBe("onboarding");
	});

	it("choice view shown if onboarding was previously completed", () => {
		window.localStorage.setItem("open-recorder-onboarding-v1", "true");
		expect(getInitialLaunchView()).toBe("choice");
	});

	it("falls back to choice when localStorage throws", () => {
		const spy = vi.spyOn(window, "localStorage", "get").mockImplementation(() => {
			throw new Error("quota exceeded");
		});
		expect(getInitialLaunchView()).toBe("choice");
		spy.mockRestore();
	});
});

// ---------------------------------------------------------------------------
// Permission checking phase
// ---------------------------------------------------------------------------

describe("onboarding – permission checking phase", () => {
	it("checking status can be set individually per permission", () => {
		const store = makeFreshStore();
		store.set(permissionsAtom, {
			...ALL_CHECKING,
			screenRecording: "granted",
		});
		expect(store.get(permissionsAtom).screenRecording).toBe("granted");
		expect(store.get(permissionsAtom).microphone).toBe("checking");
	});

	it("isCheckingPermissions transitions to false when done", () => {
		const store = makeFreshStore();
		store.set(isCheckingPermissionsAtom, false);
		expect(store.get(isCheckingPermissionsAtom)).toBe(false);
	});

	it("permissions atom updates atomically as a composite", () => {
		const store = makeFreshStore();
		store.set(permissionsAtom, ALL_GRANTED);

		const perms = store.get(permissionsAtom);
		expect(perms.screenRecording).toBe("granted");
		expect(perms.microphone).toBe("granted");
		expect(perms.camera).toBe("granted");
		expect(perms.accessibility).toBe("granted");
	});
});

// ---------------------------------------------------------------------------
// Granting permissions
// ---------------------------------------------------------------------------

describe("onboarding – granting permissions", () => {
	it("granting screen recording permission updates the atom", () => {
		const store = makeFreshStore();
		store.set(permissionsAtom, { ...ALL_CHECKING, screenRecording: "granted" });
		expect(store.get(permissionsAtom).screenRecording).toBe("granted");
	});

	it("granting microphone permission updates the atom", () => {
		const store = makeFreshStore();
		store.set(permissionsAtom, { ...ALL_CHECKING, microphone: "granted" });
		expect(store.get(permissionsAtom).microphone).toBe("granted");
	});

	it("denied permission is stored correctly", () => {
		const store = makeFreshStore();
		store.set(permissionsAtom, PARTIAL_DENIED);
		expect(store.get(permissionsAtom).microphone).toBe("denied");
	});

	it("restricted permission status is stored correctly", () => {
		const store = makeFreshStore();
		store.set(permissionsAtom, { ...ALL_CHECKING, camera: "restricted" });
		expect(store.get(permissionsAtom).camera).toBe("restricted");
	});

	it("unknown permission status is stored correctly", () => {
		const store = makeFreshStore();
		store.set(permissionsAtom, { ...ALL_CHECKING, accessibility: "unknown" });
		expect(store.get(permissionsAtom).accessibility).toBe("unknown");
	});

	it("permissions subscription fires when status changes", () => {
		const store = makeFreshStore();
		const events: PermissionState[] = [];
		const unsub = store.sub(permissionsAtom, () => {
			events.push(store.get(permissionsAtom));
		});

		store.set(permissionsAtom, { ...ALL_CHECKING, screenRecording: "granted" });
		store.set(permissionsAtom, ALL_GRANTED);
		unsub();

		expect(events).toHaveLength(2);
		expect(events[1].microphone).toBe("granted");
	});
});

// ---------------------------------------------------------------------------
// Onboarding completion → view switch
// ---------------------------------------------------------------------------

describe("onboarding – completion and view switch", () => {
	afterEach(() => {
		window.localStorage.clear();
	});

	it("launchView transitions from onboarding to choice after completion", () => {
		const store = makeFreshStore();
		store.set(launchViewAtom, "onboarding");
		store.set(permissionsAtom, ALL_GRANTED);
		store.set(isCheckingPermissionsAtom, false);

		// Simulate onboarding completion
		window.localStorage.setItem("open-recorder-onboarding-v1", "true");
		store.set(launchViewAtom, "choice");

		expect(store.get(launchViewAtom)).toBe("choice");
		expect(window.localStorage.getItem("open-recorder-onboarding-v1")).toBe("true");
	});

	it("completing onboarding with all permissions granted is the happy path", () => {
		const store = makeFreshStore();

		// Step 1: start onboarding
		store.set(launchViewAtom, "onboarding");
		expect(store.get(isCheckingPermissionsAtom)).toBe(true);

		// Step 2: permissions checked
		store.set(permissionsAtom, ALL_GRANTED);
		store.set(isCheckingPermissionsAtom, false);

		// Step 3: complete
		window.localStorage.setItem("open-recorder-onboarding-v1", "true");
		store.set(launchViewAtom, "choice");

		expect(store.get(launchViewAtom)).toBe("choice");
		expect(store.get(permissionsAtom)).toEqual(ALL_GRANTED);
		expect(store.get(isCheckingPermissionsAtom)).toBe(false);
	});

	it("onboarding can also transition to screenshot view", () => {
		const store = makeFreshStore();
		store.set(launchViewAtom, "onboarding");
		store.set(launchViewAtom, "screenshot");
		expect(store.get(launchViewAtom)).toBe("screenshot");
	});

	it("onboarding can also transition to recording view", () => {
		const store = makeFreshStore();
		store.set(launchViewAtom, "onboarding");
		store.set(launchViewAtom, "recording");
		expect(store.get(launchViewAtom)).toBe("recording");
	});

	it("getInitialLaunchView reflects flag set during onboarding", () => {
		window.localStorage.removeItem("open-recorder-onboarding-v1");
		expect(getInitialLaunchView()).toBe("onboarding");

		// Simulate completing onboarding
		window.localStorage.setItem("open-recorder-onboarding-v1", "true");
		expect(getInitialLaunchView()).toBe("choice");
	});
});
