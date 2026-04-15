import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
  type UpdateStatus,
  updaterDialogOpenAtom,
  updaterDownloadProgressAtom,
  updaterErrorAtom,
  updaterReleaseNotesAtom,
  updaterStatusAtom,
  updaterVersionAtom,
} from "./updater";

describe("updater atoms – write / read", () => {
  it("updaterStatusAtom can be set to every UpdateStatus value", () => {
    const statuses: UpdateStatus[] = [
      "idle",
      "checking",
      "up-to-date",
      "available",
      "downloading",
      "ready",
      "error",
    ];
    const store = createStore();
    for (const status of statuses) {
      store.set(updaterStatusAtom, status);
      expect(store.get(updaterStatusAtom)).toBe(status);
    }
  });

  it("updaterStatusAtom transitions: idle → checking → available → downloading → ready", () => {
    const store = createStore();
    const flow: UpdateStatus[] = ["checking", "available", "downloading", "ready"];
    for (const status of flow) {
      store.set(updaterStatusAtom, status);
      expect(store.get(updaterStatusAtom)).toBe(status);
    }
  });

  it("updaterDialogOpenAtom can be opened and closed", () => {
    const store = createStore();
    store.set(updaterDialogOpenAtom, true);
    expect(store.get(updaterDialogOpenAtom)).toBe(true);
    store.set(updaterDialogOpenAtom, false);
    expect(store.get(updaterDialogOpenAtom)).toBe(false);
  });

  it("updaterVersionAtom can be set to a semver string", () => {
    const store = createStore();
    store.set(updaterVersionAtom, "1.2.3");
    expect(store.get(updaterVersionAtom)).toBe("1.2.3");
  });

  it("updaterVersionAtom can be cleared back to null", () => {
    const store = createStore();
    store.set(updaterVersionAtom, "2.0.0");
    store.set(updaterVersionAtom, null);
    expect(store.get(updaterVersionAtom)).toBeNull();
  });

  it("updaterReleaseNotesAtom can be set to a markdown string", () => {
    const store = createStore();
    const notes = "## v2.0.0\n- New feature\n- Bug fix";
    store.set(updaterReleaseNotesAtom, notes);
    expect(store.get(updaterReleaseNotesAtom)).toBe(notes);
  });

  it("updaterReleaseNotesAtom can be cleared to null", () => {
    const store = createStore();
    store.set(updaterReleaseNotesAtom, "some notes");
    store.set(updaterReleaseNotesAtom, null);
    expect(store.get(updaterReleaseNotesAtom)).toBeNull();
  });

  it("updaterDownloadProgressAtom can be set to boundary values 0 and 100", () => {
    const store = createStore();
    store.set(updaterDownloadProgressAtom, 0);
    expect(store.get(updaterDownloadProgressAtom)).toBe(0);
    store.set(updaterDownloadProgressAtom, 100);
    expect(store.get(updaterDownloadProgressAtom)).toBe(100);
  });

  it("updaterDownloadProgressAtom tracks incremental progress", () => {
    const store = createStore();
    for (const pct of [0, 25, 50, 75, 100]) {
      store.set(updaterDownloadProgressAtom, pct);
      expect(store.get(updaterDownloadProgressAtom)).toBe(pct);
    }
  });

  it("updaterErrorAtom can be set to an error message", () => {
    const store = createStore();
    store.set(updaterErrorAtom, "Network timeout");
    expect(store.get(updaterErrorAtom)).toBe("Network timeout");
  });

  it("updaterErrorAtom can be cleared after an error is handled", () => {
    const store = createStore();
    store.set(updaterErrorAtom, "Something went wrong");
    store.set(updaterErrorAtom, null);
    expect(store.get(updaterErrorAtom)).toBeNull();
  });

  it("writes to one store do not affect another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    storeA.set(updaterStatusAtom, "available");
    storeA.set(updaterVersionAtom, "3.0.0");
    storeA.set(updaterDialogOpenAtom, true);
    storeA.set(updaterDownloadProgressAtom, 42);

    expect(storeB.get(updaterStatusAtom)).toBe("idle");
    expect(storeB.get(updaterVersionAtom)).toBeNull();
    expect(storeB.get(updaterDialogOpenAtom)).toBe(false);
    expect(storeB.get(updaterDownloadProgressAtom)).toBe(0);
  });
});
