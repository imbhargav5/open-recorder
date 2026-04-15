import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
  isCheckingPermissionsAtom,
  type PermissionState,
  type PermissionStatus,
  permissionsAtom,
} from "./permissions";

describe("permissions atoms – write / read", () => {
  it("can update screenRecording permission to granted", () => {
    const store = createStore();
    const updated: PermissionState = {
      ...store.get(permissionsAtom),
      screenRecording: "granted",
    };
    store.set(permissionsAtom, updated);
    expect(store.get(permissionsAtom).screenRecording).toBe("granted");
  });

  it("can update microphone permission to denied", () => {
    const store = createStore();
    const updated: PermissionState = {
      ...store.get(permissionsAtom),
      microphone: "denied",
    };
    store.set(permissionsAtom, updated);
    expect(store.get(permissionsAtom).microphone).toBe("denied");
  });

  it("can set all permissions to granted at once", () => {
    const store = createStore();
    const allGranted: PermissionState = {
      screenRecording: "granted",
      microphone: "granted",
      camera: "granted",
      accessibility: "granted",
    };
    store.set(permissionsAtom, allGranted);
    const result = store.get(permissionsAtom);
    expect(result.screenRecording).toBe("granted");
    expect(result.microphone).toBe("granted");
    expect(result.camera).toBe("granted");
    expect(result.accessibility).toBe("granted");
  });

  it("can set all permissions to denied at once", () => {
    const store = createStore();
    store.set(permissionsAtom, {
      screenRecording: "denied",
      microphone: "denied",
      camera: "denied",
      accessibility: "denied",
    });
    const result = store.get(permissionsAtom);
    expect(result.screenRecording).toBe("denied");
    expect(result.microphone).toBe("denied");
  });

  it("supports every PermissionStatus value", () => {
    const statuses: PermissionStatus[] = [
      "granted",
      "denied",
      "not_determined",
      "restricted",
      "unknown",
      "checking",
    ];
    const store = createStore();
    for (const status of statuses) {
      store.set(permissionsAtom, {
        screenRecording: status,
        microphone: status,
        camera: status,
        accessibility: status,
      });
      expect(store.get(permissionsAtom).screenRecording).toBe(status);
    }
  });

  it("isCheckingPermissionsAtom can be set to false", () => {
    const store = createStore();
    store.set(isCheckingPermissionsAtom, false);
    expect(store.get(isCheckingPermissionsAtom)).toBe(false);
  });

  it("isCheckingPermissionsAtom can be toggled back to true", () => {
    const store = createStore();
    store.set(isCheckingPermissionsAtom, false);
    store.set(isCheckingPermissionsAtom, true);
    expect(store.get(isCheckingPermissionsAtom)).toBe(true);
  });

  it("updating one permission key leaves others unchanged", () => {
    const store = createStore();
    const before = store.get(permissionsAtom);
    store.set(permissionsAtom, { ...before, camera: "granted" });
    const after = store.get(permissionsAtom);
    expect(after.screenRecording).toBe(before.screenRecording);
    expect(after.microphone).toBe(before.microphone);
    expect(after.accessibility).toBe(before.accessibility);
    expect(after.camera).toBe("granted");
  });

  it("permissionsAtom holds an object with the four expected keys", () => {
    const store = createStore();
    const state = store.get(permissionsAtom);
    expect(state).toHaveProperty("screenRecording");
    expect(state).toHaveProperty("microphone");
    expect(state).toHaveProperty("camera");
    expect(state).toHaveProperty("accessibility");
  });

  it("writes to one store do not affect another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    storeA.set(permissionsAtom, {
      screenRecording: "granted",
      microphone: "granted",
      camera: "granted",
      accessibility: "granted",
    });
    storeA.set(isCheckingPermissionsAtom, false);

    expect(storeB.get(permissionsAtom).screenRecording).toBe("checking");
    expect(storeB.get(isCheckingPermissionsAtom)).toBe(true);
  });

  it("can transition from checking → not_determined → granted", () => {
    const store = createStore();
    const base: PermissionState = store.get(permissionsAtom);

    store.set(permissionsAtom, { ...base, screenRecording: "not_determined" });
    expect(store.get(permissionsAtom).screenRecording).toBe("not_determined");

    store.set(permissionsAtom, {
      ...store.get(permissionsAtom),
      screenRecording: "granted",
    });
    expect(store.get(permissionsAtom).screenRecording).toBe("granted");
  });

  it("can set restricted status for accessibility", () => {
    const store = createStore();
    const base = store.get(permissionsAtom);
    store.set(permissionsAtom, { ...base, accessibility: "restricted" });
    expect(store.get(permissionsAtom).accessibility).toBe("restricted");
  });

  it("can set unknown status", () => {
    const store = createStore();
    const base = store.get(permissionsAtom);
    store.set(permissionsAtom, { ...base, microphone: "unknown" });
    expect(store.get(permissionsAtom).microphone).toBe("unknown");
  });

  it("isCheckingPermissionsAtom is independent of permissionsAtom", () => {
    const store = createStore();
    store.set(isCheckingPermissionsAtom, false);
    // Changing permissions should not reset isChecking
    store.set(permissionsAtom, {
      screenRecording: "granted",
      microphone: "granted",
      camera: "granted",
      accessibility: "granted",
    });
    expect(store.get(isCheckingPermissionsAtom)).toBe(false);
  });
});
