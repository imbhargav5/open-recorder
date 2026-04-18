// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { copyCanvasImageToClipboard } from "./clipboard";

vi.mock("@/lib/electronBridge", () => ({
	invoke: vi.fn().mockResolvedValue(undefined),
}));

const { invoke } = vi.mocked(await import("@/lib/electronBridge"));

function makeCanvas(pixels: Uint8ClampedArray, width: number, height: number) {
	let blobCallback: ((blob: Blob | null) => void) | null = null;
	const canvas = {
		width,
		height,
		getContext: vi.fn().mockReturnValue({
			getImageData: vi.fn().mockReturnValue({ data: pixels }),
		}),
		toBlob: vi.fn().mockImplementation((cb: (blob: Blob | null) => void) => {
			blobCallback = cb;
		}),
	} as unknown as HTMLCanvasElement & { _triggerBlob: (b: Blob | null) => void };
	(canvas as unknown as { _triggerBlob: (b: Blob | null) => void })._triggerBlob = (b) => blobCallback?.(b);
	return canvas;
}

describe("copyCanvasImageToClipboard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it("uses navigator.clipboard.write when ClipboardItem is available", async () => {
		const pixels = new Uint8ClampedArray([255, 0, 0, 255]);
		const canvas = makeCanvas(pixels, 1, 1);
		const fakeBlob = new Blob([""], { type: "image/png" });

		const writeStub = vi.fn().mockResolvedValue(undefined);
		const ClipboardItemStub = vi.fn().mockImplementation(() => ({}));

		Object.defineProperty(globalThis, "ClipboardItem", {
			value: ClipboardItemStub,
			writable: true,
			configurable: true,
		});
		Object.defineProperty(navigator, "clipboard", {
			value: { write: writeStub },
			writable: true,
			configurable: true,
		});

		// Trigger toBlob callback asynchronously after copyCanvasImageToClipboard is called
		const promise = copyCanvasImageToClipboard(canvas);
		(canvas as unknown as { _triggerBlob: (b: Blob | null) => void })._triggerBlob(fakeBlob);
		await promise;

		expect(writeStub).toHaveBeenCalledOnce();
		expect(invoke).not.toHaveBeenCalled();
	});

	it("falls back to IPC invoke when ClipboardItem is not available", async () => {
		const pixels = new Uint8ClampedArray([255, 0, 0, 255, 0, 255, 0, 255]);
		const canvas = makeCanvas(pixels, 2, 1);

		// Remove ClipboardItem to trigger fallback path
		Object.defineProperty(globalThis, "ClipboardItem", {
			value: undefined,
			writable: true,
			configurable: true,
		});

		await copyCanvasImageToClipboard(canvas);

		expect(invoke).toHaveBeenCalledWith("write_clipboard_image", {
			data: Array.from(pixels),
			width: 2,
			height: 1,
		});
	});

	it("throws when the canvas has no 2D context", async () => {
		const canvas = {
			width: 1,
			height: 1,
			getContext: vi.fn().mockReturnValue(null),
		} as unknown as HTMLCanvasElement;

		await expect(copyCanvasImageToClipboard(canvas)).rejects.toThrow(
			"Failed to read rendered image",
		);
		expect(invoke).not.toHaveBeenCalled();
	});
});
