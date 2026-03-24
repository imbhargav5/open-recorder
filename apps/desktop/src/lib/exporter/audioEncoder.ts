import { WebDemuxer } from "web-demuxer";
import type { SpeedRegion, TrimRegion } from "@/components/video-editor/types";
import type { VideoMuxer } from "./muxer";

const AUDIO_BITRATE = 128_000;
const DECODE_BACKPRESSURE_LIMIT = 20;
const MIN_SPEED_REGION_DELTA_MS = 0.0001;

export class AudioProcessor {
	private cancelled = false;

	/**
	 * Audio export has two modes:
	 * 1) no speed regions -> fast WebCodecs trim-only pipeline
	 * 2) speed regions present -> pitch-preserving rendered timeline pipeline
	 */
	async process(
		demuxer: WebDemuxer,
		muxer: VideoMuxer,
		videoUrl: string,
		trimRegions?: TrimRegion[],
		speedRegions?: SpeedRegion[],
		readEndSec?: number,
	): Promise<void> {
		const sortedTrims = trimRegions ? [...trimRegions].sort((a, b) => a.startMs - b.startMs) : [];
		const sortedSpeedRegions = speedRegions
			? [...speedRegions]
					.filter((region) => region.endMs - region.startMs > MIN_SPEED_REGION_DELTA_MS)
					.sort((a, b) => a.startMs - b.startMs)
			: [];

		// Speed edits must use timeline playback to preserve pitch.
		if (sortedSpeedRegions.length > 0) {
			await this.renderPitchPreservedTimelineAudioToMuxer(
				videoUrl,
				sortedTrims,
				sortedSpeedRegions,
				muxer,
			);
			return;
		}

		// No speed edits: keep the original demux/decode/encode path with trim timestamp remap.
		await this.processTrimOnlyAudio(demuxer, muxer, sortedTrims, readEndSec);
	}

	// Legacy trim-only path used when no speed regions are configured.
	private async processTrimOnlyAudio(
		demuxer: WebDemuxer,
		muxer: VideoMuxer,
		sortedTrims: TrimRegion[],
		readEndSec?: number,
	): Promise<void> {
		let audioConfig: AudioDecoderConfig;
		try {
			audioConfig = (await demuxer.getDecoderConfig("audio")) as AudioDecoderConfig;
		} catch {
			console.warn("[AudioProcessor] No audio track found, skipping");
			return;
		}

		const codecCheck = await AudioDecoder.isConfigSupported(audioConfig);
		if (!codecCheck.supported) {
			console.warn("[AudioProcessor] Audio codec not supported:", audioConfig.codec);
			return;
		}

		const decodedFrames: AudioData[] = [];

		const decoder = new AudioDecoder({
			output: (data: AudioData) => decodedFrames.push(data),
			error: (error: DOMException) => console.error("[AudioProcessor] Decode error:", error),
		});
		decoder.configure(audioConfig);

		const audioStream =
			typeof readEndSec === "number" ? demuxer.read("audio", 0, readEndSec) : demuxer.read("audio");
		const reader = (audioStream as ReadableStream<EncodedAudioChunk>).getReader();

		while (!this.cancelled) {
			const { done, value: chunk } = await reader.read();
			if (done || !chunk) break;

			const timestampMs = chunk.timestamp / 1000;
			if (this.isInTrimRegion(timestampMs, sortedTrims)) continue;

			decoder.decode(chunk);

			while (decoder.decodeQueueSize > DECODE_BACKPRESSURE_LIMIT && !this.cancelled) {
				await new Promise((resolve) => setTimeout(resolve, 1));
			}
		}

		if (decoder.state === "configured") {
			await decoder.flush();
			decoder.close();
		}

		if (this.cancelled || decodedFrames.length === 0) {
			for (const frame of decodedFrames) frame.close();
			return;
		}

		const encodedChunks: { chunk: EncodedAudioChunk; meta?: EncodedAudioChunkMetadata }[] = [];
		const encoder = new AudioEncoder({
			output: (chunk: EncodedAudioChunk, meta?: EncodedAudioChunkMetadata) => {
				encodedChunks.push({ chunk, meta });
			},
			error: (error: DOMException) => console.error("[AudioProcessor] Encode error:", error),
		});

		const sampleRate = audioConfig.sampleRate || 48_000;
		const channels = audioConfig.numberOfChannels || 2;
		const encodeConfig: AudioEncoderConfig = {
			codec: "opus",
			sampleRate,
			numberOfChannels: channels,
			bitrate: AUDIO_BITRATE,
		};

		const encodeSupport = await AudioEncoder.isConfigSupported(encodeConfig);
		if (!encodeSupport.supported) {
			console.warn("[AudioProcessor] Opus encoding not supported, skipping audio");
			for (const frame of decodedFrames) frame.close();
			return;
		}

		encoder.configure(encodeConfig);

		for (const audioData of decodedFrames) {
			if (this.cancelled) {
				audioData.close();
				continue;
			}

			const timestampMs = audioData.timestamp / 1000;
			const trimOffsetMs = this.computeTrimOffset(timestampMs, sortedTrims);
			const adjustedTimestampUs = audioData.timestamp - trimOffsetMs * 1000;

			const adjusted = this.cloneWithTimestamp(audioData, Math.max(0, adjustedTimestampUs));
			audioData.close();

			encoder.encode(adjusted);
			adjusted.close();
		}

		if (encoder.state === "configured") {
			await encoder.flush();
			encoder.close();
		}

		for (const { chunk, meta } of encodedChunks) {
			if (this.cancelled) break;
			await muxer.addAudioChunk(chunk, meta);
		}
	}

	// Speed-aware path that mirrors preview semantics (trim skipping + playbackRate regions)
	// and preserves pitch through browser media playback behavior while streaming
	// PCM directly into WebCodecs instead of blobbing and demuxing a second time.
	private async renderPitchPreservedTimelineAudioToMuxer(
		videoUrl: string,
		trimRegions: TrimRegion[],
		speedRegions: SpeedRegion[],
		muxer: VideoMuxer,
	): Promise<void> {
		const media = document.createElement("audio");
		media.src = videoUrl;
		media.preload = "auto";

		const pitchMedia = media as HTMLMediaElement & {
			preservesPitch?: boolean;
			mozPreservesPitch?: boolean;
			webkitPreservesPitch?: boolean;
		};
		pitchMedia.preservesPitch = true;
		pitchMedia.mozPreservesPitch = true;
		pitchMedia.webkitPreservesPitch = true;

		await this.waitForLoadedMetadata(media);
		if (this.cancelled) {
			throw new Error("Export cancelled");
		}

		const audioContext = new AudioContext();
		const sourceNode = audioContext.createMediaElementSource(media);
		const processorNode = audioContext.createScriptProcessor(4096);
		const silentGainNode = audioContext.createGain();
		silentGainNode.gain.value = 0;

		sourceNode.connect(processorNode);
		processorNode.connect(silentGainNode);
		silentGainNode.connect(audioContext.destination);

		const channelCount = Math.max(1, processorNode.channelCount || 2);
		const encodeConfig: AudioEncoderConfig = {
			codec: "opus",
			sampleRate: audioContext.sampleRate,
			numberOfChannels: channelCount,
			bitrate: AUDIO_BITRATE,
		};
		const encodeSupport = await AudioEncoder.isConfigSupported(encodeConfig);
		if (!encodeSupport.supported) {
			throw new Error("Opus encoding is not supported for speed-adjusted audio export");
		}

		let muxingComplete = Promise.resolve();
		let audioTimestampUs = 0;
		let firstChunkWritten = false;
		let encodeError: Error | null = null;
		let muxingError: Error | null = null;

		const encoder = new AudioEncoder({
			output: (chunk: EncodedAudioChunk, meta?: EncodedAudioChunkMetadata) => {
				muxingComplete = muxingComplete
					.then(async () => {
						if (this.cancelled) {
							return;
						}

						await muxer.addAudioChunk(chunk, firstChunkWritten ? undefined : meta);
						firstChunkWritten = true;
					})
					.catch((error) => {
						muxingError = error instanceof Error ? error : new Error(String(error));
					});
			},
			error: (error: DOMException) => {
				encodeError = new Error(`[AudioProcessor] Encode error: ${error.message}`);
			},
		});
		encoder.configure(encodeConfig);

		processorNode.onaudioprocess = (event: AudioProcessingEvent) => {
			if (this.cancelled || encodeError) {
				return;
			}

			const inputBuffer = event.inputBuffer;
			const numberOfFrames = inputBuffer.length;
			if (numberOfFrames === 0) {
				return;
			}

			try {
				const audioData = this.createAudioDataFromBuffer(
					inputBuffer,
					audioTimestampUs,
					encodeConfig.numberOfChannels,
				);
				audioTimestampUs += Math.round((numberOfFrames / encodeConfig.sampleRate) * 1_000_000);
				encoder.encode(audioData);
				audioData.close();
			} catch (error) {
				encodeError = error instanceof Error ? error : new Error(String(error));
			}

			const outputBuffer = event.outputBuffer;
			for (let channel = 0; channel < outputBuffer.numberOfChannels; channel++) {
				outputBuffer.getChannelData(channel).fill(0);
			}
		};

		let rafId: number | null = null;

		try {
			if (audioContext.state === "suspended") {
				await audioContext.resume();
			}

			await this.seekTo(media, 0);
			await media.play();

			await new Promise<void>((resolve, reject) => {
				const cleanup = () => {
					if (rafId !== null) {
						cancelAnimationFrame(rafId);
						rafId = null;
					}
					media.removeEventListener("error", onError);
					media.removeEventListener("ended", onEnded);
				};

				const onError = () => {
					cleanup();
					reject(new Error("Failed while rendering speed-adjusted audio timeline"));
				};

				const onEnded = () => {
					cleanup();
					resolve();
				};

				const tick = () => {
					if (this.cancelled) {
						cleanup();
						resolve();
						return;
					}

					const currentTimeMs = media.currentTime * 1000;
					const activeTrimRegion = this.findActiveTrimRegion(currentTimeMs, trimRegions);

					if (activeTrimRegion && !media.paused && !media.ended) {
						const skipToTime = activeTrimRegion.endMs / 1000;
						if (skipToTime >= media.duration) {
							media.pause();
							cleanup();
							resolve();
							return;
						}
						media.currentTime = skipToTime;
					} else {
						const activeSpeedRegion = this.findActiveSpeedRegion(currentTimeMs, speedRegions);
						const playbackRate = activeSpeedRegion ? activeSpeedRegion.speed : 1;
						if (Math.abs(media.playbackRate - playbackRate) > 0.0001) {
							media.playbackRate = playbackRate;
						}
					}

					if (!media.paused && !media.ended) {
						rafId = requestAnimationFrame(tick);
					} else {
						cleanup();
						resolve();
					}
				};

				media.addEventListener("error", onError, { once: true });
				media.addEventListener("ended", onEnded, { once: true });
				rafId = requestAnimationFrame(tick);
			});

			if (encodeError) {
				throw encodeError;
			}
			if (muxingError) {
				throw muxingError;
			}

			processorNode.onaudioprocess = null;

			if (encoder.state === "configured") {
				await encoder.flush();
				await muxingComplete;
				if (muxingError) {
					throw muxingError;
				}
				encoder.close();
			}
		} finally {
			if (rafId !== null) {
				cancelAnimationFrame(rafId);
			}
			media.pause();
			processorNode.onaudioprocess = null;
			sourceNode.disconnect();
			processorNode.disconnect();
			silentGainNode.disconnect();
			if (encoder.state !== "closed") {
				try {
					if (encoder.state === "configured") {
						await encoder.flush();
						await muxingComplete;
					}
					encoder.close();
				} catch {
					// ignore cleanup errors while tearing down cancelled exports
				}
			}
			await audioContext.close();
			media.src = "";
			media.load();
		}
	}

	private waitForLoadedMetadata(media: HTMLMediaElement): Promise<void> {
		if (Number.isFinite(media.duration) && media.readyState >= HTMLMediaElement.HAVE_METADATA) {
			return Promise.resolve();
		}

		return new Promise<void>((resolve, reject) => {
			const onLoaded = () => {
				cleanup();
				resolve();
			};
			const onError = () => {
				cleanup();
				reject(new Error("Failed to load media metadata for speed-adjusted audio"));
			};
			const cleanup = () => {
				media.removeEventListener("loadedmetadata", onLoaded);
				media.removeEventListener("error", onError);
			};

			media.addEventListener("loadedmetadata", onLoaded);
			media.addEventListener("error", onError, { once: true });
		});
	}

	private seekTo(media: HTMLMediaElement, targetSec: number): Promise<void> {
		if (Math.abs(media.currentTime - targetSec) < 0.0001) {
			return Promise.resolve();
		}

		return new Promise<void>((resolve, reject) => {
			const onSeeked = () => {
				cleanup();
				resolve();
			};
			const onError = () => {
				cleanup();
				reject(new Error("Failed to seek media for speed-adjusted audio"));
			};
			const cleanup = () => {
				media.removeEventListener("seeked", onSeeked);
				media.removeEventListener("error", onError);
			};

			media.addEventListener("seeked", onSeeked, { once: true });
			media.addEventListener("error", onError, { once: true });
			media.currentTime = targetSec;
		});
	}

	private findActiveTrimRegion(
		currentTimeMs: number,
		trimRegions: TrimRegion[],
	): TrimRegion | null {
		return (
			trimRegions.find(
				(region) => currentTimeMs >= region.startMs && currentTimeMs < region.endMs,
			) || null
		);
	}

	private findActiveSpeedRegion(
		currentTimeMs: number,
		speedRegions: SpeedRegion[],
	): SpeedRegion | null {
		return (
			speedRegions.find(
				(region) => currentTimeMs >= region.startMs && currentTimeMs < region.endMs,
			) || null
		);
	}

	private cloneWithTimestamp(src: AudioData, newTimestamp: number): AudioData {
		const isPlanar = src.format?.includes("planar") ?? false;
		const numPlanes = isPlanar ? src.numberOfChannels : 1;

		let totalSize = 0;
		for (let planeIndex = 0; planeIndex < numPlanes; planeIndex++) {
			totalSize += src.allocationSize({ planeIndex });
		}

		const buffer = new ArrayBuffer(totalSize);
		let offset = 0;

		for (let planeIndex = 0; planeIndex < numPlanes; planeIndex++) {
			const planeSize = src.allocationSize({ planeIndex });
			src.copyTo(new Uint8Array(buffer, offset, planeSize), { planeIndex });
			offset += planeSize;
		}

		return new AudioData({
			format: src.format!,
			sampleRate: src.sampleRate,
			numberOfFrames: src.numberOfFrames,
			numberOfChannels: src.numberOfChannels,
			timestamp: newTimestamp,
			data: buffer,
		});
	}

	private createAudioDataFromBuffer(
		buffer: AudioBuffer,
		timestampUs: number,
		targetChannels: number,
	): AudioData {
		const numberOfChannels = Math.max(1, targetChannels);
		const numberOfFrames = buffer.length;
		const bytesPerSample = Float32Array.BYTES_PER_ELEMENT;
		const data = new ArrayBuffer(numberOfChannels * numberOfFrames * bytesPerSample);
		const sourceChannelCount = Math.max(1, buffer.numberOfChannels);

		for (let channelIndex = 0; channelIndex < numberOfChannels; channelIndex++) {
			const offset = channelIndex * numberOfFrames * bytesPerSample;
			const plane = new Float32Array(data, offset, numberOfFrames);
			const sourceChannelIndex = Math.min(channelIndex, sourceChannelCount - 1);
			plane.set(buffer.getChannelData(sourceChannelIndex));
		}

		return new AudioData({
			format: "f32-planar",
			sampleRate: buffer.sampleRate,
			numberOfFrames,
			numberOfChannels,
			timestamp: timestampUs,
			data,
		});
	}

	private isInTrimRegion(timestampMs: number, trims: TrimRegion[]) {
		return trims.some((trim) => timestampMs >= trim.startMs && timestampMs < trim.endMs);
	}

	private computeTrimOffset(timestampMs: number, trims: TrimRegion[]) {
		let offset = 0;
		for (const trim of trims) {
			if (trim.endMs <= timestampMs) {
				offset += trim.endMs - trim.startMs;
			}
		}
		return offset;
	}

	cancel() {
		this.cancelled = true;
	}
}
