// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useScreenRecorder } from "./useScreenRecorder";

// ─── Mock the backend module ──────────────────────────────────────────────────

vi.mock("@/lib/backend", () => ({
	getPlatform: vi.fn(),
	getSelectedSource: vi.fn(),
	startNativeScreenRecording: vi.fn(),
	stopNativeScreenRecording: vi.fn(),
	setRecordingState: vi.fn(),
	setCurrentVideoPath: vi.fn(),
	setCurrentRecordingSession: vi.fn(),
	switchToEditor: vi.fn(),
	muxWgcRecording: vi.fn(),
	isWgcAvailable: vi.fn(),
	prepareRecordingFile: vi.fn(),
	appendRecordingData: vi.fn(),
	replaceRecordingData: vi.fn(),
	readLocalFile: vi.fn(),
	deleteRecordingFile: vi.fn(),
	onStopRecordingFromTray: vi.fn(),
	onRecordingStateChanged: vi.fn(),
	onRecordingInterrupted: vi.fn(),
	getEffectiveScreenRecordingPermissionStatus: vi.fn(),
	getScreenRecordingPermissionStatus: vi.fn(),
	requestScreenRecordingPermission: vi.fn(),
	openScreenRecordingPreferences: vi.fn(),
	getAccessibilityPermissionStatus: vi.fn(),
	requestAccessibilityPermission: vi.fn(),
	openAccessibilityPreferences: vi.fn(),
	getMicrophonePermissionStatus: vi.fn(),
	requestMicrophonePermission: vi.fn(),
	openMicrophonePreferences: vi.fn(),
	getCameraPermissionStatus: vi.fn(),
	requestCameraPermission: vi.fn(),
	openCameraPreferences: vi.fn(),
	hideCursor: vi.fn(),
	startCursorTelemetryCapture: vi.fn(),
	stopCursorTelemetryCapture: vi.fn(),
}));

// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const backend = vi.mocked(await import("@/lib/backend"));

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

type HookHarnessResult = {
	getCurrent: () => ReturnType<typeof useScreenRecorder>;
	unmount: () => Promise<void>;
};

async function mountHook(): Promise<HookHarnessResult> {
	const container = document.createElement("div");
	const root: Root = createRoot(container);
	const store = createStore();
	let currentValue!: ReturnType<typeof useScreenRecorder>;

	function Harness() {
		currentValue = useScreenRecorder();
		return null;
	}

	await act(async () => {
		root.render(
			<Provider store={store}>
				<Harness />
			</Provider>,
		);
	});
	await flushEffects();

	return {
		getCurrent: () => currentValue,
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
		},
	};
}

// ─── Setup / Teardown ────────────────────────────────────────────────────────

beforeEach(() => {
	vi.clearAllMocks();

	// Default noop unlisten functions for event listeners
	const makeUnlisten = () => vi.fn().mockResolvedValue(vi.fn());
	backend.onStopRecordingFromTray.mockImplementation(makeUnlisten());
	backend.onRecordingStateChanged.mockImplementation(makeUnlisten());
	backend.onRecordingInterrupted.mockImplementation(makeUnlisten());

	// Sensible defaults: resolve immediately unless the test overrides them
	backend.getPlatform.mockResolvedValue("linux");
	backend.setRecordingState.mockResolvedValue(undefined);
	// switchToEditor, setCurrentVideoPath, setCurrentRecordingSession resolve
	// undefined by default from vi.fn() — await undefined is fine for tests
	backend.deleteRecordingFile.mockResolvedValue(undefined);
});

afterEach(() => {
	// clearAllMocks is sufficient — restoreAllMocks would undo vi.mock() spies
	vi.clearAllMocks();
});

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("useScreenRecorder — async continuation after unmount", () => {
	it("does not call late backend state-setters after unmount mid-stop (native path)", async () => {
		// stopNativeScreenRecording only resolves after we unmount
		let resolveStop!: (value: string) => void;
		backend.stopNativeScreenRecording.mockReturnValue(
			new Promise<string>((res) => {
				resolveStop = res;
			}),
		);

		const hook = await mountHook();

		// Unmount before stopNativeScreenRecording resolves
		await hook.unmount();

		// Now resolve the pending stop — the async IIFE must bail out because
		// mountedRef.current is already false
		await act(async () => {
			resolveStop("/tmp/recording.mp4");
			await flushEffects();
		});

		// The async IIFE should have returned at the first mountedRef guard,
		// before reaching these calls
		expect(backend.setCurrentVideoPath).not.toHaveBeenCalled();
		expect(backend.setCurrentRecordingSession).not.toHaveBeenCalled();
		expect(backend.switchToEditor).not.toHaveBeenCalled();
	});

	it("does not produce 'unmounted component' warnings when stop resolves post-unmount", async () => {
		let resolveStop!: (value: string) => void;
		backend.stopNativeScreenRecording.mockReturnValue(
			new Promise<string>((res) => {
				resolveStop = res;
			}),
		);

		const consoleErrorSpy = vi.spyOn(console, "error");

		const hook = await mountHook();
		await hook.unmount();

		await act(async () => {
			resolveStop("/tmp/recording.webm");
			await flushEffects();
		});

		// React 18 warns about state updates on unmounted components
		const reactUnmountWarnings = consoleErrorSpy.mock.calls.filter((args) =>
			String(args[0]).includes("unmounted"),
		);
		expect(reactUnmountWarnings).toHaveLength(0);

		consoleErrorSpy.mockRestore();
	});

	it("short-circuits each await point after unmount so no further backend calls are made", async () => {
		// Control every async step independently
		let resolveStop!: (v: string) => void;
		let resolveMux!: (v: string) => void;

		backend.stopNativeScreenRecording.mockReturnValue(
			new Promise<string>((res) => {
				resolveStop = res;
			}),
		);
		backend.muxWgcRecording.mockReturnValue(
			new Promise<string>((res) => {
				resolveMux = res;
			}),
		);
		backend.setRecordingState.mockResolvedValue(undefined);

		const hook = await mountHook();

		// Resolve the first await and unmount before the second
		await act(async () => {
			resolveStop("/tmp/rec.mp4");
		});
		await hook.unmount();

		// Resolve the rest — all should be no-ops
		await act(async () => {
			resolveMux?.("/tmp/muxed.mp4");
			await flushEffects();
		});

		expect(backend.switchToEditor).not.toHaveBeenCalled();
		expect(backend.setCurrentVideoPath).not.toHaveBeenCalled();
		expect(backend.setCurrentRecordingSession).not.toHaveBeenCalled();
	});
});

describe("useScreenRecorder — permission preparation", () => {
	beforeEach(() => {
		backend.getPlatform.mockResolvedValue("darwin");
		backend.getEffectiveScreenRecordingPermissionStatus.mockResolvedValue("granted");
		backend.getAccessibilityPermissionStatus.mockResolvedValue("granted");
	});

	it("uses the effective screen-recording status for the re-check path", async () => {
		backend.getEffectiveScreenRecordingPermissionStatus
			.mockResolvedValueOnce("denied")
			.mockResolvedValueOnce("granted");
		backend.requestScreenRecordingPermission.mockResolvedValue(false);

		const hook = await mountHook();

		let allowed = false;
		await act(async () => {
			allowed = await hook.getCurrent().preparePermissions();
		});

		expect(allowed).toBe(true);
		expect(backend.getEffectiveScreenRecordingPermissionStatus).toHaveBeenCalledTimes(2);
		expect(backend.getScreenRecordingPermissionStatus).not.toHaveBeenCalled();
		expect(backend.openScreenRecordingPreferences).not.toHaveBeenCalled();

		await hook.unmount();
	});
});
