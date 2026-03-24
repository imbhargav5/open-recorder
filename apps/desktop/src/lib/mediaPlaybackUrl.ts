import { convertFileSrc } from "@tauri-apps/api/core";
import { fromFileUrl, toFileUrl } from "@/lib/fileUrl";

const ALREADY_RENDERABLE_MEDIA_PROTOCOL = /^(blob:|data:|asset:|https?:\/\/asset\.localhost\/|https?:)/i;

function getConvertFileSrcRuntime():
	| ((filePath: string, protocol?: string) => string)
	| undefined {
	if (typeof window === "undefined") {
		return undefined;
	}

	return (
		window as Window & {
			__TAURI_INTERNALS__?: {
				convertFileSrc?: (filePath: string, protocol?: string) => string;
			};
		}
	).__TAURI_INTERNALS__?.convertFileSrc;
}

export function resolveMediaPlaybackUrl(pathOrUrl: string): string {
	const value = pathOrUrl.trim();
	if (!value) {
		throw new Error("Path is required");
	}

	if (ALREADY_RENDERABLE_MEDIA_PROTOCOL.test(value)) {
		return value;
	}

	const filePath = value.startsWith("file://") ? fromFileUrl(value) : value;
	const runtimeConvertFileSrc = getConvertFileSrcRuntime();

	if (runtimeConvertFileSrc) {
		return convertFileSrc(filePath);
	}

	return toFileUrl(filePath);
}
