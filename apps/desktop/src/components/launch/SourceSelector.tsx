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
import { Button } from "../ui/button";
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
			<div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-border bg-muted/50 py-12">
				{type === "screen" ? (
					<Monitor className="h-5 w-5 text-muted-foreground" />
				) : (
					<AppWindow className="h-5 w-5 text-muted-foreground" />
				)}
				<p className="text-sm text-muted-foreground">{emptyMessage}</p>
			</div>
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
						className={cn(
							"rounded-lg border bg-card text-left transition-colors hover:bg-accent",
							isWindow ? "p-1.5" : "p-2",
							isSelected ? "border-primary ring-2 ring-primary/30" : "border-border",
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
								<div className="absolute top-1 right-1 flex h-4 w-4 items-center justify-center rounded-full bg-primary text-primary-foreground">
									<MdCheck className="h-2.5 w-2.5" />
								</div>
							)}
						</div>
						<p className={cn("truncate font-medium", isWindow ? "text-xs" : "text-sm")}>
							{source.name}
						</p>
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
			<div className="rounded-2xl border border-border bg-background p-6 shadow-xl">
				<div className="flex flex-col items-center gap-3">
					<Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
					<p className="text-sm text-muted-foreground">Finding sources...</p>
				</div>
			</div>
		);
	}

	return (
		<div className="rounded-2xl border border-border bg-background p-4 shadow-xl">
			<h1 className="mb-4 text-lg font-semibold">Choose what to share</h1>

			<Tabs
				value={activeTab}
				onValueChange={(value) => setActiveTab(value as "screens" | "windows")}
			>
				<TabsList>
					<TabsTrigger value="screens" className="gap-1.5">
						<Monitor className="h-3.5 w-3.5" />
						Screens
						<span className="ml-0.5 rounded-full bg-foreground/10 px-1.5 py-0.5 text-xs leading-none">
							{screenSources.length}
						</span>
					</TabsTrigger>
					<TabsTrigger value="windows" className="gap-1.5">
						<AppWindow className="h-3.5 w-3.5" />
						Windows
						<span className="ml-0.5 rounded-full bg-foreground/10 px-1.5 py-0.5 text-xs leading-none">
							{windowSources.length}
							{windowsLoading ? "..." : ""}
						</span>
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

			<div className="mt-4 flex justify-end gap-2 border-t border-border pt-4">
				<Button variant="outline" onClick={() => window.close()}>
					Cancel
				</Button>
				<Button onClick={() => void handleShare()} disabled={!selectedSource}>
					Share Source
				</Button>
			</div>
		</div>
	);
}
