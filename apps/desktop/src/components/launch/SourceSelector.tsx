import { getCurrentWindow } from "@tauri-apps/api/window";
import { AppWindow, CheckCircle2, Loader2, Monitor } from "lucide-react";
import { useEffect, useState } from "react";
import { MdCheck } from "react-icons/md";
import { flashSelectedScreen, getSources, selectSource } from "@/lib/backend";
import { cn } from "@/lib/utils";
import { Button } from "../ui/button";
import { Card } from "../ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../ui/tabs";
import styles from "./SourceSelector.module.css";
import { getSourceGridColumnClass } from "./sourceGridLayout";

interface DesktopSource {
	id: string;
	name: string;
	thumbnail: string | null;
	display_id: string;
	appIcon: string | null;
	originalName: string;
	sourceType: "screen" | "window";
	appName?: string;
	windowTitle?: string;
	windowId?: number;
}

interface SourceGridProps {
	sources: DesktopSource[];
	selectedSource: DesktopSource | null;
	onSelect: (source: DesktopSource) => void;
	type: "screen" | "window";
	emptyMessage: string;
}

function mapSources(rawSources: ProcessedDesktopSource[]): DesktopSource[] {
	return rawSources.map((source) => {
		const metadata = parseSourceMetadata(source);

		return {
			id: source.id,
			name: metadata.displayName,
			thumbnail: source.thumbnail ?? null,
			display_id: source.display_id ?? source.displayId ?? "",
			appIcon: source.appIcon ?? source.app_icon ?? null,
			originalName: source.name,
			sourceType: metadata.sourceType,
			appName: metadata.appName,
			windowTitle: metadata.windowTitle,
			windowId: source.windowId ?? source.window_id,
		};
	});
}

function mergeSources(
	existingSources: DesktopSource[],
	incomingSources: DesktopSource[],
): DesktopSource[] {
	const incomingById = new Map(incomingSources.map((source) => [source.id, source]));
	const mergedSources = existingSources.map((source) => {
		const incoming = incomingById.get(source.id);
		if (!incoming) return source;
		return {
			...source,
			...incoming,
			thumbnail: incoming.thumbnail ?? source.thumbnail,
			appIcon: incoming.appIcon ?? source.appIcon,
		};
	});

	for (const source of incomingSources) {
		if (!existingSources.some((existing) => existing.id === source.id)) {
			mergedSources.push(source);
		}
	}

	return mergedSources;
}

function parseSourceMetadata(source: ProcessedDesktopSource) {
	const sourceType: "screen" | "window" =
		source.sourceType ??
		(source.source_type as "screen" | "window" | undefined) ??
		(source.id.startsWith("window:") ? "window" : "screen");

	const appName = source.appName ?? source.app_name;
	const windowTitle = source.windowTitle ?? source.window_title;

	if (sourceType === "window" && (appName || windowTitle)) {
		return {
			sourceType,
			appName,
			windowTitle: windowTitle ?? source.name,
			displayName: windowTitle ?? source.name,
		};
	}

	if (sourceType === "window") {
		const [appNamePart, ...windowTitleParts] = source.name.split(" — ");
		const parsedAppName = appNamePart?.trim() || undefined;
		const parsedWindowTitle = windowTitleParts.join(" — ").trim() || source.name.trim();

		return {
			sourceType,
			appName: parsedAppName,
			windowTitle: parsedWindowTitle,
			displayName: parsedWindowTitle,
		};
	}

	return {
		sourceType,
		appName: undefined,
		windowTitle: undefined,
		displayName: source.name,
	};
}

function SourceGrid({ sources, selectedSource, onSelect, type, emptyMessage }: SourceGridProps) {
	if (sources.length === 0) {
		return (
			<div className={styles.emptyState}>
				<div className={styles.emptyIcon}>
					{type === "screen" ? <Monitor className="h-4 w-4" /> : <AppWindow className="h-4 w-4" />}
				</div>
				<div className="space-y-1 text-center">
					<p className="text-sm font-medium text-white/80">{emptyMessage}</p>
					<p className="text-xs text-white/40">
						{type === "screen"
							? "Try reconnecting a display or reopening the picker."
							: "Only visible windows can be shared."}
					</p>
				</div>
			</div>
		);
	}

	return (
		<div
			className={cn(
				"grid gap-3 pr-1",
				getSourceGridColumnClass(type, sources.length),
				styles.sourceGridScroll,
			)}
		>
			{sources.map((source) => {
				const isSelected = selectedSource?.id === source.id;
				const subtitle =
					type === "screen"
						? source.display_id
							? `Display ${source.display_id}`
							: "Entire display"
						: (source.appName ?? "Window");

				return (
					<Card
						key={source.id}
						className={cn(styles.sourceCard, isSelected && styles.selected)}
						onClick={() => onSelect(source)}
					>
						<div className={styles.previewShell}>
							{source.thumbnail ? (
								<img src={source.thumbnail} alt={source.name} className={styles.previewImage} />
							) : (
								<div className={styles.previewPlaceholder}>
									<div className={styles.previewPlaceholderIcon}>
										{type === "screen" ? (
											<Monitor className="h-4 w-4" />
										) : source.appIcon ? (
											<img src={source.appIcon} alt="" className="h-4 w-4 rounded-sm" />
										) : (
											<AppWindow className="h-4 w-4" />
										)}
									</div>
									<span className={styles.previewLabel}>
										{type === "screen" ? "Display" : "Window"}
									</span>
								</div>
							)}
							<div className={styles.previewOverlay} />
							<div className={styles.sourceBadge}>{type === "screen" ? "Screen" : "Window"}</div>
							{isSelected && (
								<div className={styles.selectedBadge}>
									<MdCheck className="h-3.5 w-3.5" />
								</div>
							)}
						</div>

						<div className="space-y-1">
							<div className="flex items-start gap-2">
								{type === "window" && source.appIcon ? (
									<img
										src={source.appIcon}
										alt=""
										className="mt-0.5 h-4 w-4 rounded-sm opacity-90"
									/>
								) : (
									<div className={styles.titleIcon}>
										{type === "screen" ? (
											<Monitor className="h-3.5 w-3.5" />
										) : (
											<AppWindow className="h-3.5 w-3.5" />
										)}
									</div>
								)}
								<div className="min-w-0 flex-1">
									<div className={styles.sourceName}>{source.name}</div>
									<div className={styles.sourceMeta}>{subtitle}</div>
								</div>
							</div>
						</div>
					</Card>
				);
			})}
		</div>
	);
}

export function SourceSelector() {
	const [sources, setSources] = useState<DesktopSource[]>([]);
	const [selectedSource, setSelectedSource] = useState<DesktopSource | null>(null);
	const [activeTab, setActiveTab] = useState<"screens" | "windows">("screens");
	const [loading, setLoading] = useState(true);
	const [windowsLoading, setWindowsLoading] = useState(true);

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
	}, []);

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
	}, [loading, screenSources.length, windowSources.length]);

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
			<div className="min-h-screen flex items-center justify-center px-5 py-6">
				<div className={styles.loadingPanel}>
					<div className="flex h-11 w-11 items-center justify-center rounded-2xl border border-white/10 bg-white/5">
						<Loader2 className="h-5 w-5 animate-spin text-[#7fb3ff]" />
					</div>
					<div className="space-y-1 text-center">
						<p className="text-sm font-semibold text-white">Finding shareable sources</p>
						<p className="text-xs text-white/50">
							Loading displays first, then live window previews.
						</p>
					</div>
				</div>
			</div>
		);
	}

	return (
		<div className="min-h-screen flex items-center justify-center px-5 py-6">
			<div className={styles.panel}>
				<div className={styles.panelHeader}>
					<div className="space-y-1">
						<p className={styles.eyebrow}>Source Picker</p>
						<h1 className="text-lg font-semibold tracking-tight text-white">
							Choose what to share
						</h1>
						<p className="text-sm text-white/50">
							Pick a full display or switch to a single app window.
						</p>
					</div>
					<div className={styles.statusPill}>
						<CheckCircle2 className="h-3.5 w-3.5 text-[#8dc2ff]" />
						<span>{selectedSource ? "1 selected" : "Nothing selected"}</span>
					</div>
				</div>

				<Tabs
					value={activeTab}
					onValueChange={(value) => setActiveTab(value as "screens" | "windows")}
					className="flex min-h-0 flex-1 flex-col"
				>
					<div className="flex items-center justify-between gap-3">
						<TabsList className={styles.tabsList}>
							<TabsTrigger value="screens" className={styles.tabsTrigger}>
								<Monitor className="h-3.5 w-3.5" />
								<span>Screens</span>
								<span className={styles.triggerCount}>{screenSources.length}</span>
							</TabsTrigger>
							<TabsTrigger value="windows" className={styles.tabsTrigger}>
								<AppWindow className="h-3.5 w-3.5" />
								<span>Windows</span>
								<span className={styles.triggerCount}>
									{windowSources.length}
									{windowsLoading ? "…" : ""}
								</span>
							</TabsTrigger>
						</TabsList>

						<div className="hidden sm:block text-xs text-white/40">Visible windows only</div>
					</div>

					<TabsContent value="screens" className={styles.tabContent}>
						<SourceGrid
							sources={screenSources}
							selectedSource={selectedSource}
							onSelect={handleSourceSelect}
							type="screen"
							emptyMessage="No screens available"
						/>
					</TabsContent>

					<TabsContent value="windows" className={styles.tabContent}>
						<div className="mb-3 rounded-xl border border-white/8 bg-white/[0.03] px-3 py-2 text-xs text-white/45">
							Only visible, non-minimized windows can be recorded.
						</div>
						<SourceGrid
							sources={windowSources}
							selectedSource={selectedSource}
							onSelect={handleSourceSelect}
							type="window"
							emptyMessage="No windows available"
						/>
					</TabsContent>
				</Tabs>

				<div className={styles.footer}>
					<div className="min-w-0">
						<p className="text-xs font-medium uppercase tracking-[0.18em] text-white/35">
							Selected
						</p>
						<p className="truncate text-sm font-medium text-white/80">
							{selectedSource ? selectedSource.name : "Choose a source to enable sharing"}
						</p>
					</div>

					<div className="flex items-center gap-2">
						<Button
							variant="outline"
							onClick={() => getCurrentWindow().close()}
							className={styles.cancelButton}
						>
							Cancel
						</Button>
						<Button
							onClick={() => void handleShare()}
							disabled={!selectedSource}
							className={styles.shareButton}
						>
							Share Source
						</Button>
					</div>
				</div>
			</div>
		</div>
	);
}
