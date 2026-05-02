import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

vi.mock("electron", () => ({}));

import {
	ASSET_SCHEME,
	ASSET_SCHEME_PRIVILEGES,
	assetUrlToFilePath,
	handleAssetRequest,
	registerAssetProtocolHandler,
	registerAssetSchemeAsPrivileged,
} from "./asset-protocol";

// ─── Privileged-scheme contract ──────────────────────────────────────────────
//
// REGRESSION GUARDS. Removing any of these flags silently breaks media playback
// in subtle, hard-to-reproduce ways:
//   - `standard`        → URL parser splits hostname/pathname properly; without
//                         it, asset://localhost/Users/x parses inconsistently.
//   - `secure`          → `<video>` and Service Workers will not load resources
//                         from a non-secure custom scheme when the renderer is
//                         http(s)-origin in dev.
//   - `supportFetchAPI` → `fetch("asset://...")` requires this.
//   - `stream`          → `<video>` MSE-style streaming requires this.
//   - `bypassCSP`       → Skip CSP enforcement so the renderer's CSP can't block
//                         playback; renderer-origin CSP doesn't apply to
//                         privileged custom schemes.
//   - `corsEnabled`     → Allow cross-origin XHR/fetch from the http(s) dev
//                         renderer.
// All six are required — do not weaken them without a documented replacement
// strategy and matching renderer-side changes.

describe("ASSET_SCHEME_PRIVILEGES — required for media playback", () => {
	it("uses the 'asset' scheme name", () => {
		expect(ASSET_SCHEME).toBe("asset");
	});

	it.each([
		["standard"],
		["secure"],
		["supportFetchAPI"],
		["stream"],
		["bypassCSP"],
		["corsEnabled"],
	] as const)("has %s = true", (flag) => {
		expect(ASSET_SCHEME_PRIVILEGES[flag]).toBe(true);
	});
});

describe("registerAssetSchemeAsPrivileged", () => {
	it("registers exactly the asset scheme with the documented privileges", () => {
		const protocol = { registerSchemesAsPrivileged: vi.fn() };
		registerAssetSchemeAsPrivileged(protocol);
		expect(protocol.registerSchemesAsPrivileged).toHaveBeenCalledTimes(1);
		expect(protocol.registerSchemesAsPrivileged).toHaveBeenCalledWith([
			{ scheme: "asset", privileges: ASSET_SCHEME_PRIVILEGES },
		]);
	});
});

describe("registerAssetProtocolHandler", () => {
	it("hooks the asset scheme on the protocol module", () => {
		const protocol = { handle: vi.fn() };
		registerAssetProtocolHandler(protocol);
		expect(protocol.handle).toHaveBeenCalledTimes(1);
		expect(protocol.handle).toHaveBeenCalledWith("asset", expect.any(Function));
	});
});

// ─── URL → path mapping ──────────────────────────────────────────────────────
//
// Mirrors the renderer's `toAssetUrl` in `src/lib/fileUrl.ts`. If you change one
// side, change the other — these tests will fail otherwise.

describe("assetUrlToFilePath", () => {
	it("decodes a POSIX path", () => {
		expect(assetUrlToFilePath("asset://localhost/Users/foo/bar.webm")).toBe(
			"/Users/foo/bar.webm",
		);
	});

	it("decodes percent-encoded segments", () => {
		expect(assetUrlToFilePath("asset://localhost/Users/foo%20bar/caf%C3%A9.mp4")).toBe(
			"/Users/foo bar/café.mp4",
		);
	});

	it("decodes a Windows drive path without prepending a slash", () => {
		expect(assetUrlToFilePath("asset://localhost/C:/Users/foo/bar.webm")).toBe(
			"C:/Users/foo/bar.webm",
		);
	});

	it("rejects a non-asset URL", () => {
		expect(() => assetUrlToFilePath("https://example.com/foo")).toThrow(/Expected asset/);
	});
});

// ─── handleAssetRequest — file streaming + Range support ─────────────────────
//
// `<video>` issues Range requests to discover size and to seek. Without proper
// 206/Content-Range responses, large WebM files stall mid-load with no error.

describe("handleAssetRequest", () => {
	let tempDir: string;
	let testFile: string;
	const FILE_BYTES = new Uint8Array(
		Array.from({ length: 1024 }, (_, i) => i % 256),
	);

	beforeAll(async () => {
		tempDir = await mkdtemp(path.join(tmpdir(), "asset-protocol-test-"));
		testFile = path.join(tempDir, "video.webm");
		await writeFile(testFile, FILE_BYTES);
	});

	afterAll(async () => {
		await rm(tempDir, { recursive: true, force: true });
	});

	function assetUrl(): string {
		// Build the URL the way the renderer would — POSIX paths only in this
		// suite (Windows path handling is covered by `assetUrlToFilePath` above).
		const encoded = testFile
			.split("/")
			.map((seg) => (seg ? encodeURIComponent(seg) : ""))
			.join("/");
		return `asset://localhost${encoded}`;
	}

	it("returns 200 + full body when no Range header is present", async () => {
		const res = await handleAssetRequest(new Request(assetUrl()));
		expect(res.status).toBe(200);
		expect(res.headers.get("Accept-Ranges")).toBe("bytes");
		expect(res.headers.get("Content-Length")).toBe(String(FILE_BYTES.length));
		expect(res.headers.get("Content-Type")).toBe("video/webm");
		const body = new Uint8Array(await res.arrayBuffer());
		expect(body).toEqual(FILE_BYTES);
	});

	it("returns 206 + slice for a bytes=start-end Range", async () => {
		const res = await handleAssetRequest(
			new Request(assetUrl(), { headers: { Range: "bytes=100-199" } }),
		);
		expect(res.status).toBe(206);
		expect(res.headers.get("Content-Range")).toBe(`bytes 100-199/${FILE_BYTES.length}`);
		expect(res.headers.get("Content-Length")).toBe("100");
		const body = new Uint8Array(await res.arrayBuffer());
		expect(body).toEqual(FILE_BYTES.slice(100, 200));
	});

	it("returns 206 + tail for an open-ended bytes=start- Range", async () => {
		// `<video>` opens with `Range: bytes=0-` to discover total size.
		const res = await handleAssetRequest(
			new Request(assetUrl(), { headers: { Range: "bytes=512-" } }),
		);
		expect(res.status).toBe(206);
		expect(res.headers.get("Content-Range")).toBe(
			`bytes 512-${FILE_BYTES.length - 1}/${FILE_BYTES.length}`,
		);
		const body = new Uint8Array(await res.arrayBuffer());
		expect(body).toEqual(FILE_BYTES.slice(512));
	});

	it("returns 206 + last N bytes for a suffix bytes=-N Range", async () => {
		const res = await handleAssetRequest(
			new Request(assetUrl(), { headers: { Range: "bytes=-128" } }),
		);
		expect(res.status).toBe(206);
		expect(res.headers.get("Content-Range")).toBe(
			`bytes ${FILE_BYTES.length - 128}-${FILE_BYTES.length - 1}/${FILE_BYTES.length}`,
		);
		const body = new Uint8Array(await res.arrayBuffer());
		expect(body).toEqual(FILE_BYTES.slice(-128));
	});

	it("clamps an end-past-EOF Range to file size", async () => {
		const res = await handleAssetRequest(
			new Request(assetUrl(), { headers: { Range: "bytes=900-9999" } }),
		);
		expect(res.status).toBe(206);
		expect(res.headers.get("Content-Range")).toBe(
			`bytes 900-${FILE_BYTES.length - 1}/${FILE_BYTES.length}`,
		);
	});

	it("returns 416 when the start byte is past EOF", async () => {
		const res = await handleAssetRequest(
			new Request(assetUrl(), { headers: { Range: "bytes=99999-" } }),
		);
		expect(res.status).toBe(416);
		expect(res.headers.get("Content-Range")).toBe(`bytes */${FILE_BYTES.length}`);
	});

	it("returns 404 for a missing file", async () => {
		const missing = `asset://localhost${tempDir}/does-not-exist.webm`;
		const res = await handleAssetRequest(new Request(missing));
		expect(res.status).toBe(404);
	});

	it("returns 400 for a non-asset URL", async () => {
		const res = await handleAssetRequest(new Request("https://example.com/x.webm"));
		expect(res.status).toBe(400);
	});

	it("infers Content-Type from extension", async () => {
		const mp4Path = path.join(tempDir, "clip.mp4");
		await writeFile(mp4Path, FILE_BYTES);
		const url = `asset://localhost${mp4Path
			.split("/")
			.map((s) => (s ? encodeURIComponent(s) : ""))
			.join("/")}`;
		const res = await handleAssetRequest(new Request(url));
		expect(res.headers.get("Content-Type")).toBe("video/mp4");
	});
});
