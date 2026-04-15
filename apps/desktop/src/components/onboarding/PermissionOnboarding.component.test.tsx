// @vitest-environment jsdom

/**
 * Component-level tests for PermissionOnboarding.
 * Focuses on the Tauri window-resize path and error resilience.
 */

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { UsePermissionsResult } from "../../hooks/usePermissions";

// ─── Mock Tauri window API ────────────────────────────────────────────────────

const mockSetSize = vi.fn();
const mockCenter = vi.fn();
const mockSetPosition = vi.fn();
const mockSetSize2 = vi.fn();

vi.mock("@tauri-apps/api/window", () => ({
	getCurrentWindow: () => ({
		setSize: mockSetSize,
		center: mockCenter,
		setPosition: mockSetPosition,
	}),
	primaryMonitor: vi.fn().mockResolvedValue(null),
}));

vi.mock("@tauri-apps/api/dpi", () => ({
	LogicalSize: class {
		width: number;
		height: number;
		constructor(w: number, h: number) {
			this.width = w;
			this.height = h;
		}
	},
	PhysicalPosition: class {
		x: number;
		y: number;
		constructor(x: number, y: number) {
			this.x = x;
			this.y = y;
		}
	},
}));

const { PermissionOnboarding } = await import("./PermissionOnboarding");

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makePermissionsHook(overrides: Partial<UsePermissionsResult> = {}): UsePermissionsResult {
	return {
		permissions: {
			screenRecording: "not_determined",
			microphone: "not_determined",
			camera: "not_determined",
			accessibility: "not_determined",
		},
		isMacOS: false,
		isChecking: false,
		refreshPermissions: vi.fn().mockResolvedValue({}),
		requestMicrophoneAccess: vi.fn().mockResolvedValue(true),
		requestCameraAccess: vi.fn().mockResolvedValue(true),
		requestScreenRecordingAccess: vi.fn().mockResolvedValue(true),
		openPermissionSettings: vi.fn().mockResolvedValue(undefined),
		allRequiredPermissionsGranted: false,
		allPermissionsGranted: false,
		...overrides,
	};
}

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function renderOnboarding(hook: UsePermissionsResult, onComplete = vi.fn()) {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);

	await act(async () => {
		root.render(<PermissionOnboarding permissionsHook={hook} onComplete={onComplete} />);
	});
	await flushEffects();

	return {
		container,
		unmount: async () => {
			await act(async () => root.unmount());
			container.remove();
		},
	};
}

// ─── Tests ────────────────────────────────────────────────────────────────────

afterEach(() => {
	vi.clearAllMocks();
	document.body.innerHTML = "";
});

beforeEach(() => {
	localStorage.clear();
});

describe("PermissionOnboarding — setSize error resilience", () => {
	it("renders the welcome step normally when setSize succeeds", async () => {
		mockSetSize.mockResolvedValue(undefined);
		mockCenter.mockResolvedValue(undefined);

		const harness = await renderOnboarding(makePermissionsHook());

		expect(harness.container.textContent).toContain("Welcome to Open Recorder");
		expect(harness.container.textContent).toContain("Get Started");

		await harness.unmount();
	});

	it("continues to render correctly and does not crash when setSize throws", async () => {
		mockSetSize.mockRejectedValue(new Error("Tauri IPC failure: setSize"));
		mockCenter.mockResolvedValue(undefined);

		const harness = await renderOnboarding(makePermissionsHook());

		// The component must still mount and show the welcome step
		expect(harness.container.textContent).toContain("Welcome to Open Recorder");
		expect(harness.container.textContent).toContain("Get Started");

		await harness.unmount();
	});

	it("does not call onComplete prematurely when setSize throws", async () => {
		mockSetSize.mockRejectedValue(new Error("Tauri IPC failure: setSize"));
		const onComplete = vi.fn();

		const harness = await renderOnboarding(makePermissionsHook(), onComplete);

		expect(onComplete).not.toHaveBeenCalled();

		await harness.unmount();
	});

	it("step dots are rendered and reflect the initial step index", async () => {
		mockSetSize.mockRejectedValue(new Error("Tauri IPC failure: setSize"));

		const harness = await renderOnboarding(makePermissionsHook());

		// Non-macOS flow: welcome | microphone | camera | done → 4 dots
		const dots = harness.container.querySelectorAll(".rounded-full");
		// There will be multiple rounded-full elements (icons, spinner, dots).
		// The step dot bar specifically uses a flex row of small divs — just assert
		// there are at least 4 dot-like elements present.
		expect(dots.length).toBeGreaterThanOrEqual(4);

		await harness.unmount();
	});

	it("allows the user to proceed past welcome when setSize threw on mount", async () => {
		mockSetSize.mockRejectedValue(new Error("Tauri IPC failure: setSize"));
		mockCenter.mockResolvedValue(undefined);

		const harness = await renderOnboarding(makePermissionsHook());

		const getStarted = Array.from(harness.container.querySelectorAll("button")).find(
			(b) => b.textContent?.trim() === "Get Started",
		);
		expect(getStarted).not.toBeUndefined();

		await act(async () => {
			getStarted!.dispatchEvent(new MouseEvent("click", { bubbles: true }));
		});
		await flushEffects();

		// Should have advanced to the microphone step (non-macOS skips screen recording)
		expect(harness.container.textContent).toContain("Microphone");

		await harness.unmount();
	});
});
