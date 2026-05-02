import { FolderOpen, Plus } from "lucide-react";
import { useCallback } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
	Empty,
	EmptyDescription,
	EmptyHeader,
	EmptyMedia,
	EmptyTitle,
} from "@/components/ui/empty";
import * as backend from "@/lib/backend";

interface ProjectsPageProps {
	onOpenProject: () => Promise<void>;
}

export function ProjectsPage({ onOpenProject }: ProjectsPageProps) {
	const handleOpenProject = useCallback(async () => {
		try {
			await onOpenProject();
		} catch (err) {
			toast.error(`Failed to open project: ${String(err)}`);
		}
	}, [onOpenProject]);

	const handleOpenRecordingsFolder = useCallback(async () => {
		try {
			await backend.openRecordingsFolder();
		} catch (err) {
			toast.error(`Failed to open recordings folder: ${String(err)}`);
		}
	}, []);

	return (
		<div className="flex-1 min-h-0 overflow-auto bg-[#09090b] text-slate-200">
			<div className="mx-auto w-full max-w-4xl px-8 py-10">
				<div className="flex items-end justify-between gap-4 mb-8">
					<div>
						<h1 className="text-2xl font-semibold tracking-tight text-white">Projects</h1>
						<p className="mt-1 text-sm text-white/60">
							Open a saved project or jump back into the editor.
						</p>
					</div>
					<Button
						type="button"
						size="sm"
						onClick={handleOpenProject}
						className="h-8 gap-1.5 bg-[#2563EB] text-white text-xs font-medium hover:bg-[#2563EB]/90"
					>
						<Plus className="h-3.5 w-3.5" />
						Open project file
					</Button>
				</div>

				<Empty className="max-w-none border-white/10 bg-white/[0.02]">
					<EmptyHeader>
						<EmptyMedia className="size-16 border-[#2563EB]/20 bg-[#2563EB]/10 text-[#93c5fd]">
							<FolderOpen className="size-7" />
						</EmptyMedia>
						<EmptyTitle>No recent projects yet</EmptyTitle>
						<EmptyDescription>
							Load a saved project file, or open your recordings folder to browse existing captures.
						</EmptyDescription>
					</EmptyHeader>
					<div className="flex items-center justify-center gap-2">
						<Button
							type="button"
							variant="outline"
							size="sm"
							onClick={handleOpenProject}
							className="h-8 gap-1.5 border-white/10 bg-white/5 text-xs text-white hover:bg-white/10"
						>
							<Plus className="h-3.5 w-3.5" />
							Open project
						</Button>
						<Button
							type="button"
							variant="outline"
							size="sm"
							onClick={handleOpenRecordingsFolder}
							className="h-8 gap-1.5 border-white/10 bg-white/5 text-xs text-white hover:bg-white/10"
						>
							<FolderOpen className="h-3.5 w-3.5" />
							Browse recordings
						</Button>
					</div>
				</Empty>
			</div>
		</div>
	);
}
