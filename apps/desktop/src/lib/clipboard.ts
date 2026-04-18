/**
 * Clipboard utilities for the Electron renderer.
 *
 * Uses the navigator.clipboard API (available in Electron's renderer process).
 * Falls back to IPC-based clipboard write for environments where the
 * Clipboard API is unavailable.
 */

import { invoke } from "@/lib/electronBridge";

export async function copyCanvasImageToClipboard(canvas: HTMLCanvasElement): Promise<void> {
	const context = canvas.getContext("2d");
	if (!context) {
		throw new Error("Failed to read rendered image");
	}

	const imageData = context.getImageData(0, 0, canvas.width, canvas.height);

	// Try navigator.clipboard.write first (works in Electron renderer with permissions)
	if (typeof ClipboardItem !== "undefined" && navigator.clipboard?.write) {
		const blob = await canvasToBlob(canvas);
		const item = new ClipboardItem({ "image/png": blob });
		await navigator.clipboard.write([item]);
		return;
	}

	// Fallback: send raw RGBA data to main process via IPC
	await invoke("write_clipboard_image", {
		data: Array.from(imageData.data),
		width: canvas.width,
		height: canvas.height,
	});
}

function canvasToBlob(canvas: HTMLCanvasElement): Promise<Blob> {
	return new Promise((resolve, reject) => {
		canvas.toBlob((blob) => {
			if (blob) {
				resolve(blob);
			} else {
				reject(new Error("Failed to create image blob from canvas"));
			}
		}, "image/png");
	});
}
