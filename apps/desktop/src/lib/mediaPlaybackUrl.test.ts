import { describe, expect, it } from "vitest";
import { resolveMediaPlaybackUrl } from "./mediaPlaybackUrl";

describe("resolveMediaPlaybackUrl", () => {
	it("returns already-renderable URLs unchanged", () => {
		expect(resolveMediaPlaybackUrl("blob:https://example.com/video-id")).toBe(
			"blob:https://example.com/video-id",
		);
		expect(resolveMediaPlaybackUrl("data:video/mp4;base64,abc")).toBe(
			"data:video/mp4;base64,abc",
		);
		expect(resolveMediaPlaybackUrl("asset://localhost/%2FUsers%2Fbhargav%2Fdemo.mov")).toBe(
			"asset://localhost/%2FUsers%2Fbhargav%2Fdemo.mov",
		);
		expect(resolveMediaPlaybackUrl("https://example.com/video.mp4")).toBe(
			"https://example.com/video.mp4",
		);
		expect(resolveMediaPlaybackUrl("https://asset.localhost/video.mp4")).toBe(
			"https://asset.localhost/video.mp4",
		);
	});

	it("passes file:// URLs through unchanged", () => {
		expect(resolveMediaPlaybackUrl("file:///Users/bhargav/Videos/demo%20clip.mov")).toBe(
			"file:///Users/bhargav/Videos/demo%20clip.mov",
		);
	});

	it("converts an absolute POSIX path to a file:// URL", () => {
		expect(resolveMediaPlaybackUrl("/Users/bhargav/Videos/demo clip.mov")).toBe(
			"file:///Users/bhargav/Videos/demo%20clip.mov",
		);
	});

	it("converts a Windows-style path to a file:// URL", () => {
		expect(resolveMediaPlaybackUrl("C:\\Users\\bhargav\\Videos\\demo clip.mov")).toBe(
			"file:///C:/Users/bhargav/Videos/demo%20clip.mov",
		);
	});

	it("throws when given an empty string", () => {
		expect(() => resolveMediaPlaybackUrl("")).toThrow("Path is required");
		expect(() => resolveMediaPlaybackUrl("   ")).toThrow("Path is required");
	});
});
