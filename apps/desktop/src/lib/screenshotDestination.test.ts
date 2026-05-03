import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mkdirMock = vi.fn();
const existsSyncMock = vi.fn();
const execFileMock = vi.fn();
const getPathMock = vi.fn();

vi.mock("node:fs", () => ({
	default: {
		promises: {
			mkdir: mkdirMock,
		},
		existsSync: existsSyncMock,
	},
}));

vi.mock("node:child_process", () => ({
	execFile: execFileMock,
}));

vi.mock("electron", () => ({
	app: {
		getPath: getPathMock,
	},
}));

const originalPlatform = process.platform;

function setPlatform(platform: NodeJS.Platform): void {
	Object.defineProperty(process, "platform", {
		value: platform,
		configurable: true,
	});
}

beforeEach(() => {
	vi.clearAllMocks();
	vi.resetModules();
	mkdirMock.mockResolvedValue(undefined);
	existsSyncMock.mockReturnValue(true);
	execFileMock.mockImplementation(
		(
			_file: string,
			_args: string[],
			callback: (error: Error | null, stdout?: string, stderr?: string) => void,
		) => callback(null, "", ""),
	);
	getPathMock.mockReturnValue("/tmp/user-data");
});

afterEach(() => {
	Object.defineProperty(process, "platform", {
		value: originalPlatform,
		configurable: true,
	});
});

describe("screenshot destination semantics", () => {
	it("uses a Pictures-based screenshots directory on macOS instead of the recordings directory", async () => {
		setPlatform("darwin");
		const paths = await import("../../electron/app-paths.ts");
		const home = os.homedir();

		expect(paths.defaultRecordingsDir()).toBe(path.join(home, "Movies", "Open Recorder"));
		expect(paths.defaultScreenshotsDir()).toBe(path.join(home, "Pictures", "Open Recorder"));
		expect(paths.defaultScreenshotsDir()).not.toBe(paths.defaultRecordingsDir());
	});

	it("does not route screenshots into the custom recordings directory", async () => {
		setPlatform("darwin");
		const { registerScreenshotHandlers } = await import("../../electron/handlers/screenshot.ts");

		const handlers = new Map<string, (args: unknown) => unknown>();
		const state = {
			customRecordingsDir: "/tmp/custom-recordings",
			currentScreenshotPath: null,
		};

		registerScreenshotHandlers(
			(channel, handler) => {
				handlers.set(channel, handler);
			},
			() => state,
			(updater) => updater(state),
			() => "/tmp/default-screenshots",
		);

		const takeScreenshot = handlers.get("take_screenshot");
		expect(takeScreenshot).toBeTypeOf("function");

		const screenshotPath = await takeScreenshot?.({ captureType: "screen" });
		const outputPath = execFileMock.mock.calls[0]?.[1]?.at(-1);

		expect(mkdirMock).toHaveBeenCalledWith("/tmp/default-screenshots", { recursive: true });
		expect(execFileMock).toHaveBeenCalledOnce();
		expect(outputPath).toBeTypeOf("string");
		expect(path.dirname(outputPath as string)).toBe(path.normalize("/tmp/default-screenshots"));
		expect(path.basename(outputPath as string)).toMatch(/^screenshot-\d+\.png$/);
		expect(screenshotPath).toBe(outputPath);
		expect(state.currentScreenshotPath).toBe(screenshotPath);
	});
});
