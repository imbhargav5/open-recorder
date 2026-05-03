// @vitest-environment jsdom
/**
 * Tests for the facecam pendingWrites fix (Issue #8).
 *
 * Verifies that in-flight queueRecordingChunkWrite() promises are tracked and
 * fully awaited in the recorder's onstop handler before finalization begins,
 * preventing facecam data loss when chunks are still being written at stop time.
 *
 * Limitations: the full recording pipeline (MediaRecorder, Tauri backend, stream
 * acquisition) requires heavy mocking. The tests below isolate the critical
 * ondataavailable → onstop ordering concern using a controlled MediaRecorder
 * stub and a deferred appendRecordingData promise. A fully automated end-to-end
 * integration test is not feasible given the complexity of mocking native
 * MediaRecorder behaviour, Tauri IPC, and the multi-step stream acquisition flow.
 */

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cameraEnabledAtom } from "@/atoms/recording";
import { useScreenRecorder } from "./useScreenRecorder";

// ─── Module mocks ─────────────────────────────────────────────────────────────

vi.mock("@/lib/backend", () => ({
	getPlatform: vi.fn(),
	getSelectedSource: vi.fn(),
	prepareRecordingFile: vi.fn(),
	appendRecordingData: vi.fn(),
	readLocalFile: vi.fn(),
	replaceRecordingData: vi.fn(),
	deleteRecordingFile: vi.fn(),
	setRecordingState: vi.fn(),
	setCurrentVideoPath: vi.fn(),
	setCurrentRecordingSession: vi.fn(),
	switchToEditor: vi.fn(),
	startCursorTelemetryCapture: vi.fn(),
	stopCursorTelemetryCapture: vi.fn(),
	hideCursor: vi.fn(),
	onStopRecordingFromTray: vi.fn(),
	onRecordingStateChanged: vi.fn(),
	onRecordingInterrupted: vi.fn(),
}));

vi.mock("@fix-webm-duration/fix", () => ({
	fixParsedWebmDuration: vi.fn().mockReturnValue(false),
}));

vi.mock("@fix-webm-duration/parser", () => ({
	WebmFile: vi.fn().mockImplementation(() => ({})),
}));

vi.mock("@/components/video-editor/editorWindowParams", () => ({
	buildEditorWindowQuery: vi.fn().mockReturnValue(""),
}));

// ─── MediaRecorder stub ───────────────────────────────────────────────────────

const recorderInstances: MockMediaRecorder[] = [];

class MockMediaRecorder {
	ondataavailable: ((event: { data: Blob }) => void) | null = null;
	onstop: (() => Promise<void>) | null = null;
	onstart: (() => void) | null = null;
	onerror: (() => void) | null = null;
	state: "inactive" | "recording" | "paused" = "inactive";

	constructor(_stream: MediaStream, _options?: MediaRecorderOptions) {
		recorderInstances.push(this);
	}

	start(_timeslice?: number) {
		this.state = "recording";
		this.onstart?.();
	}

	stop() {
		this.state = "inactive";
	}

	static isTypeSupported(_type: string) {
		return true;
	}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeVideoTrack() {
	return {
		kind: "video" as const,
		stop: vi.fn(),
		applyConstraints: vi.fn().mockResolvedValue(undefined),
		getSettings: vi.fn().mockReturnValue({ width: 1920, height: 1080, frameRate: 60 }),
	};
}

function makeStream(videoTrack: ReturnType<typeof makeVideoTrack>) {
	return {
		getVideoTracks: () => [videoTrack],
		getAudioTracks: () => [] as MediaStreamTrack[],
		getTracks: () => [videoTrack as unknown as MediaStreamTrack],
		addTrack: vi.fn(),
	};
}

/** Flush pending microtasks and macrotasks several times over. */
async function flushAll() {
	await act(async () => {
		for (let i = 0; i < 8; i++) {
			await Promise.resolve();
			await new Promise<void>((r) => setTimeout(r, 0));
		}
	});
}

type HookHandle = {
	getCurrent: () => ReturnType<typeof useScreenRecorder>;
	unmount: () => Promise<void>;
};

async function mountHook(store: ReturnType<typeof createStore>): Promise<HookHandle> {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);
	let current!: ReturnType<typeof useScreenRecorder>;

	function Harness() {
		current = useScreenRecorder();
		return null;
	}

	await act(async () => {
		root.render(
			<Provider store={store}>
				<Harness />
			</Provider>,
		);
	});
	await flushAll();

	return {
		getCurrent: () => current,
		unmount: async () => {
			await act(async () => root.unmount());
			container.remove();
		},
	};
}

// ─── Global setup ─────────────────────────────────────────────────────────────

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const backend = vi.mocked(await import("@/lib/backend"));

function setupBackendMocks() {
	backend.getPlatform.mockResolvedValue("linux");
	backend.getSelectedSource.mockResolvedValue({ id: "screen:0", name: "Screen 0" });
	backend.prepareRecordingFile.mockImplementation((name: string) =>
		Promise.resolve(`/tmp/${name}`),
	);
	backend.appendRecordingData.mockResolvedValue(undefined);
	backend.readLocalFile.mockResolvedValue(new Uint8Array(0));
	backend.replaceRecordingData.mockResolvedValue(undefined);
	backend.deleteRecordingFile.mockResolvedValue(undefined);
	backend.setRecordingState.mockResolvedValue(undefined);
	backend.setCurrentVideoPath.mockResolvedValue(undefined);
	backend.setCurrentRecordingSession.mockResolvedValue(undefined);
	backend.switchToEditor.mockResolvedValue(undefined);
	backend.startCursorTelemetryCapture.mockResolvedValue(undefined);
	backend.stopCursorTelemetryCapture.mockResolvedValue(undefined);
	backend.hideCursor.mockResolvedValue(undefined);
	backend.onStopRecordingFromTray.mockResolvedValue(() => undefined);
	backend.onRecordingStateChanged.mockResolvedValue(() => undefined);
	backend.onRecordingInterrupted.mockResolvedValue(() => undefined);
}

beforeEach(() => {
	vi.clearAllMocks();
	recorderInstances.length = 0;

	setupBackendMocks();

	(global as Record<string, unknown>).MediaRecorder = MockMediaRecorder;

	const screenTrack = makeVideoTrack();
	const screenStream = makeStream(screenTrack);
	const cameraTrack = makeVideoTrack();
	const cameraStream = makeStream(cameraTrack);

	Object.defineProperty(navigator, "mediaDevices", {
		configurable: true,
		writable: true,
		value: {
			getDisplayMedia: vi.fn().mockResolvedValue(screenStream),
			getUserMedia: vi.fn().mockResolvedValue(cameraStream),
			enumerateDevices: vi.fn().mockResolvedValue([]),
		},
	});

	window.alert = vi.fn();
});

afterEach(() => {
	vi.clearAllMocks();
});

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("useScreenRecorder – facecam pendingWrites (Issue #8)", () => {
	it("awaits in-flight chunk writes before proceeding to finalize facecam recording", async () => {
		// Arrange: appendRecordingData resolves only when we manually unblock it,
		// simulating a slow IPC write still in-flight when onstop fires.
		let resolveWrite!: () => void;
		const writeGate = new Promise<void>((resolve) => {
			resolveWrite = resolve;
		});
		let writeSettled = false;
		backend.appendRecordingData.mockImplementationOnce(async () => {
			await writeGate;
			writeSettled = true;
		});

		const store = createStore();
		store.set(cameraEnabledAtom, true);
		const hook = await mountHook(store);

		// Act: start recording (Linux browser path, camera enabled, no audio).
		await act(async () => {
			hook.getCurrent().toggleRecording();
		});
		await flushAll();

		// Two MediaRecorder instances should exist:
		//   [0] screen recorder (created in startRecording)
		//   [1] camera recorder (created inside startFacecamCapture)
		expect(recorderInstances).toHaveLength(2);
		const cameraRecorder = recorderInstances[1];
		expect(cameraRecorder.ondataavailable).toBeTruthy();
		expect(cameraRecorder.onstop).toBeTruthy();

		// Simulate a facecam chunk arriving while the write is slow.
		const blob = new Blob([new Uint8Array([0xde, 0xad, 0xbe])], { type: "video/webm" });
		act(() => {
			cameraRecorder.ondataavailable?.({ data: blob });
		});

		// Fire onstop while appendRecordingData is still in-flight.
		// With the fix, onstop awaits Promise.all(facecamPendingWrites) before calling
		// finalizeStagedWebm, so backend.readLocalFile must not be called yet.
		let stopResolved = false;
		const stopPromise = (async () => {
			await cameraRecorder.onstop?.();
			stopResolved = true;
		})();

		// Flush microtasks — onstop should be suspended waiting on the write gate.
		await act(async () => {
			for (let i = 0; i < 4; i++) await Promise.resolve();
		});

		expect(writeSettled).toBe(false);
		expect(backend.readLocalFile).not.toHaveBeenCalled();
		expect(stopResolved).toBe(false);

		// Unblock the write and let everything settle.
		resolveWrite();
		await act(async () => {
			await stopPromise;
		});
		await flushAll();

		// After the write completes, finalization proceeds and all data is safe.
		expect(writeSettled).toBe(true);
		expect(backend.readLocalFile).toHaveBeenCalledOnce();
		expect(stopResolved).toBe(true);

		await hook.unmount();
	});
});
