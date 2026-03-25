// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/assetPath", () => ({
	getAssetPath: vi.fn(async (value: string) => value),
}));

vi.mock("@/lib/backend", () => ({
	openExternalUrl: vi.fn(),
}));

vi.mock("@uiw/react-color-block", () => ({
	default: () => <div data-testid="color-block" />,
}));

const { SettingsPanel } = await import("./SettingsPanel");

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

async function flushEffects() {
	await act(async () => {
		await Promise.resolve();
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
}

async function click(element: Element | null) {
	if (!element) {
		throw new Error("Expected element to exist");
	}

	await act(async () => {
		element.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, button: 0 }));
		element.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, button: 0 }));
		element.dispatchEvent(new MouseEvent("click", { bubbles: true }));
	});
	await flushEffects();
}

async function renderPanel() {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);

	await act(async () => {
		root.render(
			<SettingsPanel selected="#000000" onWallpaperChange={vi.fn()} aspectRatio="16:9" />,
		);
	});
	await flushEffects();

	return {
		container,
		unmount: async () => {
			await act(async () => {
				root.unmount();
			});
			container.remove();
		},
	};
}

afterEach(() => {
	vi.clearAllMocks();
	document.body.innerHTML = "";
});

beforeEach(() => {
	class ResizeObserverMock {
		observe = vi.fn();
		unobserve = vi.fn();
		disconnect = vi.fn();
	}

	Object.defineProperty(globalThis, "ResizeObserver", {
		configurable: true,
		value: ResizeObserverMock,
	});
});

describe("SettingsPanel", () => {
	it("shows only the selected sidebar tab content", async () => {
		const harness = await renderPanel();

		expect(harness.container.textContent).toContain("Shadow");
		expect(harness.container.textContent).not.toContain("Master Volume");

		await click(harness.container.querySelector('[aria-label="Audio"]'));

		expect(harness.container.textContent).toContain("Master Volume");
		expect(harness.container.textContent).not.toContain("Shadow");

		await harness.unmount();
	});

	it("switches background sub-tabs inside the selected background panel", async () => {
		const harness = await renderPanel();

		await click(harness.container.querySelector('[aria-label="Background"]'));

		expect(harness.container.textContent).toContain("Upload Custom");

		const gradientTrigger = Array.from(harness.container.querySelectorAll("button")).find(
			(button) => button.textContent?.trim() === "Gradient",
		);
		await click(gradientTrigger ?? null);

		expect(harness.container.querySelector('[aria-label="Gradient 1"]')).not.toBeNull();
		expect(harness.container.textContent).not.toContain("Upload Custom");

		await harness.unmount();
	});
});
