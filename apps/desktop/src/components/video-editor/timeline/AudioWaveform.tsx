import { memo, useCallback, useEffect, useRef } from "react";
import { useTimelineContext } from "dnd-timeline";
import type { WaveformData } from "@/lib/audio/types";
import { WAVEFORM_COLOR, WAVEFORM_MUTED_COLOR } from "@/lib/audio/types";

interface AudioWaveformProps {
	waveformData: WaveformData | null;
	isLoading: boolean;
	audioMuted?: boolean;
}

/**
 * Canvas-based audio waveform renderer that synchronizes with the
 * dnd-timeline coordinate system for zoom/pan alignment.
 */
const AudioWaveform = memo(function AudioWaveform({
	waveformData,
	isLoading,
	audioMuted = false,
}: AudioWaveformProps) {
	const canvasRef = useRef<HTMLCanvasElement>(null);
	const rafRef = useRef<number | null>(null);
	const { range, sidebarWidth } = useTimelineContext();

	const draw = useCallback(() => {
		const canvas = canvasRef.current;
		if (!canvas) return;

		const ctx = canvas.getContext("2d");
		if (!ctx) return;

		const dpr = window.devicePixelRatio || 1;
		const rect = canvas.getBoundingClientRect();
		const displayWidth = rect.width;
		const displayHeight = rect.height;

		// Resize canvas buffer to match display at native resolution
		const bufferWidth = Math.round(displayWidth * dpr);
		const bufferHeight = Math.round(displayHeight * dpr);

		if (canvas.width !== bufferWidth || canvas.height !== bufferHeight) {
			canvas.width = bufferWidth;
			canvas.height = bufferHeight;
		}

		ctx.clearRect(0, 0, bufferWidth, bufferHeight);

		if (!waveformData || waveformData.peaks.length === 0) {
			return;
		}

		const { peaks, peaksPerSecond, duration } = waveformData;
		const rangeStartMs = range.start;
		const rangeEndMs = range.end;
		const rangeDurationMs = rangeEndMs - rangeStartMs;

		if (rangeDurationMs <= 0) return;

		const color = audioMuted ? WAVEFORM_MUTED_COLOR : WAVEFORM_COLOR;
		ctx.fillStyle = color;

		const centerY = bufferHeight / 2;

		// Draw one bar per pixel column
		for (let px = 0; px < bufferWidth; px++) {
			const timeMs = rangeStartMs + (px / bufferWidth) * rangeDurationMs;
			const timeSec = timeMs / 1000;

			if (timeSec < 0 || timeSec > duration) continue;

			const peakIndex = Math.floor(timeSec * peaksPerSecond);
			if (peakIndex < 0 || peakIndex >= peaks.length) continue;

			const amplitude = peaks[peakIndex];
			const barHeight = Math.max(1 * dpr, amplitude * centerY * 0.9);

			ctx.fillRect(
				px,
				centerY - barHeight,
				Math.max(1, dpr > 1 ? 1 : 1),
				barHeight * 2,
			);
		}
	}, [waveformData, range.start, range.end, audioMuted]);

	// Redraw on every range/data change via rAF to coalesce rapid updates
	useEffect(() => {
		if (rafRef.current !== null) {
			cancelAnimationFrame(rafRef.current);
		}
		rafRef.current = requestAnimationFrame(() => {
			draw();
			rafRef.current = null;
		});

		return () => {
			if (rafRef.current !== null) {
				cancelAnimationFrame(rafRef.current);
				rafRef.current = null;
			}
		};
	}, [draw]);

	// Handle resize
	useEffect(() => {
		const canvas = canvasRef.current;
		if (!canvas) return;

		const observer = new ResizeObserver(() => {
			if (rafRef.current !== null) {
				cancelAnimationFrame(rafRef.current);
			}
			rafRef.current = requestAnimationFrame(() => {
				draw();
				rafRef.current = null;
			});
		});

		observer.observe(canvas);
		return () => observer.disconnect();
	}, [draw]);

	return (
		<div
			className="relative w-full h-full"
			style={{ marginLeft: sidebarWidth }}
		>
			{isLoading && (
				<div className="absolute inset-0 flex items-center justify-center pointer-events-none select-none z-10">
					<div className="h-[2px] w-3/4 mx-4 bg-sky-400/20 rounded-full animate-pulse" />
				</div>
			)}
			<canvas
				ref={canvasRef}
				className="w-full h-full block"
				style={{ imageRendering: "pixelated" }}
			/>
		</div>
	);
});

export default AudioWaveform;
