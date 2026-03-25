/**
 * Waveform data extracted from a video/audio file.
 * Peaks are normalized 0..1 amplitude values sampled at a fixed resolution.
 */
export interface WaveformData {
	/** Number of peak samples per second of audio. */
	peaksPerSecond: number;
	/** Total audio duration in seconds. */
	duration: number;
	/** Peak amplitude values (0..1), one per sample bucket. */
	peaks: Float32Array;
	/** Original sample rate of the audio stream. */
	sampleRate: number;
	/** Number of audio channels. */
	channelCount: number;
	/** Source video path this data was extracted from. */
	sourcePath: string;
}

/** Default number of peak amplitude samples per second of audio. */
export const DEFAULT_PEAKS_PER_SECOND = 100;

/** Waveform visual configuration. */
export const WAVEFORM_COLOR = "rgba(56, 189, 248, 0.6)";
export const WAVEFORM_MUTED_COLOR = "rgba(100, 116, 139, 0.3)";
export const WAVEFORM_ROW_HEIGHT = 44;
