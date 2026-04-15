import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import { appNameAtom, isMacOSAtom, windowTypeAtom } from "./app";

describe("app atoms – write / read", () => {
  it("windowTypeAtom can be set to a non-empty string", () => {
    const store = createStore();
    store.set(windowTypeAtom, "main");
    expect(store.get(windowTypeAtom)).toBe("main");
  });

  it("windowTypeAtom can be set back to empty string", () => {
    const store = createStore();
    store.set(windowTypeAtom, "editor");
    store.set(windowTypeAtom, "");
    expect(store.get(windowTypeAtom)).toBe("");
  });

  it("windowTypeAtom accepts arbitrary strings", () => {
    const store = createStore();
    for (const value of ["launch", "settings", "preview", "about"]) {
      store.set(windowTypeAtom, value);
      expect(store.get(windowTypeAtom)).toBe(value);
    }
  });

  it("appNameAtom can be updated", () => {
    const store = createStore();
    store.set(appNameAtom, "My Recorder");
    expect(store.get(appNameAtom)).toBe("My Recorder");
  });

  it("appNameAtom survives being set to empty string", () => {
    const store = createStore();
    store.set(appNameAtom, "");
    expect(store.get(appNameAtom)).toBe("");
  });

  it("isMacOSAtom can be toggled true then false", () => {
    const store = createStore();
    store.set(isMacOSAtom, true);
    expect(store.get(isMacOSAtom)).toBe(true);
    store.set(isMacOSAtom, false);
    expect(store.get(isMacOSAtom)).toBe(false);
  });

  it("writes to one store do not affect another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    storeA.set(windowTypeAtom, "editor");
    storeA.set(appNameAtom, "Fork Recorder");
    storeA.set(isMacOSAtom, true);

    expect(storeB.get(windowTypeAtom)).toBe("");
    expect(storeB.get(appNameAtom)).toBe("Open Recorder");
    expect(storeB.get(isMacOSAtom)).toBe(false);
  });

  it("multiple successive writes reflect the last value", () => {
    const store = createStore();
    store.set(windowTypeAtom, "a");
    store.set(windowTypeAtom, "b");
    store.set(windowTypeAtom, "c");
    expect(store.get(windowTypeAtom)).toBe("c");
  });
});
