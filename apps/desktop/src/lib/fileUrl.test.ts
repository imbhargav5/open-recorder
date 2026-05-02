import { describe, expect, it } from "vitest";
import { fromFileUrl, toAssetUrl, toFileUrl } from "./fileUrl";

describe("toFileUrl", () => {
	it("encodes a simple POSIX path", () => {
		expect(toFileUrl("/Users/foo/bar.webm")).toBe("file:///Users/foo/bar.webm");
	});

	it("percent-encodes spaces and unicode in segments", () => {
		expect(toFileUrl("/Users/foo bar/café.mp4")).toBe(
			"file:///Users/foo%20bar/caf%C3%A9.mp4",
		);
	});

	it("preserves a Windows drive letter", () => {
		expect(toFileUrl("C:/Users/foo/bar.webm")).toBe("file:///C:/Users/foo/bar.webm");
	});

	it("normalizes Windows backslashes", () => {
		expect(toFileUrl("C:\\Users\\foo\\bar.webm")).toBe("file:///C:/Users/foo/bar.webm");
	});

	it("preserves UNC host", () => {
		expect(toFileUrl("//server/share/file.webm")).toBe(
			"file://server/share/file.webm",
		);
	});
});

describe("fromFileUrl", () => {
	it("round-trips a POSIX path", () => {
		expect(fromFileUrl("file:///Users/foo/bar.webm")).toBe("/Users/foo/bar.webm");
	});

	it("decodes percent-encoded segments", () => {
		expect(fromFileUrl("file:///Users/foo%20bar/caf%C3%A9.mp4")).toBe(
			"/Users/foo bar/café.mp4",
		);
	});

	it("strips the leading slash before a Windows drive", () => {
		expect(fromFileUrl("file:///C:/Users/foo/bar.webm")).toBe("C:/Users/foo/bar.webm");
	});

	it("returns input unchanged for non-file URLs", () => {
		expect(fromFileUrl("asset://localhost/Users/foo")).toBe("asset://localhost/Users/foo");
	});
});

// ─── toAssetUrl ─────────────────────────────────────────────────────────────
//
// These cases are the renderer half of the asset-protocol contract.
// The main process counterpart lives in `electron/asset-protocol.test.ts` —
// changes here without matching changes there will break media playback.

describe("toAssetUrl", () => {
	it("emits an asset URL for a POSIX path", () => {
		expect(toAssetUrl("/Users/foo/bar.webm")).toBe(
			"asset://localhost/Users/foo/bar.webm",
		);
	});

	it("always uses 'localhost' as the host so the privileged scheme parses correctly", () => {
		// Custom protocols registered as `standard` require a host. Anything
		// other than 'localhost' would split the path between hostname and
		// pathname on the main side and break path resolution.
		const url = new URL(toAssetUrl("/Users/foo/bar.webm"));
		expect(url.protocol).toBe("asset:");
		expect(url.hostname).toBe("localhost");
	});

	it("percent-encodes spaces and unicode just like file URLs", () => {
		expect(toAssetUrl("/Users/foo bar/café.mp4")).toBe(
			"asset://localhost/Users/foo%20bar/caf%C3%A9.mp4",
		);
	});

	it("preserves a Windows drive letter as a path segment", () => {
		expect(toAssetUrl("C:/Users/foo/bar.webm")).toBe(
			"asset://localhost/C:/Users/foo/bar.webm",
		);
	});

	it("normalizes Windows backslashes", () => {
		expect(toAssetUrl("C:\\Users\\foo\\bar.webm")).toBe(
			"asset://localhost/C:/Users/foo/bar.webm",
		);
	});

	it("collapses UNC host into the path so the asset host stays 'localhost'", () => {
		expect(toAssetUrl("//server/share/file.webm")).toBe(
			"asset://localhost/server/share/file.webm",
		);
	});

	it("never emits a file:// URL — playback would break in dev (renderer is http://)", () => {
		const inputs = [
			"/Users/foo/bar.webm",
			"C:/Users/foo/bar.webm",
			"//server/share/file.webm",
		];
		for (const input of inputs) {
			expect(toAssetUrl(input)).not.toMatch(/^file:/);
			expect(toAssetUrl(input)).toMatch(/^asset:\/\/localhost\//);
		}
	});
});
