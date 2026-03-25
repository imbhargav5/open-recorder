import { WebDemuxer } from "web-demuxer";
import { resolveMediaPlaybackUrl } from "@/lib/backend";
import { type WaveformData, DEFAULT_PEAKS_PER_SECOND } from "./types";

const DECODE_BACKPRESSURE_LIMIT = 30;

/**
 * Resolves a file path or URL to a URL loadable by web-demuxer.
 * Follows the same pattern as StreamingVideoDecoder.
 */
async function resolveVideoUrl(videoPath: string): Promise<string> {
	if (/^(blob:|data:|asset:|https?:)/i.test(videoPath)) {
		return videoPath;
	}

	try {
		return await resolveMediaPlaybackUrl(videoPath);
	} catch {
		return videoPath;
	}
}

/**
 * Compute peak amplitudes from decoded f32 PCM samples.
 * Each bucket covers `samplesPerBucket` frames and produces a single 0..1 peak.
 */
function computePeaks(
	channelData: Float32Array[],
	totalFrames: number,
	samplesPerBucket: number,
): Float32Array {
	const bucketCount = Math.max(1, Math.ceil(totalFrames / samplesPerBucket));
	const peaks = new Float32Array(bucketCount);

	for (let bucket = 0; bucket < bucketCount; bucket++) {
		const start = bucket * samplesPerBucket;
		const end = Math.min(start + samplesPerBucket, totalFrames);
		let maxAmplitude = 0;

		for (const channel of channelData) {
			for (let i = start; i < end; i++) {
				const abs = Math.abs(channel[i]);
				if (abs > maxAmplitude) {
					maxAmplitude = abs;
				}
			}
		}

		peaks[bucket] = Math.min(1, maxAmplitude);
	}

	return peaks;
}

export interface WaveformExtractionOptions {
	peaksPerSecond?: number;
	signal?: AbortSignal;
}

/**
 * Extract waveform peak data from a video file's audio track.
 *
 * Uses web-demuxer to demux the audio stream, then WebCodecs AudioDecoder to
 * decode PCM samples, and finally computes peak amplitudes at the requested
 * resolution. Returns null if the video has no audio track.
 */
export async function extractWaveformData(
	videoPath: string,
	options: WaveformExtractionOptions = {},
): Promise<WaveformData | null> {
	const peaksPerSecond = options.peaksPerSecond ?? DEFAULT_PEAKS_PER_SECOND;
	const signal = options.signal;

	const resourceUrl = await resolveVideoUrl(videoPath);

	if (signal?.aborted) return null;

	const wasmUrl = new URL("./wasm/web-demuxer.wasm", window.location.href).href;
	const demuxer = new WebDemuxer({ wasmFilePath: wasmUrl });

	try {
		await demuxer.load(resourceUrl);

		if (signal?.aborted) return null;

		const mediaInfo = await demuxer.getMediaInfo();
		const audioStream = mediaInfo.streams.find(
			(s: { codec_type_string: string }) => s.codec_type_string === "audio",
		);

		if (!audioStream) {
			return null;
		}

		let audioConfig: AudioDecoderConfig;
		try {
			audioConfig = (await demuxer.getDecoderConfig("audio")) as AudioDecoderConfig;
		} catch {
			console.warn("[WaveformExtractor] Failed to get audio decoder config");
			return null;
		}

		const configCheck = await AudioDecoder.isConfigSupported(audioConfig);
		if (!configCheck.supported) {
			console.warn("[WaveformExtractor] Audio codec not supported:", audioConfig.codec);
			return null;
		}

		const sampleRate = audioConfig.sampleRate || 48_000;
		const channelCount = audioConfig.numberOfChannels || 2;
		const duration = mediaInfo.duration;

		// Pre-allocate channel buffers for the expected total samples.
		// We'll grow if needed.
		const expectedTotalFrames = Math.ceil(duration * sampleRate) + sampleRate; // +1s buffer
		const channelBuffers: Float32Array[] = [];
		for (let c = 0; c < channelCount; c++) {
			channelBuffers.push(new Float32Array(expectedTotalFrames));
		}
		let writtenFrames = 0;

		const decodedFrames: AudioData[] = [];

		const decoder = new AudioDecoder({
			output: (data: AudioData) => decodedFrames.push(data),
			error: (error: DOMException) =>
				console.error("[WaveformExtractor] Decode error:", error),
		});
		decoder.configure(audioConfig);

		const audioReadStream = demuxer.read("audio");
		const reader = (audioReadStream as ReadableStream<EncodedAudioChunk>).getReader();

		while (!signal?.aborted) {
			const { done, value: chunk } = await reader.read();
			if (done || !chunk) break;

			decoder.decode(chunk);

			// Apply backpressure
			while (decoder.decodeQueueSize > DECODE_BACKPRESSURE_LIMIT && !signal?.aborted) {
				await new Promise((resolve) => setTimeout(resolve, 1));
			}

			// Drain decoded frames periodically to avoid holding too much in memory
			while (decodedFrames.length > 0) {
				const frame = decodedFrames.shift()!;
				writtenFrames = copyAudioDataToBuffers(
					frame,
					channelBuffers,
					writtenFrames,
					channelCount,
				);
				frame.close();
			}
		}

		if (signal?.aborted) {
			if (decoder.state === "configured") {
				decoder.close();
			}
			return null;
		}

		if (decoder.state === "configured") {
			await decoder.flush();
			decoder.close();
		}

		// Drain remaining frames
		while (decodedFrames.length > 0) {
			const frame = decodedFrames.shift()!;
			writtenFrames = copyAudioDataToBuffers(
				frame,
				channelBuffers,
				writtenFrames,
				channelCount,
			);
			frame.close();
		}

		if (writtenFrames === 0) {
			return null;
		}

		// Trim buffers to actual size
		const trimmedChannels = channelBuffers.map((buf) => buf.subarray(0, writtenFrames));

		const samplesPerBucket = Math.max(1, Math.round(sampleRate / peaksPerSecond));
		const peaks = computePeaks(trimmedChannels, writtenFrames, samplesPerBucket);

		return {
			peaksPerSecond,
			duration,
			peaks,
			sampleRate,
			channelCount,
			sourcePath: videoPath,
		};
	} finally {
		try {
			demuxer.destroy();
		} catch {
			// ignore cleanup errors
		}
	}
}

/**
 * Copy decoded AudioData PCM samples into pre-allocated channel buffers.
 * Returns the updated write offset.
 */
function copyAudioDataToBuffers(
	audioData: AudioData,
	channelBuffers: Float32Array[],
	writeOffset: number,
	targetChannels: number,
): number {
	const format = audioData.format;
	const numberOfFrames = audioData.numberOfFrames;
	const sourceChannels = audioData.numberOfChannels;

	// We need f32-planar for easy peak computation. If format is different,
	// we'll convert via an intermediate buffer.
	const isPlanar = format?.includes("planar") ?? false;

	for (let c = 0; c < targetChannels; c++) {
		const sourceChannel = Math.min(c, sourceChannels - 1);
		const buffer = channelBuffers[c];

		// Grow buffer if needed
		if (writeOffset + numberOfFrames > buffer.length) {
			const newSize = Math.max(buffer.length * 2, writeOffset + numberOfFrames + 48000);
			const grown = new Float32Array(newSize);
			grown.set(buffer);
			channelBuffers[c] = grown;
		}

		const dest = channelBuffers[c];

		if (format === "f32-planar") {
			const planeData = new Float32Array(numberOfFrames);
			audioData.copyTo(planeData, { planeIndex: sourceChannel });
			dest.set(planeData, writeOffset);
		} else if (format === "f32") {
			// Interleaved f32: extract every Nth sample
			const allData = new Float32Array(numberOfFrames * sourceChannels);
			audioData.copyTo(allData, { planeIndex: 0 });
			for (let i = 0; i < numberOfFrames; i++) {
				dest[writeOffset + i] = allData[i * sourceChannels + sourceChannel];
			}
		} else if (format === "s16-planar") {
			const planeData = new Int16Array(numberOfFrames);
			audioData.copyTo(planeData, { planeIndex: sourceChannel });
			for (let i = 0; i < numberOfFrames; i++) {
				dest[writeOffset + i] = planeData[i] / 32768;
			}
		} else if (format === "s16") {
			const allData = new Int16Array(numberOfFrames * sourceChannels);
			audioData.copyTo(allData, { planeIndex: 0 });
			for (let i = 0; i < numberOfFrames; i++) {
				dest[writeOffset + i] = allData[i * sourceChannels + sourceChannel] / 32768;
			}
		} else {
			// Fallback: try f32-planar copy
			try {
				const planeData = new Float32Array(
					isPlanar ? numberOfFrames : numberOfFrames * sourceChannels,
				);
				audioData.copyTo(planeData, { planeIndex: isPlanar ? sourceChannel : 0 });
				if (isPlanar) {
					dest.set(planeData, writeOffset);
				} else {
					for (let i = 0; i < numberOfFrames; i++) {
						dest[writeOffset + i] = planeData[i * sourceChannels + sourceChannel];
					}
				}
			} catch {
				// Fill with silence if unsupported format
				dest.fill(0, writeOffset, writeOffset + numberOfFrames);
			}
		}
	}

	return writeOffset + numberOfFrames;
}
