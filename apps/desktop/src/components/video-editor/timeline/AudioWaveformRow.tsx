import { memo } from "react";
import type { WaveformData } from "@/lib/audio/types";
import { WAVEFORM_ROW_HEIGHT } from "@/lib/audio/types";
import AudioWaveform from "./AudioWaveform";

interface AudioWaveformRowProps {
	waveformData: WaveformData | null;
	isLoading: boolean;
	audioMuted?: boolean;
}

/**
 * Non-interactive timeline row that displays the audio waveform.
 * Styled to match the existing Row component but without dnd-timeline
 * drag/drop behavior since waveform display is read-only.
 */
const AudioWaveformRow = memo(function AudioWaveformRow({
	waveformData,
	isLoading,
	audioMuted,
}: AudioWaveformRowProps) {
	// Hide row entirely when there is no audio and not loading
	if (!isLoading && !waveformData) {
		return null;
	}

	return (
		<div
			className="border-b border-[#18181b] bg-[#18181b] relative"
			style={{ minHeight: WAVEFORM_ROW_HEIGHT, marginBottom: 4 }}
		>
			<div
				className="absolute left-1.5 top-1/2 -translate-y-1/2 text-[9px] font-semibold uppercase tracking-widest z-20 pointer-events-none select-none"
				style={{ color: "#666", writingMode: "horizontal-tb" }}
			>
				Audio
			</div>
			<AudioWaveform
				waveformData={waveformData}
				isLoading={isLoading}
				audioMuted={audioMuted}
			/>
		</div>
	);
});

export default AudioWaveformRow;
