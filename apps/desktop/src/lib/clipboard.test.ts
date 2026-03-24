import { Image } from "@tauri-apps/api/image";
import { writeImage } from "@tauri-apps/plugin-clipboard-manager";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { copyCanvasImageToClipboard } from "./clipboard";

vi.mock("@tauri-apps/api/image", () => ({
	Image: {
		new: vi.fn(),
	},
}));

vi.mock("@tauri-apps/plugin-clipboard-manager", () => ({
	writeImage: vi.fn(),
}));

describe("copyCanvasImageToClipboard", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it("writes the rendered RGBA image through the Tauri clipboard plugin", async () => {
		const pixels = new Uint8ClampedArray([255, 0, 0, 255, 0, 255, 0, 255]);
		const getImageData = vi.fn().mockReturnValue({ data: pixels });
		const canvas = {
			width: 2,
			height: 1,
			getContext: vi.fn().mockReturnValue({ getImageData }),
		} as unknown as HTMLCanvasElement;
		const close = vi.fn().mockResolvedValue(undefined);
		const image = { close };

		vi.mocked(Image.new).mockResolvedValue(image as never);
		vi.mocked(writeImage).mockResolvedValue(undefined);

		await copyCanvasImageToClipboard(canvas);

		expect(getImageData).toHaveBeenCalledWith(0, 0, 2, 1);
		expect(Image.new).toHaveBeenCalledWith(pixels, 2, 1);
		expect(writeImage).toHaveBeenCalledWith(image);
		expect(close).toHaveBeenCalledTimes(1);
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
		expect(Image.new).not.toHaveBeenCalled();
		expect(writeImage).not.toHaveBeenCalled();
	});
});
