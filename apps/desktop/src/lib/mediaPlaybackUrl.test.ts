import { clearMocks, mockConvertFileSrc } from "@tauri-apps/api/mocks";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { resolveMediaPlaybackUrl } from "./mediaPlaybackUrl";

describe("resolveMediaPlaybackUrl", () => {
	beforeEach(() => {
		Object.defineProperty(globalThis, "window", {
			value: {},
			writable: true,
			configurable: true,
		});
	});

	afterEach(() => {
		clearMocks();
		delete (globalThis as typeof globalThis & { window?: Window }).window;
	});

	it("uses Tauri's macOS asset URL conversion for local file paths", () => {
		mockConvertFileSrc("macos");

		expect(resolveMediaPlaybackUrl("/Users/bhargav/Videos/demo clip.mov")).toBe(
			"asset://localhost/%2FUsers%2Fbhargav%2FVideos%2Fdemo%20clip.mov",
		);
	});

	it("uses Tauri's Windows asset URL conversion for local file paths", () => {
		mockConvertFileSrc("windows");

		expect(resolveMediaPlaybackUrl("C:\\Users\\bhargav\\Videos\\demo clip.mov")).toBe(
			"http://asset.localhost/C%3A%5CUsers%5Cbhargav%5CVideos%5Cdemo%20clip.mov",
		);
	});

	it("normalizes saved file URLs before converting them", () => {
		mockConvertFileSrc("macos");

		expect(resolveMediaPlaybackUrl("file:///Users/bhargav/Videos/demo%20clip.mov")).toBe(
			"asset://localhost/%2FUsers%2Fbhargav%2FVideos%2Fdemo%20clip.mov",
		);
	});

	it("returns already renderable media URLs unchanged", () => {
		expect(resolveMediaPlaybackUrl("asset://localhost/%2FUsers%2Fbhargav%2Fdemo.mov")).toBe(
			"asset://localhost/%2FUsers%2Fbhargav%2Fdemo.mov",
		);
		expect(resolveMediaPlaybackUrl("https://asset.localhost/%2FUsers%2Fbhargav%2Fdemo.mov")).toBe(
			"https://asset.localhost/%2FUsers%2Fbhargav%2Fdemo.mov",
		);
		expect(resolveMediaPlaybackUrl("blob:https://example.com/video-id")).toBe(
			"blob:https://example.com/video-id",
		);
	});

	it("falls back to a file URL when the Tauri runtime is unavailable", () => {
		expect(resolveMediaPlaybackUrl("/Users/bhargav/Videos/demo clip.mov")).toBe(
			"file:///Users/bhargav/Videos/demo%20clip.mov",
		);
	});
});
