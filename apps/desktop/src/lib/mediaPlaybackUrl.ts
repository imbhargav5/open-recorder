import { fromFileUrl, toFileUrl } from "@/lib/fileUrl";

const ALREADY_RENDERABLE_MEDIA_PROTOCOL =
	/^(blob:|data:|asset:|file:|https?:\/\/asset\.localhost\/|https?:)/i;

export function resolveMediaPlaybackUrl(pathOrUrl: string): string {
	const value = pathOrUrl.trim();
	if (!value) {
		throw new Error("Path is required");
	}

	if (ALREADY_RENDERABLE_MEDIA_PROTOCOL.test(value)) {
		return value;
	}

	// Convert native path to file:// URL for Electron renderer
	const filePath = value.startsWith("file://") ? fromFileUrl(value) : value;
	return toFileUrl(filePath);
}
