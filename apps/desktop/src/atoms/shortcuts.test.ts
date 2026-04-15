import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import { DEFAULT_SHORTCUTS, SHORTCUT_ACTIONS, type ShortcutsConfig } from "@/lib/shortcuts";
import { isShortcutsConfigOpenAtom, shortcutsAtom } from "./shortcuts";

describe("shortcuts atoms – write / read", () => {
  it("shortcutsAtom contains all SHORTCUT_ACTIONS keys", () => {
    const store = createStore();
    const config = store.get(shortcutsAtom);
    for (const action of SHORTCUT_ACTIONS) {
      expect(config).toHaveProperty(action);
    }
  });

  it("DEFAULT_SHORTCUTS has a key binding for every action", () => {
    for (const action of SHORTCUT_ACTIONS) {
      expect(DEFAULT_SHORTCUTS[action]).toBeDefined();
      expect(DEFAULT_SHORTCUTS[action].key).toBeTruthy();
    }
  });

  it("deleteSelected default binding has ctrl modifier", () => {
    expect(DEFAULT_SHORTCUTS.deleteSelected.ctrl).toBe(true);
  });

  it("playPause default binding is space", () => {
    expect(DEFAULT_SHORTCUTS.playPause.key).toBe(" ");
  });

  it("shortcutsAtom can be updated with a new binding for addZoom", () => {
    const store = createStore();
    const before = store.get(shortcutsAtom);
    const updated: ShortcutsConfig = {
      ...before,
      addZoom: { key: "e", ctrl: true },
    };
    store.set(shortcutsAtom, updated);
    expect(store.get(shortcutsAtom).addZoom).toEqual({ key: "e", ctrl: true });
  });

  it("shortcutsAtom can be updated with a new binding for playPause", () => {
    const store = createStore();
    const before = store.get(shortcutsAtom);
    store.set(shortcutsAtom, { ...before, playPause: { key: "p" } });
    expect(store.get(shortcutsAtom).playPause).toEqual({ key: "p" });
  });

  it("updating one binding does not affect other bindings", () => {
    const store = createStore();
    const before = store.get(shortcutsAtom);
    store.set(shortcutsAtom, { ...before, addTrim: { key: "q" } });
    const after = store.get(shortcutsAtom);

    // addZoom should still be the default
    expect(after.addZoom).toEqual(before.addZoom);
    expect(after.playPause).toEqual(before.playPause);
  });

  it("isShortcutsConfigOpenAtom can be opened", () => {
    const store = createStore();
    store.set(isShortcutsConfigOpenAtom, true);
    expect(store.get(isShortcutsConfigOpenAtom)).toBe(true);
  });

  it("isShortcutsConfigOpenAtom can be closed after opening", () => {
    const store = createStore();
    store.set(isShortcutsConfigOpenAtom, true);
    store.set(isShortcutsConfigOpenAtom, false);
    expect(store.get(isShortcutsConfigOpenAtom)).toBe(false);
  });

  it("shortcutsAtom can be reset to defaults by setting DEFAULT_SHORTCUTS", () => {
    const store = createStore();
    const before = store.get(shortcutsAtom);
    store.set(shortcutsAtom, {
      ...before,
      addZoom: { key: "x", shift: true },
    });
    // Now reset
    store.set(shortcutsAtom, DEFAULT_SHORTCUTS);
    expect(store.get(shortcutsAtom)).toEqual(DEFAULT_SHORTCUTS);
  });

  it("writes to one store do not affect another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    const customConfig: ShortcutsConfig = {
      ...DEFAULT_SHORTCUTS,
      addZoom: { key: "1", ctrl: true },
    };
    storeA.set(shortcutsAtom, customConfig);
    storeA.set(isShortcutsConfigOpenAtom, true);

    expect(storeB.get(shortcutsAtom)).toEqual(DEFAULT_SHORTCUTS);
    expect(storeB.get(isShortcutsConfigOpenAtom)).toBe(false);
  });
});
