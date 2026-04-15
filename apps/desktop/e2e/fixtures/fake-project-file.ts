/**
 * Factory for a fake saved project JSON payload used in E2E tests.
 *
 * The exact shape mirrors what the VideoEditor saves via saveProjectFile().
 */

export interface FakeProjectFile {
  filePath: string;
  version: string;
  videoPath: string;
  settings: {
    wallpaper: string;
    padding: number;
    cursorVisible: boolean;
    background: string;
  };
  timeline: {
    duration: number;
    zoomRegions: Array<{
      id: string;
      startTime: number;
      endTime: number;
      zoomFactor: number;
      x: number;
      y: number;
    }>;
  };
}

export function fakeProjectFile(
  overrides: Partial<FakeProjectFile> = {},
): FakeProjectFile {
  return {
    filePath: "/tmp/test-project.openrec",
    version: "1",
    videoPath: "/tmp/test-recording.webm",
    settings: {
      wallpaper: "gradient-dark",
      padding: 40,
      cursorVisible: true,
      background: "#1a1a2e",
    },
    timeline: {
      duration: 10.5,
      zoomRegions: [
        {
          id: "zoom-001",
          startTime: 2.0,
          endTime: 5.0,
          zoomFactor: 2.0,
          x: 0.5,
          y: 0.5,
        },
      ],
    },
    ...overrides,
  };
}

/** Serialise a project file to JSON as the backend would store it. */
export function fakeProjectFileJson(
  overrides: Partial<FakeProjectFile> = {},
): string {
  return JSON.stringify(fakeProjectFile(overrides));
}
