import { describe, expect, it } from "vitest";
import { resolveMediaPlaybackUrl } from "./mediaPlaybackUrl";

// `resolveMediaPlaybackUrl` is the boundary every <video>/<img> src crosses.
// Its job: never let a `file://` URL reach the DOM, because Chromium blocks
// `file://` media when the renderer is served from `http://localhost:5789` in
// dev. These tests pin that contract.

describe("resolveMediaPlaybackUrl — pass-through for already-renderable URLs", () => {
	it.each([
		["blob:https://example/abc-123", "blob:https://example/abc-123"],
		["data:image/png;base64,iVBOR", "data:image/png;base64,iVBOR"],
		["asset://localhost/Users/foo/bar.webm", "asset://localhost/Users/foo/bar.webm"],
		["https://cdn.example.com/clip.mp4", "https://cdn.example.com/clip.mp4"],
		["http://asset.localhost/Users/foo", "http://asset.localhost/Users/foo"],
	])("passes %s through unchanged", (input, expected) => {
		expect(resolveMediaPlaybackUrl(input)).toBe(expected);
	});
});

describe("resolveMediaPlaybackUrl — file:// must be rewritten, not passed through", () => {
	// REGRESSION: the pass-through allow list intentionally excludes `file:`.
	// If you re-add it, dev playback will silently break ("Failed to load video").
	it("does NOT pass file:// URLs through unchanged", () => {
		const input = "file:///Users/foo/bar.webm";
		expect(resolveMediaPlaybackUrl(input)).not.toBe(input);
	});

	it("rewrites a file:// URL to an asset:// URL", () => {
		expect(resolveMediaPlaybackUrl("file:///Users/foo/bar.webm")).toBe(
			"asset://localhost/Users/foo/bar.webm",
		);
	});

	it("preserves percent-encoded segments when rewriting", () => {
		expect(resolveMediaPlaybackUrl("file:///Users/foo%20bar/clip.webm")).toBe(
			"asset://localhost/Users/foo%20bar/clip.webm",
		);
	});

	it("rewrites a Windows file:// URL", () => {
		expect(resolveMediaPlaybackUrl("file:///C:/Users/foo/bar.webm")).toBe(
			"asset://localhost/C:/Users/foo/bar.webm",
		);
	});
});

describe("resolveMediaPlaybackUrl — native paths", () => {
	it("converts a POSIX path to an asset URL", () => {
		expect(resolveMediaPlaybackUrl("/Users/foo/bar.webm")).toBe(
			"asset://localhost/Users/foo/bar.webm",
		);
	});

	it("preserves spaces via percent-encoding", () => {
		expect(resolveMediaPlaybackUrl("/Users/bhargav/Videos/demo clip.mov")).toBe(
			"asset://localhost/Users/bhargav/Videos/demo%20clip.mov",
		);
	});

	it("converts a Windows path to an asset URL", () => {
		expect(resolveMediaPlaybackUrl("C:\\Users\\foo\\bar.webm")).toBe(
			"asset://localhost/C:/Users/foo/bar.webm",
		);
	});

	it("trims surrounding whitespace before conversion", () => {
		expect(resolveMediaPlaybackUrl("  /Users/foo/bar.webm  ")).toBe(
			"asset://localhost/Users/foo/bar.webm",
		);
	});

	it("rejects an empty string", () => {
		expect(() => resolveMediaPlaybackUrl("")).toThrow(/Path is required/);
		expect(() => resolveMediaPlaybackUrl("   ")).toThrow(/Path is required/);
	});
});
