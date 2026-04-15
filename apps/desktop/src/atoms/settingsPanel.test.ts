import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
  type BackgroundTab,
  type SettingsSidebarTab,
  settingsActiveTabAtom,
  settingsBackgroundTabAtom,
  settingsCustomImagesAtom,
  settingsGradientAtom,
  settingsSelectedColorAtom,
  settingsShowCropModalAtom,
} from "./settingsPanel";

describe("settingsPanel atoms – write / read", () => {
  it("settingsActiveTabAtom can cycle through all sidebar tabs", () => {
    const tabs: SettingsSidebarTab[] = [
      "appearance",
      "cursor",
      "camera",
      "background",
      "audio",
    ];
    const store = createStore();
    for (const tab of tabs) {
      store.set(settingsActiveTabAtom, tab);
      expect(store.get(settingsActiveTabAtom)).toBe(tab);
    }
  });

  it("settingsBackgroundTabAtom can cycle through all background tabs", () => {
    const tabs: BackgroundTab[] = ["image", "color", "gradient"];
    const store = createStore();
    for (const tab of tabs) {
      store.set(settingsBackgroundTabAtom, tab);
      expect(store.get(settingsBackgroundTabAtom)).toBe(tab);
    }
  });

  it("settingsCustomImagesAtom can have images added", () => {
    const store = createStore();
    store.set(settingsCustomImagesAtom, ["/img/bg1.png"]);
    expect(store.get(settingsCustomImagesAtom)).toEqual(["/img/bg1.png"]);
  });

  it("settingsCustomImagesAtom can hold multiple paths", () => {
    const store = createStore();
    const paths = ["/img/bg1.png", "/img/bg2.jpg", "/img/bg3.webp"];
    store.set(settingsCustomImagesAtom, paths);
    expect(store.get(settingsCustomImagesAtom)).toHaveLength(3);
    expect(store.get(settingsCustomImagesAtom)).toEqual(paths);
  });

  it("settingsCustomImagesAtom can be cleared back to empty", () => {
    const store = createStore();
    store.set(settingsCustomImagesAtom, ["/img/bg1.png"]);
    store.set(settingsCustomImagesAtom, []);
    expect(store.get(settingsCustomImagesAtom)).toEqual([]);
  });

  it("settingsSelectedColorAtom can be set to various hex colors", () => {
    const store = createStore();
    for (const color of ["#FF0000", "#00FF00", "#0000FF", "#000000", "#FFFFFF"]) {
      store.set(settingsSelectedColorAtom, color);
      expect(store.get(settingsSelectedColorAtom)).toBe(color);
    }
  });

  it("settingsSelectedColorAtom accepts rgba strings", () => {
    const store = createStore();
    store.set(settingsSelectedColorAtom, "rgba(255, 0, 0, 0.5)");
    expect(store.get(settingsSelectedColorAtom)).toBe("rgba(255, 0, 0, 0.5)");
  });

  it("settingsGradientAtom can be updated to a new gradient", () => {
    const store = createStore();
    const gradient = "linear-gradient(90deg, #ff0000, #0000ff)";
    store.set(settingsGradientAtom, gradient);
    expect(store.get(settingsGradientAtom)).toBe(gradient);
  });

  it("settingsShowCropModalAtom can be opened", () => {
    const store = createStore();
    store.set(settingsShowCropModalAtom, true);
    expect(store.get(settingsShowCropModalAtom)).toBe(true);
  });

  it("settingsShowCropModalAtom can be closed after opening", () => {
    const store = createStore();
    store.set(settingsShowCropModalAtom, true);
    store.set(settingsShowCropModalAtom, false);
    expect(store.get(settingsShowCropModalAtom)).toBe(false);
  });

  it("switching active tab does not affect background tab", () => {
    const store = createStore();
    store.set(settingsActiveTabAtom, "cursor");
    store.set(settingsBackgroundTabAtom, "gradient");

    store.set(settingsActiveTabAtom, "audio");
    expect(store.get(settingsBackgroundTabAtom)).toBe("gradient");
  });

  it("writes to one store do not affect another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    storeA.set(settingsActiveTabAtom, "cursor");
    storeA.set(settingsBackgroundTabAtom, "color");
    storeA.set(settingsCustomImagesAtom, ["/img/bg.png"]);
    storeA.set(settingsSelectedColorAtom, "#123456");
    storeA.set(settingsShowCropModalAtom, true);

    expect(storeB.get(settingsActiveTabAtom)).toBe("appearance");
    expect(storeB.get(settingsBackgroundTabAtom)).toBe("image");
    expect(storeB.get(settingsCustomImagesAtom)).toEqual([]);
    expect(storeB.get(settingsSelectedColorAtom)).toBe("#ADADAD");
    expect(storeB.get(settingsShowCropModalAtom)).toBe(false);
  });
});
