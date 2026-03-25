import { useEffect, useRef, useState } from "react";
import type { WaveformData } from "@/lib/audio/types";
import { extractWaveformData } from "@/lib/audio/waveformExtractor";

interface UseWaveformDataResult {
	waveformData: WaveformData | null;
	isLoading: boolean;
	error: string | null;
}

/**
 * React hook that extracts waveform peak data from a video file's audio track.
 * Caches the result per videoPath so re-renders don't re-extract.
 * Automatically cancels extraction if videoPath changes before completion.
 */
export function useWaveformData(
	videoPath: string | null,
	duration: number,
): UseWaveformDataResult {
	const [waveformData, setWaveformData] = useState<WaveformData | null>(null);
	const [isLoading, setIsLoading] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const cacheRef = useRef<Map<string, WaveformData>>(new Map());

	useEffect(() => {
		if (!videoPath || duration <= 0) {
			setWaveformData(null);
			setIsLoading(false);
			setError(null);
			return;
		}

		// Check cache first
		const cached = cacheRef.current.get(videoPath);
		if (cached) {
			setWaveformData(cached);
			setIsLoading(false);
			setError(null);
			return;
		}

		const abortController = new AbortController();
		setIsLoading(true);
		setError(null);

		extractWaveformData(videoPath, { signal: abortController.signal })
			.then((data) => {
				if (abortController.signal.aborted) return;

				if (data) {
					cacheRef.current.set(videoPath, data);
				}
				setWaveformData(data);
				setIsLoading(false);
			})
			.catch((err) => {
				if (abortController.signal.aborted) return;

				console.warn("[useWaveformData] Extraction failed:", err);
				setError(err instanceof Error ? err.message : String(err));
				setIsLoading(false);
			});

		return () => {
			abortController.abort();
		};
	}, [videoPath, duration]);

	return { waveformData, isLoading, error };
}
