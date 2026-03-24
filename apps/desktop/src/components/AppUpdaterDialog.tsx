import { CheckCircle2, Download, LoaderCircle, RefreshCw, TriangleAlert } from "lucide-react";
import { useEffect, useRef } from "react";
import { Button } from "@/components/ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@/components/ui/dialog";
import { useAppUpdater } from "@/hooks/useAppUpdater";

type AppUpdaterDialogProps = {
	enableAutoCheck?: boolean;
};

function ProgressBar({ progress }: { progress: number }) {
	return (
		<div className="space-y-2">
			<div className="h-2 overflow-hidden rounded-full bg-white/10">
				<div
					className="h-full rounded-full bg-[#2563EB] transition-[width] duration-300"
					style={{ width: `${Math.max(0, Math.min(progress, 100))}%` }}
				/>
			</div>
			<p className="text-xs text-slate-400">{progress}% downloaded</p>
		</div>
	);
}

export function AppUpdaterDialog({ enableAutoCheck = true }: AppUpdaterDialogProps) {
	const {
		status,
		isDialogOpen,
		isBlocking,
		version,
		releaseNotes,
		downloadProgress,
		error,
		checkForUpdate,
		downloadAndInstall,
		restartApp,
		dismiss,
	} = useAppUpdater({ enableAutoCheck });
	const contentRef = useRef<HTMLDivElement | null>(null);

	useEffect(() => {
		if (!isBlocking) {
			return;
		}

		const handleKeyEvent = (event: KeyboardEvent) => {
			if (
				contentRef.current &&
				event.target instanceof Node &&
				contentRef.current.contains(event.target)
			) {
				return;
			}

			event.preventDefault();
			event.stopPropagation();
		};

		window.addEventListener("keydown", handleKeyEvent, { capture: true });
		window.addEventListener("keyup", handleKeyEvent, { capture: true });

		return () => {
			window.removeEventListener("keydown", handleKeyEvent, { capture: true });
			window.removeEventListener("keyup", handleKeyEvent, { capture: true });
		};
	}, [isBlocking]);

	const canDismiss = !isBlocking;

	return (
		<Dialog
			open={isDialogOpen}
			onOpenChange={(open) => {
				if (!open && canDismiss) {
					dismiss();
				}
			}}
		>
			<DialogContent
				ref={contentRef}
				showCloseButton={canDismiss}
				className="max-w-[520px] border-white/10 bg-[#09090b] text-white shadow-2xl shadow-black/50"
				onEscapeKeyDown={(event) => {
					if (!canDismiss) {
						event.preventDefault();
					}
				}}
				onInteractOutside={(event) => {
					if (!canDismiss) {
						event.preventDefault();
					}
				}}
			>
				{status === "checking" ? (
					<>
						<DialogHeader>
							<DialogTitle className="flex items-center gap-2 text-base">
								<LoaderCircle className="h-5 w-5 animate-spin text-[#2563EB]" />
								Checking for updates
							</DialogTitle>
							<DialogDescription className="text-slate-400">
								Looking for the latest Open Recorder release.
							</DialogDescription>
						</DialogHeader>
						<p className="rounded-lg border border-[#2563EB]/20 bg-[#2563EB]/10 px-4 py-3 text-sm text-slate-200">
							Please wait while the app checks for a new version.
						</p>
					</>
				) : null}

				{status === "up-to-date" ? (
					<>
						<DialogHeader>
							<DialogTitle className="flex items-center gap-2 text-base">
								<CheckCircle2 className="h-5 w-5 text-emerald-400" />
								Open Recorder is up to date
							</DialogTitle>
							<DialogDescription className="text-slate-400">
								You already have the latest available version installed.
							</DialogDescription>
						</DialogHeader>
						<DialogFooter>
							<Button onClick={dismiss} className="bg-[#2563EB] text-white hover:bg-[#1d4ed8]">
								Close
							</Button>
						</DialogFooter>
					</>
				) : null}

				{status === "available" ? (
					<>
						<DialogHeader>
							<DialogTitle className="flex items-center gap-2 text-base">
								<Download className="h-5 w-5 text-[#2563EB]" />
								Update available{version ? `: v${version}` : ""}
							</DialogTitle>
							<DialogDescription className="text-slate-400">
								A newer version of Open Recorder is ready to install.
							</DialogDescription>
						</DialogHeader>
						{releaseNotes ? (
							<div className="max-h-56 overflow-y-auto rounded-lg border border-white/10 bg-white/5 p-4 text-sm text-slate-300 whitespace-pre-wrap">
								{releaseNotes}
							</div>
						) : (
							<p className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-sm text-slate-300">
								The update will download in the background and prompt you to restart when it is
								ready.
							</p>
						)}
						<DialogFooter>
							<Button variant="ghost" onClick={dismiss}>
								Later
							</Button>
							<Button
								onClick={() => {
									void downloadAndInstall();
								}}
								className="bg-[#2563EB] text-white hover:bg-[#1d4ed8]"
							>
								Install update
							</Button>
						</DialogFooter>
					</>
				) : null}

				{status === "downloading" ? (
					<>
						<DialogHeader>
							<DialogTitle className="flex items-center gap-2 text-base">
								<RefreshCw className="h-5 w-5 animate-spin text-[#2563EB]" />
								Updating Open Recorder
							</DialogTitle>
							<DialogDescription className="text-slate-400">
								Downloading and installing{version ? ` v${version}` : " the latest release"}.
							</DialogDescription>
						</DialogHeader>
						<ProgressBar progress={downloadProgress} />
						<p className="rounded-lg border border-amber-500/20 bg-amber-500/10 px-4 py-3 text-sm text-amber-200">
							Other actions are temporarily disabled until the update finishes.
						</p>
					</>
				) : null}

				{status === "ready" ? (
					<>
						<DialogHeader>
							<DialogTitle className="flex items-center gap-2 text-base">
								<CheckCircle2 className="h-5 w-5 text-emerald-400" />
								Update ready to restart
							</DialogTitle>
							<DialogDescription className="text-slate-400">
								Open Recorder needs to restart to finish applying the update.
							</DialogDescription>
						</DialogHeader>
						<DialogFooter>
							<Button variant="ghost" onClick={dismiss}>
								Later
							</Button>
							<Button
								onClick={() => {
									void restartApp();
								}}
								className="bg-[#2563EB] text-white hover:bg-[#1d4ed8]"
							>
								Restart now
							</Button>
						</DialogFooter>
					</>
				) : null}

				{status === "error" ? (
					<>
						<DialogHeader>
							<DialogTitle className="flex items-center gap-2 text-base">
								<TriangleAlert className="h-5 w-5 text-rose-400" />
								Update failed
							</DialogTitle>
							<DialogDescription className="text-slate-400">
								Open Recorder could not complete the update.
							</DialogDescription>
						</DialogHeader>
						<p className="rounded-lg border border-rose-500/20 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
							{error ?? "An unexpected error occurred while updating."}
						</p>
						<DialogFooter>
							<Button variant="ghost" onClick={dismiss}>
								Close
							</Button>
							<Button
								onClick={() => {
									void checkForUpdate({ showDialog: true });
								}}
								className="bg-[#2563EB] text-white hover:bg-[#1d4ed8]"
							>
								Try again
							</Button>
						</DialogFooter>
					</>
				) : null}
			</DialogContent>
		</Dialog>
	);
}
