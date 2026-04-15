// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { launchViewAtom } from "@/atoms/launch";

// ─── Mock heavy dependencies ──────────────────────────────────────────────────

vi.mock("@/lib/backend", () => ({
	getSelectedSource: vi.fn().mockResolvedValue(null),
	getScreenRecordingPermissionStatus: vi.fn().mockResolvedValue("granted"),
	onMenuOpenVideoFile: vi.fn().mockResolvedValue(() => {}),
	onMenuLoadProject: vi.fn().mockResolvedValue(() => {}),
	onNewRecordingFromTray: vi.fn().mockResolvedValue(() => {}),
	openSourceSelector: vi.fn().mockResolvedValue(undefined),
	hudOverlayHide: vi.fn().mockResolvedValue(undefined),
	hudOverlayShow: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("../../hooks/useScreenRecorder", () => ({
	useScreenRecorder: () => ({
		recording: false,
		toggleRecording: vi.fn(),
		preparePermissions: vi.fn().mockResolvedValue(true),
		setMicrophoneEnabled: vi.fn(),
		microphoneDeviceId: undefined,
		setMicrophoneDeviceId: vi.fn(),
		systemAudioEnabled: false,
		setSystemAudioEnabled: vi.fn(),
		cameraEnabled: true,
		setCameraEnabled: vi.fn(),
		cameraDeviceId: undefined,
		setCameraDeviceId: vi.fn(),
	}),
}));

vi.mock("../../hooks/usePermissions", () => ({
	usePermissions: () => ({
		permissions: {
			microphone: "granted",
			camera: "granted",
			screen: "granted",
			accessibility: "granted",
		},
		isMacOS: false,
		openPermissionSettings: vi.fn(),
		requestMicrophoneAccess: vi.fn(),
	}),
}));

vi.mock("../../hooks/useCameraDevices", () => ({
	useCameraDevices: () => ({
		devices: [],
		selectedDeviceId: "default",
		setSelectedDeviceId: vi.fn(),
		isLoading: false,
		isRequestingAccess: false,
		permissionDenied: false,
		error: null,
	}),
}));

vi.mock("../../hooks/useMicrophoneDevices", () => ({
	useMicrophoneDevices: () => ({
		devices: [],
		selectedDeviceId: "default",
		setSelectedDeviceId: vi.fn(),
		isLoading: false,
		isRequestingAccess: false,
		permissionDenied: false,
		error: null,
	}),
}));

vi.mock("../../machines/microphoneMachine", () => ({
	microphoneMachine: {
		provide: vi.fn().mockReturnValue({ id: "mock-mic-machine" }),
	},
}));

vi.mock("@xstate/react", () => ({
	useActor: vi.fn().mockReturnValue([{ matches: () => false }, vi.fn()]),
}));

const { LaunchWindow } = await import("./LaunchWindow");

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

function setupMediaDevicesMock() {
	const stop = vi.fn();
	const getTracks = vi.fn().mockReturnValue([{ stop }]);
	const stream = { getTracks } as unknown as MediaStream;

	Object.defineProperty(navigator, "mediaDevices", {
		configurable: true,
		value: {
			getUserMedia: vi.fn().mockResolvedValue(stream),
			enumerateDevices: vi.fn().mockResolvedValue([]),
		},
	});

	return { stop, getTracks, stream };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("LaunchWindow camera preview stream cleanup", () => {
	let container: HTMLDivElement;
	let root: Root;

	beforeEach(() => {
		// Prevent the onboarding redirect so view stays as we set it
		localStorage.setItem("open-recorder-onboarding-v1", "true");

		// jsdom doesn't implement HTMLVideoElement.play()
		HTMLVideoElement.prototype.play = vi.fn().mockResolvedValue(undefined);

		container = document.createElement("div");
		document.body.appendChild(container);
		root = createRoot(container);
	});

	afterEach(() => {
		localStorage.removeItem("open-recorder-onboarding-v1");
		vi.clearAllMocks();
		container.remove();
	});

	it("stops all stream tracks when the component unmounts", async () => {
		const { stop, getTracks } = setupMediaDevicesMock();

		// Set the view to "recording" so showCameraPreview = cameraEnabled && !recording && view === "recording"
		const store = createStore();
		store.set(launchViewAtom, "recording");

		await act(async () => {
			root.render(
				<Provider store={store}>
					<LaunchWindow />
				</Provider>,
			);
		});

		// Flush effects: lets the async getUserMedia promise resolve and the
		// stream get attached to the video element
		await flushEffects();

		// Confirm getUserMedia was called (stream was acquired)
		expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledOnce();

		// Unmount to trigger the effect cleanup
		await act(async () => {
			root.unmount();
		});

		// The cleanup must stop every track in the stream
		expect(getTracks).toHaveBeenCalled();
		expect(stop).toHaveBeenCalled();
	});

	it("stops all stream tracks when the camera is toggled off", async () => {
		const { stop, getTracks } = setupMediaDevicesMock();

		const store = createStore();
		store.set(launchViewAtom, "recording");

		await act(async () => {
			root.render(
				<Provider store={store}>
					<LaunchWindow />
				</Provider>,
			);
		});

		await flushEffects();

		expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledOnce();

		// Switch view away from "recording" — showCameraPreview becomes false,
		// which re-runs the effect and fires the previous cleanup
		await act(async () => {
			store.set(launchViewAtom, "choice");
		});

		await flushEffects();

		expect(getTracks).toHaveBeenCalled();
		expect(stop).toHaveBeenCalled();

		// Clean up root
		await act(async () => {
			root.unmount();
		});
	});

	it("logs a warning when play() rejects", async () => {
		setupMediaDevicesMock();
		const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
		const playError = new DOMException("play interrupted", "AbortError");
		HTMLVideoElement.prototype.play = vi.fn().mockRejectedValue(playError);

		const store = createStore();
		store.set(launchViewAtom, "recording");

		await act(async () => {
			root.render(
				<Provider store={store}>
					<LaunchWindow />
				</Provider>,
			);
		});

		await flushEffects();

		expect(warnSpy).toHaveBeenCalledWith("Camera preview play() failed:", playError);

		await act(async () => {
			root.unmount();
		});
		warnSpy.mockRestore();
	});
});
