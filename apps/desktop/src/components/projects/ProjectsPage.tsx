import { FolderOpen, Plus } from "lucide-react";
import { useCallback } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
	Empty,
	EmptyDescription,
	EmptyHeader,
	EmptyMedia,
	EmptyTitle,
} from "@/components/ui/empty";
import { Separator } from "@/components/ui/separator";
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
		<div className="min-h-0 flex-1 overflow-auto bg-background text-foreground">
			<div className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-8 py-8">
				<div className="flex items-end justify-between gap-4">
					<div>
						<div className="flex items-center gap-2">
							<h1 className="text-2xl font-semibold tracking-tight">Projects</h1>
							<Badge variant="secondary">Local</Badge>
						</div>
						<p className="mt-1 text-sm text-muted-foreground">
							Open a saved project or browse recordings from this device.
						</p>
					</div>
					<Button
						type="button"
						size="sm"
						onClick={handleOpenProject}
						className="h-8 gap-1.5 text-xs font-medium"
					>
						<Plus data-icon="inline-start" />
						Open project file
					</Button>
				</div>

				<div className="grid gap-4 md:grid-cols-2">
					<Card className="border-border/70 bg-card/80 shadow-xl shadow-black/10">
						<CardHeader className="p-5">
							<CardTitle className="flex items-center gap-2 text-base">
								<Plus className="size-4 text-primary" />
								Open project
							</CardTitle>
							<CardDescription>Load an Open Recorder editing session.</CardDescription>
						</CardHeader>
						<CardContent className="p-5 pt-0">
							<Button type="button" className="w-full" onClick={handleOpenProject}>
								<Plus data-icon="inline-start" />
								Choose file
							</Button>
						</CardContent>
					</Card>

					<Card className="border-border/70 bg-card/80 shadow-xl shadow-black/10">
						<CardHeader className="p-5">
							<CardTitle className="flex items-center gap-2 text-base">
								<FolderOpen className="size-4 text-primary" />
								Recordings folder
							</CardTitle>
							<CardDescription>Jump to saved captures and exported videos.</CardDescription>
						</CardHeader>
						<CardContent className="p-5 pt-0">
							<Button
								type="button"
								variant="outline"
								className="w-full"
								onClick={handleOpenRecordingsFolder}
							>
								<FolderOpen data-icon="inline-start" />
								Browse recordings
							</Button>
						</CardContent>
					</Card>
				</div>

				<Separator />

				<Empty className="max-w-none border-dashed bg-card/40">
					<EmptyHeader>
						<EmptyMedia className="size-16 border-primary/20 bg-primary/10 text-primary">
							<FolderOpen className="size-7" />
						</EmptyMedia>
						<EmptyTitle>No recent projects yet</EmptyTitle>
						<EmptyDescription>
							Recent project shortcuts will appear here after you save or open one.
						</EmptyDescription>
					</EmptyHeader>
					<div className="flex items-center justify-center gap-2">
						<Button type="button" variant="outline" size="sm" onClick={handleOpenProject}>
							<Plus data-icon="inline-start" />
							Open project
						</Button>
					</div>
				</Empty>
			</div>
		</div>
	);
}
