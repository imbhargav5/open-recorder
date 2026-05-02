import { fromFileUrl, toAssetUrl } from "@/lib/fileUrl";

const ALREADY_RENDERABLE_MEDIA_PROTOCOL =
	/^(blob:|data:|asset:|https?:\/\/asset\.localhost\/|https?:)/i;

/**
 * Resolve any path-or-URL to a URL `<video>`/`<img>` can load. Native paths and
 * `file://` URLs are routed through the privileged `asset://` protocol so they
 * play back from both the `http://localhost` dev renderer and packaged builds.
 */
export function resolveMediaPlaybackUrl(pathOrUrl: string): string {
	const value = pathOrUrl.trim();
	if (!value) {
		throw new Error("Path is required");
	}

	if (ALREADY_RENDERABLE_MEDIA_PROTOCOL.test(value)) {
		return value;
	}

	const filePath = value.startsWith("file://") ? fromFileUrl(value) : value;
	return toAssetUrl(filePath);
}
