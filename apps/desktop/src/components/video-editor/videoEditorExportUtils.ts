import {
	calculateOutputDimensions,
	GIF_SIZE_PRESETS,
	type ExportSettings,
	type GifFrameRate,
	type ExportQuality,
	type GifSizePreset,
} from "@/lib/exporter";
import { getAspectRatioValue, type AspectRatio } from "@/utils/aspectRatioUtils";

type BuildExportSettingsParams = {
	format: "mp4" | "gif";
	exportQuality: ExportQuality;
	gifFrameRate: GifFrameRate;
	gifLoop: boolean;
	gifSizePreset: GifSizePreset;
	sourceWidth: number;
	sourceHeight: number;
};

export type Mp4ExportPlan = {
	width: number;
	height: number;
	bitrate: number;
};

type BuildMp4ExportPlanParams = {
	quality: ExportQuality;
	sourceWidth: number;
	sourceHeight: number;
	aspectRatio: AspectRatio;
};

export function buildImmediateExportSettings({
	format,
	exportQuality,
	gifFrameRate,
	gifLoop,
	gifSizePreset,
	sourceWidth,
	sourceHeight,
}: BuildExportSettingsParams): ExportSettings {
	const gifDimensions = calculateOutputDimensions(
		sourceWidth,
		sourceHeight,
		gifSizePreset,
		GIF_SIZE_PRESETS,
	);

	return {
		format,
		quality: format === "mp4" ? exportQuality : undefined,
		gifConfig:
			format === "gif"
				? {
						frameRate: gifFrameRate,
						loop: gifLoop,
						sizePreset: gifSizePreset,
						width: gifDimensions.width,
						height: gifDimensions.height,
					}
				: undefined,
	};
}

export function buildMp4ExportPlan({
	quality,
	sourceWidth,
	sourceHeight,
	aspectRatio,
}: BuildMp4ExportPlanParams): Mp4ExportPlan {
	const sourceAspectRatio = sourceHeight > 0 ? sourceWidth / sourceHeight : 16 / 9;
	const aspectRatioValue = getAspectRatioValue(aspectRatio, sourceAspectRatio);

	if (quality === "source") {
		return buildSourceQualityPlan({
			sourceWidth,
			sourceHeight,
			aspectRatio,
			aspectRatioValue,
		});
	}

	return buildScaledQualityPlan(quality, aspectRatioValue);
}

function buildSourceQualityPlan({
	sourceWidth,
	sourceHeight,
	aspectRatio,
	aspectRatioValue,
}: {
	sourceWidth: number;
	sourceHeight: number;
	aspectRatio: AspectRatio;
	aspectRatioValue: number;
}): Mp4ExportPlan {
	let width = sourceWidth;
	let height = sourceHeight;

	if (aspectRatio === "native") {
		width = Math.floor(sourceWidth / 2) * 2;
		height = Math.floor(sourceHeight / 2) * 2;
	} else if (aspectRatioValue === 1) {
		const baseDimension = Math.floor(Math.min(sourceWidth, sourceHeight) / 2) * 2;
		width = baseDimension;
		height = baseDimension;
	} else if (aspectRatioValue > 1) {
		const baseWidth = Math.floor(sourceWidth / 2) * 2;
		let found = false;
		for (let candidateWidth = baseWidth; candidateWidth >= 100 && !found; candidateWidth -= 2) {
			const candidateHeight = Math.round(candidateWidth / aspectRatioValue);
			if (
				candidateHeight % 2 === 0 &&
				Math.abs(candidateWidth / candidateHeight - aspectRatioValue) < 0.0001
			) {
				width = candidateWidth;
				height = candidateHeight;
				found = true;
			}
		}
		if (!found) {
			width = baseWidth;
			height = Math.floor(baseWidth / aspectRatioValue / 2) * 2;
		}
	} else {
		const baseHeight = Math.floor(sourceHeight / 2) * 2;
		let found = false;
		for (let candidateHeight = baseHeight; candidateHeight >= 100 && !found; candidateHeight -= 2) {
			const candidateWidth = Math.round(candidateHeight * aspectRatioValue);
			if (
				candidateWidth % 2 === 0 &&
				Math.abs(candidateWidth / candidateHeight - aspectRatioValue) < 0.0001
			) {
				width = candidateWidth;
				height = candidateHeight;
				found = true;
			}
		}
		if (!found) {
			height = baseHeight;
			width = Math.floor((baseHeight * aspectRatioValue) / 2) * 2;
		}
	}

	const totalPixels = width * height;
	let bitrate = 30_000_000;
	if (totalPixels > 1920 * 1080 && totalPixels <= 2560 * 1440) {
		bitrate = 50_000_000;
	} else if (totalPixels > 2560 * 1440) {
		bitrate = 80_000_000;
	}

	return { width, height, bitrate };
}

function buildScaledQualityPlan(
	quality: Exclude<ExportQuality, "source">,
	aspectRatioValue: number,
): Mp4ExportPlan {
	const targetHeight = quality === "medium" ? 720 : 1080;
	const height = Math.floor(targetHeight / 2) * 2;
	const width = Math.floor((height * aspectRatioValue) / 2) * 2;

	const totalPixels = width * height;
	let bitrate: number;
	if (totalPixels <= 1280 * 720) {
		bitrate = 10_000_000;
	} else if (totalPixels <= 1920 * 1080) {
		bitrate = 20_000_000;
	} else {
		bitrate = 30_000_000;
	}

	return { width, height, bitrate };
}
