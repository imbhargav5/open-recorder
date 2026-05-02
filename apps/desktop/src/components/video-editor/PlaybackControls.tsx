import { Pause, Play } from "lucide-react";
import { memo } from "react";
import { Slider } from "@/components/ui/slider";
import { cn } from "@/lib/utils";
import { Button } from "../ui/button";
import { type TimeStore, useTimeValue } from "./useTimeStore";

interface PlaybackControlsProps {
	isPlaying: boolean;
	timeStore: TimeStore;
	duration: number;
	onTogglePlayPause: () => void;
	onSeek: (time: number) => void;
}

function PlaybackControls({
	isPlaying,
	timeStore,
	duration,
	onTogglePlayPause,
	onSeek,
}: PlaybackControlsProps) {
	console.log("render <PlaybackControls>");
	const currentTime = useTimeValue(timeStore);

	function formatTime(seconds: number) {
		if (!isFinite(seconds) || isNaN(seconds) || seconds < 0) return "0:00";
		const mins = Math.floor(seconds / 60);
		const secs = Math.floor(seconds % 60);
		return `${mins}:${secs.toString().padStart(2, "0")}`;
	}

	return (
		<div className="flex items-center gap-2 px-1 py-0.5 rounded-full bg-black/60 backdrop-blur-md border border-white/10 shadow-xl transition-all duration-300 hover:bg-black/70 hover:border-white/20">
			<Button
				onClick={onTogglePlayPause}
				size="icon"
				className={cn(
					"w-8 h-8 rounded-full transition-all duration-200 border border-white/10",
					isPlaying
						? "bg-white/10 text-white hover:bg-white/20"
						: "bg-white text-black hover:bg-white/90 hover:scale-105 shadow-[0_0_15px_rgba(255,255,255,0.3)]",
				)}
				aria-label={isPlaying ? "Pause" : "Play"}
			>
				{isPlaying ? (
					<Pause className="w-3.5 h-3.5 fill-current" />
				) : (
					<Play className="w-3.5 h-3.5 fill-current ml-0.5" />
				)}
			</Button>

			<span className="text-[9px] font-medium text-slate-300 tabular-nums w-[30px] text-right">
				{formatTime(currentTime)}
			</span>

			<Slider
				aria-label="Playback position"
				value={[currentTime]}
				onValueChange={([value]) => onSeek(value)}
				min={0}
				max={duration || 100}
				step={0.01}
				className="flex-1"
			/>

			<span className="text-[9px] font-medium text-slate-500 tabular-nums w-[30px]">
				{formatTime(duration)}
			</span>
		</div>
	);
}

export default memo(PlaybackControls);
