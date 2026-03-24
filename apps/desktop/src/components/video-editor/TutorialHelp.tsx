import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
    DialogTrigger,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { HelpCircle, Scissors, ArrowRight } from "lucide-react";

export function TutorialHelp() {
    return (
        <Dialog>
            <DialogTrigger asChild>
                <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 px-2 text-xs text-slate-400 hover:text-slate-200 hover:bg-white/10 transition-all gap-1.5"
                >
                    <HelpCircle className="w-3.5 h-3.5" />
                    <span className="font-medium">How trimming works</span>
                </Button>
            </DialogTrigger>
            <DialogContent className="max-w-2xl bg-[#09090b] border-white/10 [&>button]:text-slate-400 [&>button:hover]:text-white">
                <DialogHeader>
                    <DialogTitle className="text-xl font-semibold text-slate-200 flex items-center gap-2">
                        <Scissors className="w-5 h-5 text-[#ef4444]" /> How Trimming Works
                    </DialogTitle>
                    <DialogDescription className="text-slate-400">
                        Understanding how to cut out unwanted parts of your video.
                    </DialogDescription>
                </DialogHeader>
                <div className="mt-4 space-y-8">
                    {/* Explanation */}
                    <div className="bg-white/5 rounded-lg p-4 border border-white/5">
                        <p className="text-slate-300 leading-relaxed">
                            The Trim tool works by defining the segments you want to
                            <span className="text-[#ef4444] font-bold"> remove</span>. Any part
                            of the timeline that is
                            <span className="text-[#ef4444] font-bold"> covered</span> by a red
                            trim segment will be cut out when you export.
                        </p>
                    </div>
                    {/* Visual Illustration */}
                    <div className="space-y-2">
                        <h3 className="text-sm font-medium text-slate-400 uppercase tracking-wider">
                            Visual Example
                        </h3>
                        <div className="relative h-24 bg-[#000] rounded-lg border border-white/10 flex items-center px-4 overflow-hidden select-none">
                            {/* Background track (Kept parts) */}
                            <div className="absolute inset-x-4 h-2 bg-slate-600 rounded-full overflow-hidden">
                                {/* Solid line representing video */}
                            </div>
                            {/* Removed Segment 1 */}
                            <div
                                className="absolute left-[20%] h-8 bg-[#ef4444]/20 border border-[#ef4444] rounded flex flex-col items-center justify-center z-10"
                                style={{ width: "20%" }}
                            >
                                <span className="text-[10px] font-bold text-[#ef4444] bg-black/50 px-1 rounded">
                                    REMOVED
                                </span>
                            </div>
                            {/* Removed Segment 2 */}
                            <div
                                className="absolute left-[65%] h-8 bg-[#ef4444]/20 border border-[#ef4444] rounded flex flex-col items-center justify-center z-10"
                                style={{ width: "15%" }}
                            >
                                <span className="text-[10px] font-bold text-[#ef4444] bg-black/50 px-1 rounded">
                                    REMOVED
                                </span>
                            </div>
                            {/* Labels for kept parts */}
                            <div className="absolute left-[5%] text-[10px] text-slate-400 font-medium">
                                Kept
                            </div>
                            <div className="absolute left-[50%] text-[10px] text-slate-400 font-medium">
                                Kept
                            </div>
                            <div className="absolute left-[90%] text-[10px] text-slate-400 font-medium">
                                Kept
                            </div>
                        </div>
                        <div className="flex justify-center mt-2">

                            <ArrowRight className="w-4 h-4 text-slate-600 rotate-90" />
                        </div>
                        {/* Result */}
                        <div className="relative h-12 bg-[#000] rounded-lg border border-white/10 flex items-center justify-center gap-1 px-4 select-none">
                            <div
                                className="h-8 bg-slate-700 rounded flex items-center justify-center opacity-80"
                                style={{ width: "30%" }}
                            >
                                <span className="text-[10px] text-white font-medium">
                                    Part 1
                                </span>
                            </div>
                            <div
                                className="h-8 bg-slate-700 rounded flex items-center justify-center opacity-80"
                                style={{ width: "30%" }}
                            >
                                <span className="text-[10px] text-white font-medium">
                                    Part 2
                                </span>
                            </div>
                            <div
                                className="h-8 bg-slate-700 rounded flex items-center justify-center opacity-80"
                                style={{ width: "30%" }}
                            >
                                <span className="text-[10px] text-white font-medium">
                                    Part 3
                                </span>
                            </div>
                            <span className="absolute right-4 text-xs text-slate-400">
                                Final Video
                            </span>
                        </div>
                    </div>
                    {/* Steps */}
                    <div className="grid grid-cols-2 gap-4">
                        <div className="p-3 rounded bg-white/5 border border-white/5">
                            <div className="text-[#ef4444] font-bold mb-1">
                                1. Add Trim
                            </div>
                            <p className="text-xs text-slate-400">
                                Press
                                <kbd className="bg-white/10 px-1 rounded text-slate-300">T</kbd>
                                or click the scissors icon to mark a section for removal.
                            </p>
                        </div>
                        <div className="p-3 rounded bg-white/5 border border-white/5">
                            <div className="text-[#ef4444] font-bold mb-1">
                                2. Adjust
                            </div>
                            <p className="text-xs text-slate-400">
                                Drag the edges of the red region to cover exactly what you want
                                to cut out.
                            </p>
                        </div>
                    </div>
                </div>
            </DialogContent>
        </Dialog>
    );
}

