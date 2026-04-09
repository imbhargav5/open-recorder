import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/backend", () => ({
	convertFileToSrc: vi.fn((path: string) => `asset://localhost/${encodeURIComponent(path)}`),
}));

const { getRenderableAssetUrl, isRenderableAssetUrl } = await import("./assetPath");

describe("assetPath", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it("treats Tauri asset URLs as renderable image URLs", () => {
		expect(isRenderableAssetUrl("asset://localhost/%2FUsers%2Fdemo%2Fwallpaper.jpg")).toBe(true);
		expect(isRenderableAssetUrl("https://asset.localhost/%2FUsers%2Fdemo%2Fwallpaper.jpg")).toBe(
			true,
		);
	});

	it("converts file URLs into Tauri asset URLs before rendering", async () => {
		await expect(getRenderableAssetUrl("file:///Users/demo/Pictures/wallpaper.jpg")).resolves.toBe(
			"asset://localhost/%2FUsers%2Fdemo%2FPictures%2Fwallpaper.jpg",
		);
	});

	it("preserves existing Tauri asset URLs", async () => {
		const assetUrl = "asset://localhost/%2FUsers%2Fdemo%2FPictures%2Fwallpaper.jpg";
		await expect(getRenderableAssetUrl(assetUrl)).resolves.toBe(assetUrl);
	});
});
