// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Slider } from "./slider";

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

function pointerEvent(type: string, clientX: number) {
	return new PointerEvent(type, {
		bubbles: true,
		button: 0,
		clientX,
		pointerId: 1,
	});
}

async function renderSlider(
	props: Partial<React.ComponentProps<typeof Slider>> = {},
): Promise<{ container: HTMLDivElement; root: Root; onValueChange: ReturnType<typeof vi.fn> }> {
	const container = document.createElement("div");
	document.body.appendChild(container);
	const root = createRoot(container);
	const onValueChange = vi.fn();

	await act(async () => {
		root.render(
			<Slider value={[50]} min={0} max={100} step={1} onValueChange={onValueChange} {...props} />,
		);
	});

	return { container, root, onValueChange };
}

beforeEach(() => {
	class PointerEventMock extends MouseEvent {
		pointerId: number;

		constructor(type: string, init: PointerEventInit = {}) {
			super(type, init);
			this.pointerId = init.pointerId ?? 1;
		}
	}

	vi.stubGlobal("PointerEvent", PointerEventMock);
	Object.defineProperty(HTMLElement.prototype, "setPointerCapture", {
		configurable: true,
		value: vi.fn(),
	});
	Object.defineProperty(HTMLElement.prototype, "releasePointerCapture", {
		configurable: true,
		value: vi.fn(),
	});
});

afterEach(() => {
	document.body.innerHTML = "";
	vi.unstubAllGlobals();
	vi.restoreAllMocks();
});

describe("Slider", () => {
	it("does not snap the value when a pointer drag starts", async () => {
		const { container, root, onValueChange } = await renderSlider();
		const slider = container.querySelector('[role="slider"]') as HTMLDivElement;
		vi.spyOn(slider, "getBoundingClientRect").mockReturnValue({
			left: 0,
			right: 200,
			top: 0,
			bottom: 24,
			width: 200,
			height: 24,
			x: 0,
			y: 0,
			toJSON: () => ({}),
		});

		await act(async () => {
			slider.dispatchEvent(pointerEvent("pointerdown", 10));
		});
		expect(onValueChange).not.toHaveBeenCalled();

		await act(async () => {
			slider.dispatchEvent(pointerEvent("pointermove", 30));
		});
		expect(onValueChange).toHaveBeenLastCalledWith([60]);

		await act(async () => {
			slider.dispatchEvent(pointerEvent("pointerup", 30));
		});

		await act(async () => {
			root.unmount();
		});
	});

	it("supports keyboard changes and commits the current value", async () => {
		const onValueCommit = vi.fn();
		const { container, root, onValueChange } = await renderSlider({ onValueCommit, step: 5 });
		const slider = container.querySelector('[role="slider"]') as HTMLDivElement;

		await act(async () => {
			slider.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: "ArrowRight" }));
		});

		expect(onValueChange).toHaveBeenLastCalledWith([55]);
		expect(onValueCommit).toHaveBeenLastCalledWith([55]);

		await act(async () => {
			root.unmount();
		});
	});
});
