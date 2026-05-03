// @vitest-environment jsdom

import { Provider } from "jotai";
import { createStore } from "jotai/vanilla";
import { act, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/backend", () => ({
	openExternalUrl: vi.fn(),
}));

vi.mock("@uiw/react-color-block", () => ({
	default: () => <div data-testid="color-block" />,
}));

const { TooltipProvider } = await import("@/components/ui/tooltip");
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

async function renderPanel(props: Partial<ComponentProps<typeof SettingsPanel>> = {}) {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root: Root = createRoot(container);
	const store = createStore();

	await act(async () => {
		root.render(
			<Provider store={store}>
				<TooltipProvider>
					<SettingsPanel
						selected="#000000"
						onWallpaperChange={vi.fn()}
						aspectRatio="16:9"
						{...props}
					/>
				</TooltipProvider>
			</Provider>,
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

	it("shows background controls inside the appearance panel", async () => {
		const harness = await renderPanel();

		expect(harness.container.querySelector('[aria-label="Background"]')).toBeNull();
		expect(harness.container.textContent).toContain("Background");
		expect(harness.container.textContent).toContain("Upload Custom");
		expect(harness.container.querySelector('img[alt="Wallpaper 1"]')?.getAttribute("src")).toBe(
			"/wallpapers/thumbs/wallpaper1.jpg",
		);

		const gradientTrigger = Array.from(harness.container.querySelectorAll("button")).find(
			(button) => button.textContent?.trim() === "Gradient",
		);
		await click(gradientTrigger ?? null);

		expect(harness.container.querySelector('[aria-label="Gradient 1"]')).not.toBeNull();
		expect(harness.container.textContent).not.toContain("Upload Custom");

		await harness.unmount();
	});

	it("shows a focused zoom editor without the main editor controls", async () => {
		const onZoomEaseChange = vi.fn();
		const harness = await renderPanel({
			selectedZoomId: "zoom-1",
			selectedZoomDepth: 2,
			selectedZoomEaseIn: { durationMs: 1200, type: "linear" },
			selectedZoomEaseOut: { durationMs: 800, type: "smooth" },
			onZoomDepthChange: vi.fn(),
			onZoomEaseChange,
			onZoomDelete: vi.fn(),
		});

		expect(harness.container.textContent).toContain("Zoom Settings");
		expect(harness.container.textContent).toContain("Ease In");
		expect(harness.container.textContent).toContain("Ease Out");
		expect(harness.container.textContent).toContain("Linear");
		expect(harness.container.textContent).toContain("Smooth");
		expect(harness.container.textContent).toContain("Delete Zoom");
		expect(harness.container.textContent).not.toContain("Shadow");
		expect(harness.container.textContent).not.toContain("Report Bug");
		expect(harness.container.querySelector('[aria-label="Appearance"]')).toBeNull();

		const easeInDurationInput = harness.container.querySelector(
			'input[aria-label="Ease In duration"]',
		) as HTMLInputElement | null;
		expect(easeInDurationInput?.value).toBe("1.2");

		await act(async () => {
			if (!easeInDurationInput) throw new Error("Expected ease-in duration input");
			const valueSetter = Object.getOwnPropertyDescriptor(
				window.HTMLInputElement.prototype,
				"value",
			)?.set;
			valueSetter?.call(easeInDurationInput, "0.75");
			easeInDurationInput.dispatchEvent(new Event("input", { bubbles: true }));
			easeInDurationInput.dispatchEvent(new Event("change", { bubbles: true }));
		});
		await flushEffects();

		expect(onZoomEaseChange).toHaveBeenCalledWith("easeIn", { durationMs: 750 });

		await harness.unmount();
	});

	it("shows a focused trim editor without the main editor controls", async () => {
		const harness = await renderPanel({
			selectedTrimId: "trim-1",
			onTrimDelete: vi.fn(),
		});

		expect(harness.container.textContent).toContain("Trim Settings");
		expect(harness.container.textContent).toContain("Delete Trim Region");
		expect(harness.container.textContent).not.toContain("Shadow");
		expect(harness.container.textContent).not.toContain("Report Bug");
		expect(harness.container.querySelector('[aria-label="Appearance"]')).toBeNull();

		await harness.unmount();
	});

	it("shows a focused speed editor without the main editor controls", async () => {
		const harness = await renderPanel({
			selectedSpeedId: "speed-1",
			selectedSpeedValue: 1.5,
			onSpeedChange: vi.fn(),
			onSpeedDelete: vi.fn(),
		});

		expect(harness.container.textContent).toContain("Speed Settings");
		expect(harness.container.textContent).toContain("Delete Speed Region");
		expect(harness.container.textContent).toContain("1.5×");
		expect(harness.container.textContent).not.toContain("Shadow");
		expect(harness.container.textContent).not.toContain("Report Bug");
		expect(harness.container.querySelector('[aria-label="Appearance"]')).toBeNull();

		await harness.unmount();
	});
});
