// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { FacecamRecorderController, RecorderController } from "./screenRecorderShared";
import { useMacScreenRecorder } from "./useMacScreenRecorder";

vi.mock("@/lib/backend", () => ({
	startCursorTelemetryCapture: vi.fn(),
	stopCursorTelemetryCapture: vi.fn(),
	startNativeScreenRecording: vi.fn(),
	stopNativeScreenRecording: vi.fn(),
	setRecordingState: vi.fn(),
	setCurrentVideoPath: vi.fn(),
	setCurrentRecordingSession: vi.fn(),
	switchToEditor: vi.fn(),
}));

vi.mock("@/components/video-editor/editorWindowParams", () => ({
	buildEditorWindowQuery: vi.fn().mockReturnValue("mode=session"),
}));

const backend = vi.mocked(await import("@/lib/backend"));

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

async function flushEffects() {
	await act(async () => {
		for (let i = 0; i < 6; i++) {
			await Promise.resolve();
			await new Promise((resolve) => setTimeout(resolve, 0));
		}
	});
}

function createFacecamRecorder(): FacecamRecorderController {
	return {
		prepareForNewSession: vi.fn(),
		setScreenStartedAt: vi.fn(),
		start: vi.fn().mockResolvedValue(undefined),
		stop: vi.fn().mockResolvedValue({ path: "/tmp/facecam.webm", offsetMs: 12 }),
		cleanup: vi.fn(),
	};
}

async function mountHook(facecamRecorder: FacecamRecorderController) {
	const container = document.createElement("div");
	const root: Root = createRoot(container);
	const mountedRef = { current: true };
	const selectedSourceNameRef = { current: "External Display" };
	const setRecording = vi.fn();
	let controller!: RecorderController;

	function Harness() {
		controller = useMacScreenRecorder({
			facecamRecorder,
			mountedRef,
			selectedSourceNameRef,
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
		mountedRef,
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
	backend.startCursorTelemetryCapture.mockResolvedValue(undefined);
	backend.stopCursorTelemetryCapture.mockResolvedValue(undefined);
	backend.startNativeScreenRecording.mockResolvedValue("/tmp/native.mov");
	backend.stopNativeScreenRecording.mockResolvedValue("/tmp/native.mov");
	backend.setRecordingState.mockResolvedValue(undefined);
	backend.setCurrentVideoPath.mockResolvedValue(undefined);
	backend.setCurrentRecordingSession.mockResolvedValue(undefined);
	backend.switchToEditor.mockResolvedValue(undefined);
});

afterEach(() => {
	vi.clearAllMocks();
});

describe("useMacScreenRecorder", () => {
	it("starts and stops native capture with cursor telemetry and editor handoff", async () => {
		const facecamRecorder = createFacecamRecorder();
		const hook = await mountHook(facecamRecorder);

		await act(async () => {
			await hook.controller().start({
				source: { id: "screen:42", name: "Display" } as never,
				sessionId: "session-1",
				microphoneEnabled: true,
				microphoneDeviceId: "mic-1",
				systemAudioEnabled: true,
				cameraEnabled: true,
				cameraDeviceId: "camera-1",
			});
		});

		expect(backend.startCursorTelemetryCapture).toHaveBeenCalledOnce();
		expect(backend.startNativeScreenRecording).toHaveBeenCalledWith(
			{ id: "screen:42", name: "Display" },
			{
				captureCursor: false,
				capturesMicrophone: true,
				capturesSystemAudio: true,
				microphoneDeviceId: "mic-1",
			},
		);
		expect(facecamRecorder.setScreenStartedAt).toHaveBeenCalledOnce();
		expect(facecamRecorder.start).toHaveBeenCalledWith("session-1");
		expect(hook.setRecording).toHaveBeenCalledWith(true);
		expect(backend.setRecordingState).toHaveBeenCalledWith(true);

		act(() => {
			hook.controller().stop();
		});
		await flushEffects();

		expect(facecamRecorder.stop).toHaveBeenCalledOnce();
		expect(backend.stopNativeScreenRecording).toHaveBeenCalledOnce();
		expect(backend.stopCursorTelemetryCapture).toHaveBeenCalledWith("/tmp/native.mov");
		expect(backend.setCurrentVideoPath).toHaveBeenCalledWith("/tmp/native.mov");
		expect(backend.setCurrentRecordingSession).toHaveBeenCalledWith(
			expect.objectContaining({
				screenVideoPath: "/tmp/native.mov",
				facecamVideoPath: "/tmp/facecam.webm",
				sourceName: "External Display",
				showCursorOverlay: true,
			}),
		);
		expect(backend.switchToEditor).toHaveBeenCalledWith("mode=session");

		await hook.unmount();
	});
});
