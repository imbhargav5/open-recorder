import { Clock3, FileVideo, FolderOpen, Plus } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
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
	onOpenProjectPath: (path: string) => Promise<void>;
}

function formatProjectDate(value: string): string {
	const date = new Date(value);
	if (Number.isNaN(date.getTime())) return "Unknown";
	return new Intl.DateTimeFormat(undefined, {
		month: "short",
		day: "numeric",
		hour: "numeric",
		minute: "2-digit",
	}).format(date);
}

function basename(filePath: string): string {
	return filePath.split(/[\\/]/).pop() || filePath;
}

export function ProjectsPage({ onOpenProject, onOpenProjectPath }: ProjectsPageProps) {
	const [projects, setProjects] = useState<backend.ProjectListItem[]>([]);
	const [loading, setLoading] = useState(true);

	const refreshProjects = useCallback(async () => {
		try {
			setLoading(true);
			setProjects(await backend.listProjects());
		} catch (err) {
			toast.error(`Failed to load projects: ${String(err)}`);
		} finally {
			setLoading(false);
		}
	}, []);

	useEffect(() => {
		void refreshProjects();
	}, [refreshProjects]);

	const handleOpenProject = useCallback(async () => {
		try {
			await onOpenProject();
			await refreshProjects();
		} catch (err) {
			toast.error(`Failed to open project: ${String(err)}`);
		}
	}, [onOpenProject, refreshProjects]);

	const handleOpenIndexedProject = useCallback(
		async (project: backend.ProjectListItem) => {
			if (project.missing) return;
			await onOpenProjectPath(project.path);
			await refreshProjects();
		},
		[onOpenProjectPath, refreshProjects],
	);

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

				{projects.length > 0 ? (
					<div className="flex flex-col gap-3">
						<div className="flex items-center justify-between gap-3">
							<h2 className="text-sm font-medium text-muted-foreground">Recent projects</h2>
							<Button type="button" variant="ghost" size="sm" onClick={refreshProjects}>
								Refresh
							</Button>
						</div>
						<div className="overflow-hidden rounded-lg border border-border/70 bg-card/70">
							{projects.map((project) => (
								<button
									type="button"
									key={project.path}
									disabled={project.missing}
									onClick={() => void handleOpenIndexedProject(project)}
									className="flex w-full items-center gap-3 border-border/70 border-b px-4 py-3 text-left transition-colors last:border-b-0 hover:bg-muted/60 disabled:cursor-not-allowed disabled:opacity-55"
								>
									<div className="flex size-10 shrink-0 items-center justify-center rounded-md border border-primary/20 bg-primary/10 text-primary">
										<FileVideo className="size-5" />
									</div>
									<div className="min-w-0 flex-1">
										<div className="flex min-w-0 items-center gap-2">
											<span className="truncate text-sm font-medium">{project.title}</span>
											{project.missing ? (
												<Badge variant="outline" className="text-destructive">
													Missing
												</Badge>
											) : null}
										</div>
										<div className="mt-1 flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
											<span className="truncate">
												{project.sourceName ?? basename(project.recordingPath ?? project.path)}
											</span>
											<span className="inline-flex items-center gap-1">
												<Clock3 className="size-3" />
												{formatProjectDate(project.lastOpenedAt)}
											</span>
										</div>
									</div>
									<span className="hidden max-w-60 truncate text-xs text-muted-foreground md:block">
										{project.path}
									</span>
								</button>
							))}
						</div>
					</div>
				) : (
					<Empty className="max-w-none border-dashed bg-card/40">
						<EmptyHeader>
							<EmptyMedia className="size-16 border-primary/20 bg-primary/10 text-primary">
								<FolderOpen className="size-7" />
							</EmptyMedia>
							<EmptyTitle>{loading ? "Loading projects" : "No recent projects yet"}</EmptyTitle>
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
				)}
			</div>
		</div>
	);
}
