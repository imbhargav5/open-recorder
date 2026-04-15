/**
 * Factory for fake screen/window source arrays used in E2E tests.
 */
import type { ProcessedDesktopSource } from "../setup/shim-registry";

export function fakeScreenSources(): ProcessedDesktopSource[] {
  return [
    {
      id: "screen:0:0",
      name: "Main Display",
      sourceType: "screen",
      thumbnail: null,
      appIcon: null,
      displayId: "0",
    },
    {
      id: "screen:1:0",
      name: "External Monitor",
      sourceType: "screen",
      thumbnail: null,
      appIcon: null,
      displayId: "1",
    },
  ];
}

export function fakeWindowSources(): ProcessedDesktopSource[] {
  return [
    {
      id: "window:1234",
      name: "Google Chrome",
      sourceType: "window",
      thumbnail: null,
      appIcon: null,
      windowId: 1234,
      windowTitle: "Google Chrome",
    },
    {
      id: "window:5678",
      name: "Visual Studio Code",
      sourceType: "window",
      thumbnail: null,
      appIcon: null,
      windowId: 5678,
      windowTitle: "Visual Studio Code",
    },
  ];
}

export function fakeMixedSources(): ProcessedDesktopSource[] {
  return [...fakeScreenSources(), ...fakeWindowSources()];
}
