/**
 * Factory for a fake RecordingSession object used in E2E tests.
 */
import type { RecordingSession } from "../setup/shim-registry";

export function fakeRecordingSession(
  overrides: Partial<RecordingSession> = {},
): RecordingSession {
  return {
    videoPath: "/tmp/test-recording.webm",
    facecamPath: null,
    facecamOffsetMs: 0,
    startedAt: Date.now() - 5000,
    sourceId: "screen:0:0",
    sourceName: "Main Display",
    width: 1920,
    height: 1080,
    frameRate: 60,
    cursorTelemetryPath: null,
    ...overrides,
  };
}
