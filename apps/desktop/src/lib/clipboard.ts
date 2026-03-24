import { Image } from "@tauri-apps/api/image";
import { writeImage } from "@tauri-apps/plugin-clipboard-manager";

export async function copyCanvasImageToClipboard(canvas: HTMLCanvasElement): Promise<void> {
	const context = canvas.getContext("2d");
	if (!context) {
		throw new Error("Failed to read rendered image");
	}

	const imageData = context.getImageData(0, 0, canvas.width, canvas.height);
	const image = await Image.new(imageData.data, canvas.width, canvas.height);

	try {
		await writeImage(image);
	} finally {
		await image.close();
	}
}
