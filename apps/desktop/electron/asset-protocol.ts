/**
 * `asset://` custom protocol — single source of truth for streaming local files
 * into the renderer.
 *
 * Why a custom protocol? In dev the renderer is loaded from `http://localhost:5789`,
 * and Chromium refuses to play `file://` URLs in `<video>` from a non-`file://`
 * origin. Routing media through `asset://localhost/<path>` works identically in
 * dev and in packaged builds, and the privileged registration unlocks range
 * requests (required for `<video>` seeking), CORS, and CSP bypass.
 *
 * The privileges and scheme name are part of the renderer↔main contract used by
 * `src/lib/fileUrl.ts#toAssetUrl` — change them in lockstep, or playback breaks.
 */

import { type Protocol } from "electron";
import { createReadStream, promises as fsp } from "node:fs";
import { Readable } from "node:stream";
import type { ReadableStream as NodeReadableStream } from "node:stream/web";

export const ASSET_SCHEME = "asset" as const;

export const ASSET_SCHEME_PRIVILEGES = {
	standard: true,
	secure: true,
	supportFetchAPI: true,
	stream: true,
	bypassCSP: true,
	corsEnabled: true,
} as const;

/**
 * Convert an `asset://` URL into the absolute filesystem path it points at.
 *
 * URL shape (mirrors `toAssetUrl` in the renderer):
 *   asset://localhost/Users/foo/bar.webm           (POSIX)
 *   asset://localhost/C:/Users/foo/bar.webm        (Windows drive)
 *   asset://localhost/server/share/path            (UNC, host collapsed into path)
 */
export function assetUrlToFilePath(assetUrl: string): string {
	const url = new URL(assetUrl);
	if (url.protocol !== `${ASSET_SCHEME}:`) {
		throw new Error(`Expected ${ASSET_SCHEME}:// URL, got ${url.protocol}`);
	}
	const decoded = decodeURIComponent(url.pathname);
	const trimmed = decoded.replace(/^\/+/, "");
	const isWindowsAbsolute = /^[a-zA-Z]:[\\/]/.test(trimmed);
	return isWindowsAbsolute ? trimmed : `/${trimmed}`;
}

/**
 * Register the `asset` scheme as privileged. **Must be called before
 * `app.whenReady()`** — Electron freezes the privileged-scheme list at ready time.
 */
export function registerAssetSchemeAsPrivileged(
	protocol: Pick<Protocol, "registerSchemesAsPrivileged">,
): void {
	protocol.registerSchemesAsPrivileged([
		{ scheme: ASSET_SCHEME, privileges: ASSET_SCHEME_PRIVILEGES },
	]);
}

/**
 * Install the runtime handler that turns `asset://` requests into file reads.
 * Honors HTTP Range requests so `<video>` can seek and progressively stream
 * large local files. Call inside `app.whenReady()`.
 */
export function registerAssetProtocolHandler(
	protocol: Pick<Protocol, "handle">,
): void {
	protocol.handle(ASSET_SCHEME, (request) => handleAssetRequest(request));
}

export async function handleAssetRequest(request: Request): Promise<Response> {
	let filePath: string;
	try {
		filePath = assetUrlToFilePath(request.url);
	} catch (err) {
		return new Response(String(err), { status: 400 });
	}

	let stat: Awaited<ReturnType<typeof fsp.stat>>;
	try {
		stat = await fsp.stat(filePath);
	} catch {
		return new Response("Not Found", { status: 404 });
	}
	if (!stat.isFile()) {
		return new Response("Not Found", { status: 404 });
	}

	const fileSize = stat.size;
	const rangeHeader = request.headers.get("Range") ?? request.headers.get("range");
	const range = rangeHeader ? parseRangeHeader(rangeHeader, fileSize) : null;

	if (rangeHeader && !range) {
		return new Response("Range Not Satisfiable", {
			status: 416,
			headers: { "Content-Range": `bytes */${fileSize}` },
		});
	}

	const start = range?.start ?? 0;
	const end = range?.end ?? fileSize - 1;
	const length = end - start + 1;

	const nodeStream = createReadStream(filePath, { start, end });
	const webStream = Readable.toWeb(nodeStream) as unknown as NodeReadableStream<Uint8Array>;

	const headers: HeadersInit = {
		"Accept-Ranges": "bytes",
		"Content-Length": String(length),
		"Content-Type": guessContentType(filePath),
	};
	if (range) {
		(headers as Record<string, string>)["Content-Range"] = `bytes ${start}-${end}/${fileSize}`;
	}

	return new Response(webStream as unknown as ReadableStream, {
		status: range ? 206 : 200,
		headers,
	});
}

function parseRangeHeader(header: string, fileSize: number): { start: number; end: number } | null {
	// Only honor the simple `bytes=start-end` / `bytes=start-` / `bytes=-suffix` forms.
	const match = /^bytes=(\d*)-(\d*)$/i.exec(header.trim());
	if (!match) return null;

	const startStr = match[1];
	const endStr = match[2];

	if (!startStr && !endStr) return null;

	let start: number;
	let end: number;
	if (!startStr) {
		// Suffix form: last N bytes.
		const suffix = Number(endStr);
		if (!Number.isFinite(suffix) || suffix <= 0) return null;
		start = Math.max(0, fileSize - suffix);
		end = fileSize - 1;
	} else {
		start = Number(startStr);
		end = endStr ? Number(endStr) : fileSize - 1;
	}

	if (!Number.isFinite(start) || !Number.isFinite(end)) return null;
	if (start < 0 || start >= fileSize || end < start) return null;
	if (end >= fileSize) end = fileSize - 1;
	return { start, end };
}

const CONTENT_TYPE_BY_EXT: Record<string, string> = {
	webm: "video/webm",
	mp4: "video/mp4",
	mov: "video/quicktime",
	mkv: "video/x-matroska",
	m4v: "video/x-m4v",
	ogg: "video/ogg",
	ogv: "video/ogg",
	avi: "video/x-msvideo",
	wav: "audio/wav",
	mp3: "audio/mpeg",
	m4a: "audio/mp4",
	aac: "audio/aac",
	flac: "audio/flac",
	opus: "audio/opus",
	png: "image/png",
	jpg: "image/jpeg",
	jpeg: "image/jpeg",
	gif: "image/gif",
	webp: "image/webp",
	svg: "image/svg+xml",
};

function guessContentType(filePath: string): string {
	const ext = filePath.split(".").pop()?.toLowerCase() ?? "";
	return CONTENT_TYPE_BY_EXT[ext] ?? "application/octet-stream";
}
