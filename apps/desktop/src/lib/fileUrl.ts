function isFileUrl(value: string): boolean {
	return /^file:\/\//i.test(value);
}

function encodePathSegments(pathname: string, keepWindowsDrive = false): string {
	return pathname
		.split("/")
		.map((segment, index) => {
			if (!segment) return "";
			if (keepWindowsDrive && index === 1 && /^[a-zA-Z]:$/.test(segment)) {
				return segment;
			}
			return encodeURIComponent(segment);
		})
		.join("/");
}

export function toFileUrl(filePath: string): string {
	const normalized = filePath.replace(/\\/g, "/");

	if (/^[a-zA-Z]:\//.test(normalized)) {
		return `file://${encodePathSegments(`/${normalized}`, true)}`;
	}

	if (normalized.startsWith("//")) {
		const [host, ...pathParts] = normalized.replace(/^\/+/, "").split("/");
		const encodedPath = pathParts.map((part) => encodeURIComponent(part)).join("/");
		return encodedPath ? `file://${host}/${encodedPath}` : `file://${host}/`;
	}

	const absolutePath = normalized.startsWith("/") ? normalized : `/${normalized}`;
	return `file://${encodePathSegments(absolutePath)}`;
}

/**
 * Convert a local file path to an `asset://` URL the renderer can load.
 *
 * Why not `file://`? In dev the renderer is served from `http://localhost:5789`,
 * so Chromium treats `file://` as cross-origin and refuses to play it back in
 * `<video>`. The `asset` scheme is registered as a privileged custom protocol
 * (see `electron/main.ts`) and works identically in dev and in packaged builds.
 *
 * Shape: `asset://localhost/<absolute-path-with-forward-slashes-percent-encoded>`.
 * The `localhost` host is required because the scheme is registered as `standard`.
 */
export function toAssetUrl(filePath: string): string {
	const normalized = filePath.replace(/\\/g, "/");

	if (/^[a-zA-Z]:\//.test(normalized)) {
		// Windows drive path. encodePathSegments preserves the drive letter when it
		// sits at index 1 of the split — so prefix a slash before splitting.
		return `asset://localhost${encodePathSegments(`/${normalized}`, true)}`;
	}

	if (normalized.startsWith("//")) {
		// UNC. Collapse the host into the path so the asset host stays "localhost"
		// — the main-process handler doesn't need to distinguish UNC from POSIX.
		const segments = normalized.replace(/^\/+/, "").split("/").filter(Boolean);
		return `asset://localhost/${segments.map(encodeURIComponent).join("/")}`;
	}

	const absolutePath = normalized.startsWith("/") ? normalized : `/${normalized}`;
	return `asset://localhost${encodePathSegments(absolutePath)}`;
}

export function fromFileUrl(fileUrl: string): string {
	const value = fileUrl.trim();
	if (!isFileUrl(value)) {
		return fileUrl;
	}

	try {
		const url = new URL(value);
		const pathname = decodeURIComponent(url.pathname);

		if (url.host && url.host !== "localhost") {
			const uncPath = `//${url.host}${pathname.startsWith("/") ? pathname : `/${pathname}`}`;
			return uncPath.replace(/\//g, "\\");
		}

		if (/^\/[A-Za-z]:/.test(pathname)) {
			return pathname.slice(1);
		}

		return pathname;
	} catch {
		const rawFallbackPath = value.replace(/^file:\/\//i, "");
		let fallbackPath = rawFallbackPath;
		try {
			fallbackPath = decodeURIComponent(rawFallbackPath);
		} catch {
			// Keep raw best-effort path if percent decoding fails.
		}
		return fallbackPath.replace(/^\/([a-zA-Z]:)/, "$1");
	}
}
