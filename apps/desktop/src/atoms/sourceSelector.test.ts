import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import type { DesktopSource } from "@/components/launch/sourceSelectorState";
import {
  selectedDesktopSourceAtom,
  sourceSelectorTabAtom,
  type SourceSelectorTab,
  sourcesAtom,
  sourcesLoadingAtom,
  windowsLoadingAtom,
} from "./sourceSelector";

function makeSource(overrides: Partial<DesktopSource> = {}): DesktopSource {
  return {
    id: "screen:0",
    name: "Main Display",
    thumbnail: null,
    display_id: "0",
    appIcon: null,
    originalName: "Main Display",
    sourceType: "screen",
    ...overrides,
  };
}

describe("sourceSelector atoms – write / read", () => {
  it("sourceSelectorTabAtom can be switched to windows", () => {
    const store = createStore();
    store.set(sourceSelectorTabAtom, "windows");
    expect(store.get(sourceSelectorTabAtom)).toBe("windows");
  });

  it("sourceSelectorTabAtom can be switched back to screens", () => {
    const store = createStore();
    store.set(sourceSelectorTabAtom, "windows");
    store.set(sourceSelectorTabAtom, "screens");
    expect(store.get(sourceSelectorTabAtom)).toBe("screens");
  });

  it("sourceSelectorTabAtom accepts both SourceSelectorTab values", () => {
    const tabs: SourceSelectorTab[] = ["screens", "windows"];
    const store = createStore();
    for (const tab of tabs) {
      store.set(sourceSelectorTabAtom, tab);
      expect(store.get(sourceSelectorTabAtom)).toBe(tab);
    }
  });

  it("sourcesAtom can be populated with screen sources", () => {
    const store = createStore();
    const sources = [
      makeSource({ id: "screen:0", name: "Main Display" }),
      makeSource({ id: "screen:1", name: "External Monitor" }),
    ];
    store.set(sourcesAtom, sources);
    expect(store.get(sourcesAtom)).toHaveLength(2);
    expect(store.get(sourcesAtom)[0].name).toBe("Main Display");
  });

  it("sourcesAtom can be populated with window sources", () => {
    const store = createStore();
    const source = makeSource({
      id: "window:100",
      name: "Finder",
      sourceType: "window",
    });
    store.set(sourcesAtom, [source]);
    expect(store.get(sourcesAtom)[0].sourceType).toBe("window");
  });

  it("sourcesAtom can be cleared back to empty", () => {
    const store = createStore();
    store.set(sourcesAtom, [makeSource()]);
    store.set(sourcesAtom, []);
    expect(store.get(sourcesAtom)).toEqual([]);
  });

  it("selectedDesktopSourceAtom can be set to a source", () => {
    const store = createStore();
    const source = makeSource({ id: "screen:0", name: "Main Display" });
    store.set(selectedDesktopSourceAtom, source);
    expect(store.get(selectedDesktopSourceAtom)).toEqual(source);
    expect(store.get(selectedDesktopSourceAtom)?.name).toBe("Main Display");
  });

  it("selectedDesktopSourceAtom can be cleared back to null", () => {
    const store = createStore();
    store.set(selectedDesktopSourceAtom, makeSource());
    store.set(selectedDesktopSourceAtom, null);
    expect(store.get(selectedDesktopSourceAtom)).toBeNull();
  });

  it("sourcesLoadingAtom can be set to false when loaded", () => {
    const store = createStore();
    store.set(sourcesLoadingAtom, false);
    expect(store.get(sourcesLoadingAtom)).toBe(false);
  });

  it("windowsLoadingAtom can be set to false independently", () => {
    const store = createStore();
    store.set(windowsLoadingAtom, false);
    expect(store.get(windowsLoadingAtom)).toBe(false);
    // sourcesLoadingAtom should remain at its own value
    expect(store.get(sourcesLoadingAtom)).toBe(true);
  });

  it("writes to one store do not affect another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    storeA.set(sourceSelectorTabAtom, "windows");
    storeA.set(sourcesAtom, [makeSource()]);
    storeA.set(selectedDesktopSourceAtom, makeSource());
    storeA.set(sourcesLoadingAtom, false);

    expect(storeB.get(sourceSelectorTabAtom)).toBe("screens");
    expect(storeB.get(sourcesAtom)).toEqual([]);
    expect(storeB.get(selectedDesktopSourceAtom)).toBeNull();
    expect(storeB.get(sourcesLoadingAtom)).toBe(true);
  });
});
