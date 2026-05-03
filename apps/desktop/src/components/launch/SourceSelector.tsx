import { useAtom } from "jotai";
import { AppWindow, Loader2, Monitor } from "lucide-react";
import { useEffect } from "react";
import { MdCheck } from "react-icons/md";
import {
	selectedDesktopSourceAtom,
	sourceSelectorTabAtom,
	sourcesAtom,
	sourcesLoadingAtom,
	windowsLoadingAtom,
} from "@/atoms/sourceSelector";
import { flashSelectedScreen, getSources, selectSource } from "@/lib/backend";
import { cn } from "@/lib/utils";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "../ui/card";
import { Empty, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "../ui/empty";
import { Separator } from "../ui/separator";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../ui/tabs";
import { getSourceGridColumnClass } from "./sourceGridLayout";
import { type DesktopSource, mapSources, mergeSources } from "./sourceSelectorState";

interface SourceGridProps {
	sources: DesktopSource[];
	selectedSource: DesktopSource | null;
	onSelect: (source: DesktopSource) => void;
	type: "screen" | "window";
	emptyMessage: string;
}

function SourceGrid({ sources, selectedSource, onSelect, type, emptyMessage }: SourceGridProps) {
	if (sources.length === 0) {
		return (
			<Empty className="min-h-48 border-dashed bg-muted/30">
				<EmptyHeader>
					<EmptyMedia>{type === "screen" ? <Monitor /> : <AppWindow />}</EmptyMedia>
					<EmptyTitle>{emptyMessage}</EmptyTitle>
					<EmptyDescription>
						Try a different tab or make sure the source is visible.
					</EmptyDescription>
				</EmptyHeader>
			</Empty>
		);
	}

	const isWindow = type === "window";

	return (
		<div
			className={cn(
				"grid gap-2",
				isWindow ? "grid-cols-3" : getSourceGridColumnClass(type, sources.length),
			)}
		>
			{sources.map((source) => {
				const isSelected = selectedSource?.id === source.id;

				return (
					<button
						type="button"
						key={source.id}
						aria-pressed={isSelected}
						className={cn(
							"group rounded-lg border bg-card/80 text-left shadow-sm transition-all hover:-translate-y-0.5 hover:border-primary/40 hover:bg-accent/60 hover:shadow-md",
							isWindow ? "p-1.5" : "p-2",
							isSelected ? "border-primary ring-2 ring-primary/25" : "border-border/70",
						)}
						onClick={() => onSelect(source)}
					>
						<div
							className={cn(
								"relative overflow-hidden rounded-md bg-muted",
								isWindow ? "mb-1 aspect-[16/10]" : "mb-2 aspect-video",
							)}
						>
							{source.thumbnail ? (
								<img
									src={source.thumbnail}
									alt={source.name}
									className="h-full w-full object-cover"
								/>
							) : (
								<div className="flex h-full w-full items-center justify-center text-muted-foreground">
									{type === "screen" ? (
										<Monitor className={isWindow ? "h-4 w-4" : "h-5 w-5"} />
									) : source.appIcon ? (
										<img
											src={source.appIcon}
											alt=""
											className={cn("rounded-sm", isWindow ? "h-4 w-4" : "h-5 w-5")}
										/>
									) : (
										<AppWindow className={isWindow ? "h-4 w-4" : "h-5 w-5"} />
									)}
								</div>
							)}
							{isSelected && (
								<div className="absolute top-1 right-1 flex size-4 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-sm">
									<MdCheck className="h-2.5 w-2.5" />
								</div>
							)}
						</div>
						<div className="flex items-center gap-2">
							<p className={cn("truncate font-medium", isWindow ? "text-xs" : "text-sm")}>
								{source.name}
							</p>
							{isSelected ? (
								<Badge variant="secondary" className="ml-auto text-[10px]">
									Selected
								</Badge>
							) : null}
						</div>
					</button>
				);
			})}
		</div>
	);
}

export function SourceSelector() {
	const [sources, setSources] = useAtom(sourcesAtom);
	const [selectedSource, setSelectedSource] = useAtom(selectedDesktopSourceAtom);
	const [activeTab, setActiveTab] = useAtom(sourceSelectorTabAtom);
	const [loading, setLoading] = useAtom(sourcesLoadingAtom);
	const [windowsLoading, setWindowsLoading] = useAtom(windowsLoadingAtom);

	useEffect(() => {
		const params = new URLSearchParams(window.location.search);
		if (params.get("tab") === "windows") {
			setActiveTab("windows");
		}
	}, [setActiveTab]);

	useEffect(() => {
		let cancelled = false;

		async function fetchSources() {
			setLoading(true);
			try {
				const rawSources = await getSources({
					types: ["screen"],
					thumbnailSize: { width: 320, height: 180 },
				});
				if (!cancelled) {
					setSources(mapSources(rawSources));
				}
			} catch (error) {
				console.error("Error loading sources:", error);
			} finally {
				if (!cancelled) {
					setLoading(false);
				}
			}

			try {
				const windowSources = await getSources({
					types: ["window"],
					thumbnailSize: { width: 320, height: 180 },
				});

				if (!cancelled) {
					setSources((prev) => {
						const screens = prev.filter((source) => source.sourceType === "screen");
						return [...screens, ...mapSources(windowSources)];
					});
				}
			} catch (error) {
				console.error("Error loading window sources:", error);
			} finally {
				if (!cancelled) {
					setWindowsLoading(false);
				}
			}

			try {
				const previewScreens = await getSources({
					types: ["screen"],
					thumbnailSize: { width: 320, height: 180 },
					withThumbnails: true,
					timeoutMs: 4000,
				});

				if (!cancelled) {
					setSources((prev) => mergeSources(prev, mapSources(previewScreens)));
				}
			} catch (error) {
				console.error("Error loading screen previews:", error);
			}

			try {
				const previewWindows = await getSources({
					types: ["window"],
					thumbnailSize: { width: 320, height: 180 },
					withThumbnails: true,
					timeoutMs: 8000,
				});

				if (!cancelled) {
					setSources((prev) => mergeSources(prev, mapSources(previewWindows)));
				}
			} catch (error) {
				console.error("Error loading window previews:", error);
			}
		}

		void fetchSources();
		return () => {
			cancelled = true;
		};
	}, [setLoading, setSources, setWindowsLoading]);

	const screenSources = sources.filter((source) => source.sourceType === "screen");
	const windowSources = sources.filter((source) => source.sourceType === "window");

	useEffect(() => {
		if (loading) {
			return;
		}

		if (screenSources.length === 0 && windowSources.length > 0) {
			setActiveTab("windows");
			return;
		}

		if (windowSources.length === 0 && screenSources.length > 0) {
			setActiveTab("screens");
		}
	}, [loading, screenSources.length, windowSources.length, setActiveTab]);

	const handleSourceSelect = (source: DesktopSource) => {
		setSelectedSource(source);

		if (source.sourceType !== "screen") {
			return;
		}

		void flashSelectedScreen(source).catch((error) => {
			console.warn("Unable to flash selected screen border:", error);
		});
	};

	const handleShare = async () => {
		if (selectedSource) {
			await selectSource(selectedSource);
		}
	};

	if (loading) {
		return (
			<Card className="w-[520px] border-border/70 bg-background/95 shadow-2xl">
				<CardContent className="p-6">
					<Empty className="border-0 p-0">
						<EmptyHeader>
							<EmptyMedia>
								<Loader2 className="animate-spin" />
							</EmptyMedia>
							<EmptyTitle>Finding sources</EmptyTitle>
							<EmptyDescription>Collecting screens and open windows.</EmptyDescription>
						</EmptyHeader>
					</Empty>
				</CardContent>
			</Card>
		);
	}

	return (
		<Card className="w-[min(860px,calc(100vw-32px))] border-border/70 bg-background/95 shadow-2xl">
			<CardHeader className="p-4 pb-3">
				<div className="flex items-center justify-between gap-4">
					<div>
						<CardTitle className="text-lg">Choose what to share</CardTitle>
						<p className="mt-1 text-xs text-muted-foreground">
							Pick a screen or a single app window for the next recording.
						</p>
					</div>
					<Badge variant="outline">{screenSources.length + windowSources.length} sources</Badge>
				</div>
			</CardHeader>
			<CardContent className="p-4 pt-0">
				<Tabs
					value={activeTab}
					onValueChange={(value) => setActiveTab(value as "screens" | "windows")}
				>
					<TabsList className="grid w-full grid-cols-2">
						<TabsTrigger value="screens" className="gap-1.5">
							<Monitor data-icon="inline-start" />
							Screens
							<Badge variant="secondary" className="ml-1 text-[10px]">
								{screenSources.length}
							</Badge>
						</TabsTrigger>
						<TabsTrigger value="windows" className="gap-1.5">
							<AppWindow data-icon="inline-start" />
							Windows
							<Badge variant="secondary" className="ml-1 text-[10px]">
								{windowSources.length}
								{windowsLoading ? "..." : ""}
							</Badge>
						</TabsTrigger>
					</TabsList>

					<TabsContent value="screens" className="mt-3">
						<SourceGrid
							sources={screenSources}
							selectedSource={selectedSource}
							onSelect={handleSourceSelect}
							type="screen"
							emptyMessage="No screens available"
						/>
					</TabsContent>

					<TabsContent value="windows" className="mt-3">
						<SourceGrid
							sources={windowSources}
							selectedSource={selectedSource}
							onSelect={handleSourceSelect}
							type="window"
							emptyMessage="No windows available"
						/>
					</TabsContent>
				</Tabs>
			</CardContent>

			<Separator />
			<CardFooter className="flex justify-end gap-2 p-4">
				<Button variant="outline" onClick={() => window.close()}>
					Cancel
				</Button>
				<Button onClick={() => void handleShare()} disabled={!selectedSource}>
					Share Source
				</Button>
			</CardFooter>
		</Card>
	);
}
