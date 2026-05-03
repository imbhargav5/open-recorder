// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { FacecamRecorderController, RecorderController } from "./screenRecorderShared";
import { useChromiumScreenRecorder } from "./useChromiumScreenRecorder";

vi.mock("@/lib/backend", () => ({
	startCursorTelemetryCapture: vi.fn(),
	stopCursorTelemetryCapture: vi.fn(),
	hideCursor: vi.fn(),
	prepareRecordingFile: vi.fn(),
	appendRecordingData: vi.fn(),
	readLocalFile: vi.fn(),
	replaceRecordingData: vi.fn(),
	deleteRecordingFile: vi.fn(),
	setRecordingState: vi.fn(),
	setCurrentVideoPath: vi.fn(),
	setCurrentRecordingSession: vi.fn(),
	switchToEditor: vi.fn(),
}));

const backend = vi.mocked(await import("@/lib/backend"));

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

const recorderInstances: MockMediaRecorder[] = [];

class MockMediaRecorder {
	ondataavailable: ((event: { data: Blob }) => void) | null = null;
	onstop: (() => Promise<void> | void) | null = null;
	onerror: (() => void) | null = null;
	state: "inactive" | "recording" = "inactive";

	constructor(_stream: MediaStream, _options?: MediaRecorderOptions) {
		recorderInstances.push(this);
	}

	start() {
		this.state = "recording";
	}

	stop() {
		this.state = "inactive";
	}

	static isTypeSupported(_type: string) {
		return true;
	}
}

function makeVideoTrack() {
	return {
		kind: "video" as const,
		stop: vi.fn(),
		applyConstraints: vi.fn().mockResolvedValue(undefined),
		getSettings: vi.fn().mockReturnValue({ width: 1920, height: 1080, frameRate: 60 }),
	};
}

function makeStream(videoTrack = makeVideoTrack()) {
	return {
		getVideoTracks: () => [videoTrack],
		getAudioTracks: () => [] as MediaStreamTrack[],
		getTracks: () => [videoTrack as unknown as MediaStreamTrack],
		addTrack: vi.fn(),
	};
}

function createFacecamRecorder(): FacecamRecorderController {
	return {
		prepareForNewSession: vi.fn(),
		setScreenStartedAt: vi.fn(),
		start: vi.fn().mockResolvedValue(undefined),
		stop: vi.fn().mockResolvedValue(null),
		cleanup: vi.fn(),
	};
}

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function mountHook(facecamRecorder: FacecamRecorderController) {
	const container = document.createElement("div");
	const root: Root = createRoot(container);
	const mountedRef = { current: true };
	const selectedSourceNameRef = { current: "Screen 0" };
	const setMicrophoneEnabled = vi.fn();
	const setRecording = vi.fn();
	let controller!: RecorderController;

	function Harness() {
		controller = useChromiumScreenRecorder({
			facecamRecorder,
			mountedRef,
			selectedSourceNameRef,
			setMicrophoneEnabled,
			setRecording,
		});
		return null;
	}

	await act(async () => {
		root.render(<Harness />);
	});
	await flushEffects();

	return {
		controller: () => controller,
		setRecording,
		unmount: async () => {
			mountedRef.current = false;
			await act(async () => root.unmount());
			container.remove();
		},
	};
}

beforeEach(() => {
	vi.clearAllMocks();
	recorderInstances.length = 0;
	vi.stubGlobal("MediaRecorder", MockMediaRecorder);

	backend.startCursorTelemetryCapture.mockResolvedValue(undefined);
	backend.stopCursorTelemetryCapture.mockResolvedValue(undefined);
	backend.hideCursor.mockResolvedValue(undefined);
	backend.prepareRecordingFile.mockImplementation((name: string) =>
		Promise.resolve(`/tmp/${name}`),
	);
	backend.appendRecordingData.mockResolvedValue(undefined);
	backend.deleteRecordingFile.mockResolvedValue(undefined);
	backend.setRecordingState.mockResolvedValue(undefined);

	Object.defineProperty(navigator, "mediaDevices", {
		configurable: true,
		writable: true,
		value: {
			getDisplayMedia: vi.fn().mockResolvedValue(makeStream()),
			getUserMedia: vi.fn(),
			enumerateDevices: vi.fn().mockResolvedValue([]),
		},
	});
});

afterEach(() => {
	vi.clearAllMocks();
	vi.unstubAllGlobals();
});

describe("useChromiumScreenRecorder", () => {
	it("starts browser capture through Chromium media APIs", async () => {
		const facecamRecorder = createFacecamRecorder();
		const hook = await mountHook(facecamRecorder);

		await act(async () => {
			await hook.controller().start({
				source: { id: "screen:0", name: "Screen 0" } as never,
				sessionId: "session-1",
				microphoneEnabled: false,
				microphoneDeviceId: undefined,
				systemAudioEnabled: false,
				cameraEnabled: false,
				cameraDeviceId: undefined,
			});
		});

		expect(navigator.mediaDevices.getDisplayMedia).toHaveBeenCalledWith(
			expect.objectContaining({
				audio: false,
				selfBrowserSurface: "exclude",
				surfaceSwitching: "exclude",
			}),
		);
		expect(backend.prepareRecordingFile).toHaveBeenCalledWith("recording-session-1.webm");
		expect(recorderInstances).toHaveLength(1);
		expect(recorderInstances[0].state).toBe("recording");
		expect(facecamRecorder.start).toHaveBeenCalledWith("session-1");
		expect(facecamRecorder.setScreenStartedAt).toHaveBeenCalledOnce();
		expect(hook.setRecording).toHaveBeenCalledWith(true);
		expect(backend.setRecordingState).toHaveBeenCalledWith(true);

		await hook.unmount();
	});
});
