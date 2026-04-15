/**
 * Flow 7 — Project persistence
 *
 * Tests the save/load project file IPC contract:
 *  - saveProjectFile is called with valid JSON
 *  - loadCurrentProjectFile returns the saved payload
 *  - The shim correctly round-trips project data
 */

import { expect, test } from "@playwright/test";
import {
  configureHandlers,
  installTauriShim,
} from "../setup/tauri-shim";
import { fakeRecordingSession } from "../fixtures/fake-recording-session";
import {
  fakeProjectFile,
  fakeProjectFileJson,
} from "../fixtures/fake-project-file";

const EDITOR_URL = "/?windowType=editor";

async function setupPersistencePage(page: import("@playwright/test").Page) {
  await installTauriShim(page);
  await configureHandlers(page, {
    get_current_video_path: "/tmp/test-recording.webm",
    get_current_recording_session: fakeRecordingSession(),
    load_current_project_file: fakeProjectFile(),
    get_cursor_telemetry: [],
    get_system_cursor_assets: [],
    get_shortcuts: null,
    set_has_unsaved_changes: null,
    save_project_file: "/tmp/test-project.openrec",
  });
}

test.describe("Project persistence", () => {
  test("save_project_file IPC is called with JSON-parseable data", async ({
    page,
  }) => {
    await setupPersistencePage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(500);

    // Simulate calling save_project_file with project JSON
    const projectJson = fakeProjectFileJson();

    await page.evaluate(async (data) => {
      await window.__TAURI_INTERNALS__.invoke("save_project_file", {
        data,
        suggestedName: "my-recording",
      });
    }, projectJson);

    const calls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("save_project_file"),
    );
    expect(calls.length).toBeGreaterThanOrEqual(1);

    const lastCall = calls[calls.length - 1];
    // data must be valid JSON
    expect(() => JSON.parse(lastCall.args.data)).not.toThrow();
    const parsed = JSON.parse(lastCall.args.data) as Record<string, unknown>;
    expect(parsed).toHaveProperty("videoPath");
    expect(parsed).toHaveProperty("timeline");
  });

  test("save_project_file returns the saved file path", async ({ page }) => {
    await setupPersistencePage(page);
    await page.goto(EDITOR_URL);

    const path = await page.evaluate(async () => {
      return window.__TAURI_INTERNALS__.invoke("save_project_file", {
        data: JSON.stringify({ version: "1" }),
        suggestedName: "test-project",
      });
    });

    expect(path).toBe("/tmp/test-project.openrec");
  });

  test("load_current_project_file returns fake project with zoom region", async ({
    page,
  }) => {
    await setupPersistencePage(page);
    await page.goto(EDITOR_URL);

    const project = await page.evaluate(async () => {
      return window.__TAURI_INTERNALS__.invoke("load_current_project_file");
    });

    // The fake project fixture has a zoom region
    expect(project).toBeTruthy();
    // biome-ignore lint/suspicious/noExplicitAny: test assertion
    expect((project as any).timeline.zoomRegions).toHaveLength(1);
    // biome-ignore lint/suspicious/noExplicitAny: test assertion
    expect((project as any).timeline.zoomRegions[0].id).toBe("zoom-001");
  });

  test("load_current_project_file IPC is called on editor mount when project path provided", async ({
    page,
  }) => {
    await setupPersistencePage(page);
    await page.goto(`${EDITOR_URL}&mode=project&projectPath=/tmp/test-project.openrec`);
    await page.waitForTimeout(2_000);

    // Verify the editor attempted to load the project
    const wasCalled = await page.evaluate(() =>
      window.__IPC_WAS_CALLED__("load_current_project_file"),
    );
    expect(wasCalled).toBe(true);
  });

  test("project round-trip: save then load returns same data", async ({
    page,
  }) => {
    await installTauriShim(page);

    // Set up dynamic handler that captures save and returns it on load
    await page.addInitScript(() => {
      let savedData: unknown = null;
      // biome-ignore lint/suspicious/noExplicitAny: test shim
      (window as any).__TEST_HANDLERS__.save_project_file = (args: { data: string }) => {
        savedData = JSON.parse(args.data);
        return "/tmp/project.openrec";
      };
      // biome-ignore lint/suspicious/noExplicitAny: test shim
      (window as any).__TEST_HANDLERS__.load_current_project_file = () => savedData;
      // biome-ignore lint/suspicious/noExplicitAny: test shim
      (window as any).__TEST_HANDLERS__.get_current_video_path = () =>
        "/tmp/test-recording.webm";
      // biome-ignore lint/suspicious/noExplicitAny: test shim
      (window as any).__TEST_HANDLERS__.get_current_recording_session = () => ({
        videoPath: "/tmp/test-recording.webm",
        startedAt: Date.now(),
        sourceName: "Main Display",
      });
    });

    await page.goto(EDITOR_URL);
    await page.waitForTimeout(500);

    const projectData = fakeProjectFileJson();

    // Save project
    await page.evaluate(async (data) => {
      await window.__TAURI_INTERNALS__.invoke("save_project_file", { data });
    }, projectData);

    // Load project — should return what we saved
    const loaded = await page.evaluate(async () => {
      return window.__TAURI_INTERNALS__.invoke("load_current_project_file");
    });

    expect(loaded).toBeTruthy();
    // biome-ignore lint/suspicious/noExplicitAny: test assertion
    expect((loaded as any).videoPath).toBe("/tmp/test-recording.webm");
    // biome-ignore lint/suspicious/noExplicitAny: test assertion
    expect((loaded as any).timeline.zoomRegions).toHaveLength(1);
  });

  test("set_has_unsaved_changes is called with true when project is modified", async ({
    page,
  }) => {
    await setupPersistencePage(page);
    await page.goto(EDITOR_URL);
    await page.waitForTimeout(500);

    // Simulate marking the project as having unsaved changes
    await page.evaluate(async () => {
      await window.__TAURI_INTERNALS__.invoke("set_has_unsaved_changes", {
        hasChanges: true,
      });
    });

    const calls = await page.evaluate(() =>
      window.__IPC_GET_CALLS__("set_has_unsaved_changes"),
    );
    const trueCall = calls.find((c) => c.args.hasChanges === true);
    expect(trueCall).toBeTruthy();
  });
});
