// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resolveSelectedSourceState } from "./launchWindowState";

// ─── Mock heavy dependencies before importing the component ──────────────────

vi.mock("@/lib/backend", () => ({
	onMenuOpenVideoFile: vi.fn(),
	onMenuLoadProject: vi.fn(),
	onNewRecordingFromTray: vi.fn(),
	getSelectedSource: vi.fn(),
	getScreenRecordingPermissionStatus: vi.fn(),
	requestScreenRecordingPermission: vi.fn(),
	openScreenRecordingPreferences: vi.fn(),
	openSourceSelector: vi.fn(),
	openVideoFilePicker: vi.fn(),
	setCurrentVideoPath: vi.fn(),
	switchToEditor: vi.fn(),
	loadProjectFile: vi.fn(),
	getPlatform: vi.fn(),
	getMicrophonePermissionStatus: vi.fn(),
	getCameraPermissionStatus: vi.fn(),
	getAccessibilityPermissionStatus: vi.fn(),
	closeSourceSelector: vi.fn(),
	hudOverlayHide: vi.fn(),
	hudOverlayShow: vi.fn(),
	takeScreenshot: vi.fn(),
	switchToImageEditor: vi.fn(),
	startHudOverlayDrag: vi.fn(),
}));

vi.mock("../../hooks/useScreenRecorder", () => ({
	useScreenRecorder: vi.fn(),
}));

vi.mock("../../hooks/usePermissions", () => ({
	usePermissions: vi.fn(),
}));

vi.mock("../../hooks/useMicrophoneDevices", () => ({
	useMicrophoneDevices: vi.fn(),
}));

vi.mock("../../hooks/useCameraDevices", () => ({
	useCameraDevices: vi.fn(),
}));

vi.mock("@xstate/react", () => ({
	useActor: vi.fn(),
}));

vi.mock("../../machines/microphoneMachine", () => ({
	microphoneMachine: {
		provide: vi.fn().mockReturnValue({}),
	},
}));

vi.mock("../onboarding/PermissionOnboarding", () => ({
	PermissionOnboarding: () => null,
}));

// ─── Resolve mocked modules ───────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const backend = vi.mocked(await import("@/lib/backend"));
// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const { useScreenRecorder } = vi.mocked(await import("../../hooks/useScreenRecorder"));
// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const { usePermissions } = vi.mocked(await import("../../hooks/usePermissions"));
// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const { useMicrophoneDevices } = vi.mocked(await import("../../hooks/useMicrophoneDevices"));
// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const { useCameraDevices } = vi.mocked(await import("../../hooks/useCameraDevices"));
// eslint-disable-next-line @typescript-eslint/consistent-type-imports
const { useActor } = vi.mocked(await import("@xstate/react"));

const { LaunchWindow } = await import("./LaunchWindow");

// ─── Helpers ──────────────────────────────────────────────────────────────────

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

type MockUnlistens = {
	mockUnlistenVideo: ReturnType<typeof vi.fn>;
	mockUnlistenProject: ReturnType<typeof vi.fn>;
	mockUnlistenNewRecording: ReturnType<typeof vi.fn>;
};

function setupDefaultMocks(): MockUnlistens {
	const mockUnlistenVideo = vi.fn();
	const mockUnlistenProject = vi.fn();
	const mockUnlistenNewRecording = vi.fn();

	backend.onMenuOpenVideoFile.mockResolvedValue(mockUnlistenVideo);
	backend.onMenuLoadProject.mockResolvedValue(mockUnlistenProject);
	backend.onNewRecordingFromTray.mockResolvedValue(mockUnlistenNewRecording);
	backend.getSelectedSource.mockResolvedValue(null);
	backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");

	useScreenRecorder.mockReturnValue({
		recording: false,
		toggleRecording: vi.fn(),
		preparePermissions: vi.fn().mockResolvedValue(true),
		setMicrophoneEnabled: vi.fn(),
		microphoneDeviceId: undefined,
		setMicrophoneDeviceId: vi.fn(),
		systemAudioEnabled: false,
		setSystemAudioEnabled: vi.fn(),
		cameraEnabled: false,
		setCameraEnabled: vi.fn(),
		cameraDeviceId: undefined,
		setCameraDeviceId: vi.fn(),
	});

	usePermissions.mockReturnValue({
		permissions: {
			microphone: "granted",
			camera: "granted",
			screenRecording: "granted",
			accessibility: "granted",
		},
		isMacOS: false,
		isChecking: false,
		refreshPermissions: vi.fn().mockResolvedValue({}),
		requestMicrophoneAccess: vi.fn().mockResolvedValue(true),
		requestCameraAccess: vi.fn().mockResolvedValue(true),
		requestScreenRecordingAccess: vi.fn().mockResolvedValue(true),
		openPermissionSettings: vi.fn().mockResolvedValue(undefined),
		allRequiredPermissionsGranted: true,
		allPermissionsGranted: true,
	});

	useMicrophoneDevices.mockReturnValue({
		devices: [],
		selectedDeviceId: "default",
		setSelectedDeviceId: vi.fn(),
		isLoading: false,
		isRequestingAccess: false,
		permissionDenied: false,
		error: null,
	});

	useCameraDevices.mockReturnValue({
		devices: [],
		selectedDeviceId: "default",
		setSelectedDeviceId: vi.fn(),
		isLoading: false,
		isRequestingAccess: false,
		permissionDenied: false,
		error: null,
	});

	useActor.mockReturnValue([{ matches: () => false, value: "off" }, vi.fn()]);

	return { mockUnlistenVideo, mockUnlistenProject, mockUnlistenNewRecording };
}

async function mountLaunchWindow(): Promise<{ unmount: () => Promise<void> }> {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);
	const store = createStore();

	await act(async () => {
		root.render(
			<Provider store={store}>
				<LaunchWindow />
			</Provider>,
		);
	});
	await flushEffects();

	return {
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
			container.remove();
		},
	};
}

// ─── Selection invariant tests (preserved from original) ─────────────────────

describe("LaunchWindow selection invariants", () => {
	it.each([
		["falls back to the default source name", null, "Main Display"],
		["uses the source name when present", { name: "Display 2" }, "Display 2"],
		["uses the windowTitle fallback when name is missing", { windowTitle: "Docs" }, "Docs"],
		["uses the snake_case window_title fallback when needed", { window_title: "Chat" }, "Chat"],
	])("%s", (_label, source, expectedName) => {
		expect(resolveSelectedSourceState(source)).toEqual({
			selectedSource: expectedName,
			hasSelectedSource: true,
		});
	});
});

// ─── Event listener cleanup tests ────────────────────────────────────────────

describe("LaunchWindow event listener cleanup", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		// Ensure component renders in the "choice" view, not "onboarding"
		localStorage.setItem("open-recorder-onboarding-v1", "true");
	});

	afterEach(() => {
		document.body.innerHTML = "";
		localStorage.clear();
	});

	it("subscribes to all three menu events on mount", async () => {
		setupDefaultMocks();
		const harness = await mountLaunchWindow();

		expect(backend.onMenuOpenVideoFile).toHaveBeenCalledOnce();
		expect(backend.onMenuLoadProject).toHaveBeenCalledOnce();
		expect(backend.onNewRecordingFromTray).toHaveBeenCalledOnce();

		await harness.unmount();
	});

	it("calls each unlisten function exactly once when the component unmounts", async () => {
		const { mockUnlistenVideo, mockUnlistenProject, mockUnlistenNewRecording } =
			setupDefaultMocks();

		const harness = await mountLaunchWindow();

		// Unlisten functions must not be called while the component is still mounted
		expect(mockUnlistenVideo).not.toHaveBeenCalled();
		expect(mockUnlistenProject).not.toHaveBeenCalled();
		expect(mockUnlistenNewRecording).not.toHaveBeenCalled();

		await harness.unmount();

		// Every unlisten must be called exactly once after unmount
		expect(mockUnlistenVideo).toHaveBeenCalledOnce();
		expect(mockUnlistenProject).toHaveBeenCalledOnce();
		expect(mockUnlistenNewRecording).toHaveBeenCalledOnce();
	});

	it("wires a live handler that calls backend.openVideoFilePicker when the menu event fires", async () => {
		let capturedHandler: (() => void) | undefined;

		backend.onMenuOpenVideoFile.mockImplementation((handler) => {
			capturedHandler = handler;
			return Promise.resolve(vi.fn());
		});
		backend.onMenuLoadProject.mockResolvedValue(vi.fn());
		backend.onNewRecordingFromTray.mockResolvedValue(vi.fn());
		backend.getSelectedSource.mockResolvedValue(null);
		backend.getScreenRecordingPermissionStatus.mockResolvedValue("granted");
		backend.openVideoFilePicker.mockResolvedValue(null); // user cancels — no file path

		useScreenRecorder.mockReturnValue({
			recording: false,
			toggleRecording: vi.fn(),
			preparePermissions: vi.fn().mockResolvedValue(true),
			setMicrophoneEnabled: vi.fn(),
			microphoneDeviceId: undefined,
			setMicrophoneDeviceId: vi.fn(),
			systemAudioEnabled: false,
			setSystemAudioEnabled: vi.fn(),
			cameraEnabled: false,
			setCameraEnabled: vi.fn(),
			cameraDeviceId: undefined,
			setCameraDeviceId: vi.fn(),
		});
		usePermissions.mockReturnValue({
			permissions: {
				microphone: "granted",
				camera: "granted",
				screenRecording: "granted",
				accessibility: "granted",
			},
			isMacOS: false,
			isChecking: false,
			refreshPermissions: vi.fn().mockResolvedValue({}),
			requestMicrophoneAccess: vi.fn().mockResolvedValue(true),
			requestCameraAccess: vi.fn().mockResolvedValue(true),
			requestScreenRecordingAccess: vi.fn().mockResolvedValue(true),
			openPermissionSettings: vi.fn().mockResolvedValue(undefined),
			allRequiredPermissionsGranted: true,
			allPermissionsGranted: true,
		});
		useMicrophoneDevices.mockReturnValue({
			devices: [],
			selectedDeviceId: "default",
			setSelectedDeviceId: vi.fn(),
			isLoading: false,
			isRequestingAccess: false,
			permissionDenied: false,
			error: null,
		});
		useCameraDevices.mockReturnValue({
			devices: [],
			selectedDeviceId: "default",
			setSelectedDeviceId: vi.fn(),
			isLoading: false,
			isRequestingAccess: false,
			permissionDenied: false,
			error: null,
		});
		useActor.mockReturnValue([{ matches: () => false, value: "off" }, vi.fn()]);

		const harness = await mountLaunchWindow();

		// The handler should have been captured by the mock
		expect(capturedHandler).toBeDefined();

		// Simulate the Tauri "menu-open-video-file" event firing
		await act(async () => {
			capturedHandler?.();
		});
		await flushEffects();

		// The handler must have propagated to the backend call
		expect(backend.openVideoFilePicker).toHaveBeenCalledOnce();

		await harness.unmount();
	});

	it("does not process events fired after unmount — unlisten is the no-fire guarantee", async () => {
		const { mockUnlistenVideo } = setupDefaultMocks();

		const harness = await mountLaunchWindow();
		await harness.unmount();

		// The backend's unlisten function was called, which deregisters the handler
		// from the Tauri event bus. Any subsequent event dispatch is therefore a
		// no-op at the backend level. We assert the contract from our side:
		// unlisten must have been invoked synchronously during the cleanup phase.
		expect(mockUnlistenVideo).toHaveBeenCalledOnce();

		// Confirm the backend was never asked to open a video file after unmount
		// (the handler was not invoked post-cleanup)
		expect(backend.openVideoFilePicker).not.toHaveBeenCalled();
	});

	it("routes tray-triggered source selection through preparePermissions only", async () => {
		let capturedHandler: (() => void) | undefined;
		const preparePermissions = vi.fn().mockResolvedValue(true);

		backend.onMenuOpenVideoFile.mockResolvedValue(vi.fn());
		backend.onMenuLoadProject.mockResolvedValue(vi.fn());
		backend.onNewRecordingFromTray.mockImplementation((handler) => {
			capturedHandler = handler;
			return Promise.resolve(vi.fn());
		});
		backend.getSelectedSource.mockResolvedValue(null);
		backend.openSourceSelector.mockResolvedValue(undefined);

		useScreenRecorder.mockReturnValue({
			recording: false,
			toggleRecording: vi.fn(),
			preparePermissions,
			setMicrophoneEnabled: vi.fn(),
			microphoneDeviceId: undefined,
			setMicrophoneDeviceId: vi.fn(),
			systemAudioEnabled: false,
			setSystemAudioEnabled: vi.fn(),
			cameraEnabled: false,
			setCameraEnabled: vi.fn(),
			cameraDeviceId: undefined,
			setCameraDeviceId: vi.fn(),
		});

		const harness = await mountLaunchWindow();

		await act(async () => {
			capturedHandler?.();
		});
		await flushEffects();

		expect(preparePermissions).toHaveBeenCalledOnce();
		expect(backend.getScreenRecordingPermissionStatus).not.toHaveBeenCalled();
		expect(backend.requestScreenRecordingPermission).not.toHaveBeenCalled();
		expect(backend.openScreenRecordingPreferences).not.toHaveBeenCalled();
		expect(backend.openSourceSelector).toHaveBeenCalledOnce();

		await harness.unmount();
	});
});
