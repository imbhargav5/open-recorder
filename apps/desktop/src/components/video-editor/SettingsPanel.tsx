import Block from "@uiw/react-color-block";
import { useAtom } from "jotai";
import {
	Bug,
	Camera,
	Crop,
	Gauge,
	type LucideIcon,
	MousePointer2,
	Palette,
	Scissors,
	SlidersHorizontal,
	Star,
	Trash2,
	Upload,
	Volume2,
	X,
	ZoomIn,
} from "lucide-react";
import { memo, type ReactNode, useMemo, useRef } from "react";
import { toast } from "sonner";
import {
	type SettingsSidebarTab,
	settingsActiveTabAtom,
	settingsBackgroundTabAtom,
	settingsCustomImagesAtom,
	settingsGradientAtom,
	settingsSelectedColorAtom,
	settingsShowCropModalAtom,
} from "@/atoms/settingsPanel";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@/components/ui/select";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { openExternalUrl } from "@/lib/backend";
import {
	createDefaultFacecamSettings,
	FACECAM_ANCHORS,
	type FacecamAnchor,
	type FacecamSettings,
} from "@/lib/recordingSession";
import { cn } from "@/lib/utils";
import { BUILT_IN_WALLPAPERS, type BuiltInWallpaper, WALLPAPER_PATHS } from "@/lib/wallpapers";
import { type AspectRatio } from "@/utils/aspectRatioUtils";
import { AnnotationSettingsPanel } from "./AnnotationSettingsPanel";
import { CropControl } from "./CropControl";
import type {
	AnnotationRegion,
	AnnotationType,
	CropRegion,
	FigureData,
	PlaybackSpeed,
	ZoomDepth,
	ZoomEaseType,
	ZoomEasing,
} from "./types";
import { DEFAULT_ZOOM_EASE_IN, DEFAULT_ZOOM_EASE_OUT, SPEED_OPTIONS } from "./types";

const GRADIENTS = [
	"linear-gradient( 111.6deg,  rgba(114,167,232,1) 9.4%, rgba(253,129,82,1) 43.9%, rgba(253,129,82,1) 54.8%, rgba(249,202,86,1) 86.3% )",
	"linear-gradient(120deg, #d4fc79 0%, #96e6a1 100%)",
	"radial-gradient( circle farthest-corner at 3.2% 49.6%,  rgba(80,12,139,0.87) 0%, rgba(161,10,144,0.72) 83.6% )",
	"linear-gradient( 111.6deg,  rgba(0,56,68,1) 0%, rgba(163,217,185,1) 51.5%, rgba(231, 148, 6, 1) 88.6% )",
	"linear-gradient( 107.7deg,  rgba(235,230,44,0.55) 8.4%, rgba(252,152,15,1) 90.3% )",
	"linear-gradient( 91deg,  rgba(72,154,78,1) 5.2%, rgba(251,206,70,1) 95.9% )",
	"radial-gradient( circle farthest-corner at 10% 20%,  rgba(2,37,78,1) 0%, rgba(4,56,126,1) 19.7%, rgba(85,245,221,1) 100.2% )",
	"linear-gradient( 109.6deg,  rgba(15,2,2,1) 11.2%, rgba(36,163,190,1) 91.1% )",
	"linear-gradient(135deg, #FBC8B4, #2447B1)",
	"linear-gradient(109.6deg, #F635A6, #36D860)",
	"linear-gradient(90deg, #FF0101, #4DFF01)",
	"linear-gradient(315deg, #EC0101, #5044A9)",
	"linear-gradient(45deg, #ff9a9e 0%, #fad0c4 99%, #fad0c4 100%)",
	"linear-gradient(to top, #a18cd1 0%, #fbc2eb 100%)",
	"linear-gradient(to right, #ff8177 0%, #ff867a 0%, #ff8c7f 21%, #f99185 52%, #cf556c 78%, #b12a5b 100%)",
	"linear-gradient(120deg, #84fab0 0%, #8fd3f4 100%)",
	"linear-gradient(to right, #4facfe 0%, #00f2fe 100%)",
	"linear-gradient(to top, #fcc5e4 0%, #fda34b 15%, #ff7882 35%, #c8699e 52%, #7046aa 71%, #0c1db8 87%, #020f75 100%)",
	"linear-gradient(to right, #fa709a 0%, #fee140 100%)",
	"linear-gradient(to top, #30cfd0 0%, #330867 100%)",
	"linear-gradient(to top, #c471f5 0%, #fa71cd 100%)",
	"linear-gradient(to right, #f78ca0 0%, #f9748f 19%, #fd868c 60%, #fe9a8b 100%)",
	"linear-gradient(to top, #48c6ef 0%, #6f86d6 100%)",
	"linear-gradient(to right, #0acffe 0%, #495aff 100%)",
];

const COLOR_PALETTE = [
	"#FF0000",
	"#FFD700",
	"#00FF00",
	"#FFFFFF",
	"#0000FF",
	"#FF6B00",
	"#9B59B6",
	"#E91E63",
	"#00BCD4",
	"#FF5722",
	"#8BC34A",
	"#FFC107",
	"#2563EB",
	"#000000",
	"#607D8B",
	"#795548",
];

type SettingsTabDefinition = {
	id: SettingsSidebarTab;
	label: string;
	description: string;
	icon: LucideIcon;
};

const SETTINGS_SIDEBAR_TABS: SettingsTabDefinition[] = [
	{
		id: "appearance",
		label: "Appearance",
		description: "Frame styling, background, crop, and composition.",
		icon: SlidersHorizontal,
	},
	{
		id: "cursor",
		label: "Cursor",
		description: "Cursor visibility and motion effects.",
		icon: MousePointer2,
	},
	{
		id: "camera",
		label: "Camera",
		description: "Facecam overlay settings.",
		icon: Camera,
	},
	{
		id: "audio",
		label: "Audio",
		description: "Master preview and MP4 export audio.",
		icon: Volume2,
	},
];

interface SettingsPanelProps {
	selected: string;
	onWallpaperChange: (path: string) => void;
	audioMuted?: boolean;
	onAudioMutedChange?: (muted: boolean) => void;
	audioVolume?: number;
	onAudioVolumeChange?: (volume: number) => void;
	selectedZoomDepth?: ZoomDepth | null;
	onZoomDepthChange?: (depth: ZoomDepth) => void;
	selectedZoomEaseIn?: ZoomEasing | null;
	selectedZoomEaseOut?: ZoomEasing | null;
	onZoomEaseChange?: (side: "easeIn" | "easeOut", patch: Partial<ZoomEasing>) => void;
	selectedZoomId?: string | null;
	onZoomDelete?: (id: string) => void;
	selectedTrimId?: string | null;
	onTrimDelete?: (id: string) => void;
	shadowIntensity?: number;
	onShadowChange?: (intensity: number) => void;
	backgroundBlur?: number;
	onBackgroundBlurChange?: (amount: number) => void;
	zoomMotionBlur?: number;
	onZoomMotionBlurChange?: (amount: number) => void;
	connectZooms?: boolean;
	onConnectZoomsChange?: (enabled: boolean) => void;
	showCursor?: boolean;
	onShowCursorChange?: (enabled: boolean) => void;
	loopCursor?: boolean;
	onLoopCursorChange?: (enabled: boolean) => void;
	cursorSize?: number;
	onCursorSizeChange?: (size: number) => void;
	cursorSmoothing?: number;
	onCursorSmoothingChange?: (smoothing: number) => void;
	cursorMotionBlur?: number;
	onCursorMotionBlurChange?: (amount: number) => void;
	cursorClickBounce?: number;
	onCursorClickBounceChange?: (amount: number) => void;
	borderRadius?: number;
	onBorderRadiusChange?: (radius: number) => void;
	padding?: number;
	onPaddingChange?: (padding: number) => void;
	cropRegion?: CropRegion;
	onCropChange?: (region: CropRegion) => void;
	facecamVideoPath?: string | null;
	facecamSettings?: FacecamSettings;
	onFacecamSettingsChange?: (settings: FacecamSettings) => void;
	aspectRatio: AspectRatio;
	videoElement?: HTMLVideoElement | null;
	selectedAnnotationId?: string | null;
	annotationRegions?: AnnotationRegion[];
	onAnnotationContentChange?: (id: string, content: string) => void;
	onAnnotationTypeChange?: (id: string, type: AnnotationType) => void;
	onAnnotationStyleChange?: (id: string, style: Partial<AnnotationRegion["style"]>) => void;
	onAnnotationFigureDataChange?: (id: string, figureData: FigureData) => void;
	onAnnotationDelete?: (id: string) => void;
	selectedSpeedId?: string | null;
	selectedSpeedValue?: PlaybackSpeed | null;
	onSpeedChange?: (speed: PlaybackSpeed) => void;
	onSpeedDelete?: (id: string) => void;
}

const ZOOM_DEPTH_OPTIONS: Array<{ depth: ZoomDepth; label: string }> = [
	{ depth: 1, label: "1.25×" },
	{ depth: 2, label: "1.5×" },
	{ depth: 3, label: "1.8×" },
	{ depth: 4, label: "2.2×" },
	{ depth: 5, label: "3.5×" },
	{ depth: 6, label: "5×" },
];

const ZOOM_EASE_OPTIONS: Array<{ type: ZoomEaseType; label: string }> = [
	{ type: "smooth", label: "Smooth" },
	{ type: "linear", label: "Linear" },
	{ type: "ease-in", label: "Ease In" },
	{ type: "ease-out", label: "Ease Out" },
	{ type: "ease-in-out", label: "Ease In-Out" },
];

function formatZoomEaseDurationSeconds(durationMs: number) {
	return (durationMs / 1000).toFixed(3).replace(/\.?0+$/, "");
}

function parseZoomEaseDurationMs(value: string) {
	const seconds = Number.parseFloat(value);
	if (!Number.isFinite(seconds)) {
		return null;
	}

	return Math.round(Math.max(0, Math.min(5, seconds)) * 1000);
}

const normalizeWallpaperValue = (value: string) =>
	value.replace(/^file:\/\//, "").replace(/^\//, "");

function isBuiltInWallpaperSelected(selectedValue: string, wallpaper: BuiltInWallpaper) {
	const normalizedSelected = normalizeWallpaperValue(selectedValue);

	return [wallpaper.publicPath, wallpaper.relativePath, wallpaper.thumbnailPublicPath].some(
		(candidate) => {
			const normalizedCandidate = normalizeWallpaperValue(candidate);
			return (
				normalizedSelected === normalizedCandidate ||
				normalizedSelected.endsWith(normalizedCandidate) ||
				normalizedCandidate.endsWith(normalizedSelected)
			);
		},
	);
}

type WallpaperPreviewTileProps = {
	label: string;
	previewSrc: string;
	isSelected: boolean;
	onSelect: () => void;
	children?: ReactNode;
};

function WallpaperPreviewTile({
	label,
	previewSrc,
	isSelected,
	onSelect,
	children,
}: WallpaperPreviewTileProps) {
	return (
		<div
			className={cn(
				"aspect-square w-9 h-9 rounded-md border-2 overflow-hidden cursor-pointer transition-all duration-200 relative shadow-sm group",
				isSelected
					? "border-[#2563EB] ring-1 ring-[#2563EB]/30"
					: "border-white/10 hover:border-[#2563EB]/40 opacity-80 hover:opacity-100 bg-white/5",
			)}
			aria-label={label}
			title={label}
			onClick={onSelect}
			role="button"
		>
			<img
				src={previewSrc}
				alt={label}
				loading="lazy"
				decoding="async"
				draggable={false}
				className="pointer-events-none h-full w-full object-cover"
			/>
			{children}
		</div>
	);
}

function SettingsPanelInner({
	selected,
	onWallpaperChange,
	audioMuted = false,
	onAudioMutedChange,
	audioVolume = 1,
	onAudioVolumeChange,
	selectedZoomDepth,
	onZoomDepthChange,
	selectedZoomEaseIn,
	selectedZoomEaseOut,
	onZoomEaseChange,
	selectedZoomId,
	onZoomDelete,
	selectedTrimId,
	onTrimDelete,
	shadowIntensity = 0,
	onShadowChange,
	backgroundBlur = 0,
	onBackgroundBlurChange,
	zoomMotionBlur = 0,
	onZoomMotionBlurChange,
	connectZooms = true,
	onConnectZoomsChange,
	showCursor = false,
	onShowCursorChange,
	loopCursor = false,
	onLoopCursorChange,
	cursorSize = 5,
	onCursorSizeChange,
	cursorSmoothing = 2,
	onCursorSmoothingChange,
	cursorMotionBlur = 0.35,
	onCursorMotionBlurChange,
	cursorClickBounce = 1,
	onCursorClickBounceChange,
	borderRadius = 12.5,
	onBorderRadiusChange,
	padding = 50,
	onPaddingChange,
	cropRegion,
	onCropChange,
	facecamVideoPath,
	facecamSettings = createDefaultFacecamSettings(false),
	onFacecamSettingsChange,
	aspectRatio,
	videoElement,
	selectedAnnotationId,
	annotationRegions = [],
	onAnnotationContentChange,
	onAnnotationTypeChange,
	onAnnotationStyleChange,
	onAnnotationFigureDataChange,
	onAnnotationDelete,
	selectedSpeedId,
	selectedSpeedValue,
	onSpeedChange,
	onSpeedDelete,
}: SettingsPanelProps) {
	const [activeTab, setActiveTab] = useAtom(settingsActiveTabAtom);
	const [backgroundTab, setBackgroundTab] = useAtom(settingsBackgroundTabAtom);
	const [customImages, setCustomImages] = useAtom(settingsCustomImagesAtom);
	const fileInputRef = useRef<HTMLInputElement>(null);
	const [selectedColor, setSelectedColor] = useAtom(settingsSelectedColorAtom);
	const [gradient, setGradient] = useAtom(settingsGradientAtom);
	const [showCropModal, setShowCropModal] = useAtom(settingsShowCropModalAtom);
	const cropSnapshotRef = useRef<CropRegion | null>(null);
	const activeTabDefinition = useMemo(
		() => SETTINGS_SIDEBAR_TABS.find((tab) => tab.id === activeTab) ?? SETTINGS_SIDEBAR_TABS[0],
		[activeTab],
	);

	const zoomEnabled = Boolean(selectedZoomDepth);
	const trimEnabled = Boolean(selectedTrimId);
	const facecamAvailable = Boolean(facecamVideoPath);

	const updateFacecamSettings = (next: Partial<FacecamSettings>) => {
		onFacecamSettingsChange?.({
			...facecamSettings,
			...next,
		});
	};

	const handleDeleteClick = () => {
		if (selectedZoomId && onZoomDelete) {
			onZoomDelete(selectedZoomId);
		}
	};

	const handleTrimDeleteClick = () => {
		if (selectedTrimId && onTrimDelete) {
			onTrimDelete(selectedTrimId);
		}
	};

	const renderZoomEaseControl = (label: string, side: "easeIn" | "easeOut", easing: ZoomEasing) => (
		<div className="rounded-lg border border-white/5 bg-white/5 p-2">
			<div className="mb-2 text-[10px] font-medium text-slate-300">{label}</div>
			<div className="grid grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)] gap-2">
				<div>
					<div className="mb-1 text-[9px] uppercase tracking-wide text-slate-500">Duration</div>
					<Input
						aria-label={`${label} duration`}
						type="number"
						inputMode="decimal"
						min={0}
						max={5}
						step={0.05}
						value={formatZoomEaseDurationSeconds(easing.durationMs)}
						onChange={(event) => {
							const durationMs = parseZoomEaseDurationMs(event.target.value);
							if (durationMs !== null) {
								onZoomEaseChange?.(side, { durationMs });
							}
						}}
						className="h-8 rounded-md border-white/10 bg-black/20 px-2 text-xs text-slate-100 ring-offset-0 focus-visible:ring-1 focus-visible:ring-[#2563EB] focus-visible:ring-offset-0"
					/>
				</div>
				<div>
					<div className="mb-1 text-[9px] uppercase tracking-wide text-slate-500">Ease Type</div>
					<Select
						value={easing.type}
						onValueChange={(value) => onZoomEaseChange?.(side, { type: value as ZoomEaseType })}
					>
						<SelectTrigger
							aria-label={`${label} type`}
							className="h-8 rounded-md border-white/10 bg-black/20 px-2 text-xs text-slate-100 ring-offset-0 focus:ring-1 focus:ring-[#2563EB] focus:ring-offset-0"
						>
							<SelectValue />
						</SelectTrigger>
						<SelectContent className="z-[10000] border-white/10 bg-[#1a1a1c] text-slate-200">
							{ZOOM_EASE_OPTIONS.map((option) => (
								<SelectItem key={option.type} value={option.type}>
									{option.label}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				</div>
			</div>
		</div>
	);

	const handleCropToggle = () => {
		if (!showCropModal && cropRegion) {
			cropSnapshotRef.current = { ...cropRegion };
		}
		setShowCropModal(!showCropModal);
	};

	const handleCropCancel = () => {
		if (cropSnapshotRef.current && onCropChange) {
			onCropChange(cropSnapshotRef.current);
		}
		setShowCropModal(false);
	};

	const handleImageUpload = (event: React.ChangeEvent<HTMLInputElement>) => {
		const files = event.target.files;
		if (!files || files.length === 0) return;

		const file = files[0];

		// Validate file type - only allow JPG/JPEG
		const validTypes = ["image/jpeg", "image/jpg"];
		if (!validTypes.includes(file.type)) {
			toast.error("Invalid file type", {
				description: "Please upload a JPG or JPEG image file.",
			});
			event.target.value = "";
			return;
		}

		const reader = new FileReader();

		reader.onload = (e) => {
			const dataUrl = e.target?.result as string;
			if (dataUrl) {
				setCustomImages((prev) => [...prev, dataUrl]);
				onWallpaperChange(dataUrl);
				toast.success("Custom image uploaded successfully!");
			}
		};

		reader.onerror = () => {
			toast.error("Failed to upload image", {
				description: "There was an error reading the file.",
			});
		};

		reader.readAsDataURL(file);
		// Reset input so the same file can be selected again
		event.target.value = "";
	};

	const handleRemoveCustomImage = (imageUrl: string, event: React.MouseEvent) => {
		event.stopPropagation();
		setCustomImages((prev) => prev.filter((img) => img !== imageUrl));
		// If the removed image was selected, clear selection
		if (selected === imageUrl) {
			onWallpaperChange(WALLPAPER_PATHS[0]);
		}
	};

	// Find selected annotation
	const selectedAnnotation = selectedAnnotationId
		? annotationRegions.find((a) => a.id === selectedAnnotationId)
		: null;

	// If an annotation is selected, show annotation settings instead
	if (
		selectedAnnotation &&
		onAnnotationContentChange &&
		onAnnotationTypeChange &&
		onAnnotationStyleChange &&
		onAnnotationDelete
	) {
		return (
			<AnnotationSettingsPanel
				annotation={selectedAnnotation}
				onContentChange={(content) => onAnnotationContentChange(selectedAnnotation.id, content)}
				onTypeChange={(type) => onAnnotationTypeChange(selectedAnnotation.id, type)}
				onStyleChange={(style) => onAnnotationStyleChange(selectedAnnotation.id, style)}
				onFigureDataChange={
					onAnnotationFigureDataChange
						? (figureData) => onAnnotationFigureDataChange(selectedAnnotation.id, figureData)
						: undefined
				}
				onDelete={() => onAnnotationDelete(selectedAnnotation.id)}
			/>
		);
	}

	if (zoomEnabled) {
		return (
			<div className="flex-[2] min-w-0 bg-[#09090b] border border-white/5 rounded-2xl p-4 flex flex-col shadow-xl h-full overflow-y-auto custom-scrollbar">
				<div className="mb-6">
					<div className="flex items-center justify-between mb-4">
						<div className="flex items-center gap-2">
							<ZoomIn className="h-4 w-4 text-[#2563EB]" />
							<span className="text-sm font-medium text-slate-200">Zoom Settings</span>
						</div>
						{selectedZoomDepth && (
							<span className="text-[10px] uppercase tracking-wider font-medium text-[#2563EB] bg-[#2563EB]/10 px-2 py-1 rounded-full">
								{ZOOM_DEPTH_OPTIONS.find((option) => option.depth === selectedZoomDepth)?.label}
							</span>
						)}
					</div>
					<ToggleGroup
						type="single"
						value={String(selectedZoomDepth)}
						onValueChange={(value) => {
							const nextDepth = Number(value) as ZoomDepth;
							if (ZOOM_DEPTH_OPTIONS.some((option) => option.depth === nextDepth)) {
								onZoomDepthChange?.(nextDepth);
							}
						}}
						className="mb-3 grid grid-cols-6 rounded-lg border border-white/5 bg-white/5 p-1"
					>
						{ZOOM_DEPTH_OPTIONS.map((option) => (
							<ToggleGroupItem
								key={option.depth}
								value={String(option.depth)}
								className="h-8 text-xs"
							>
								{option.label}
							</ToggleGroupItem>
						))}
					</ToggleGroup>
					<div className="mb-3 grid grid-cols-1 gap-2">
						{renderZoomEaseControl("Ease In", "easeIn", selectedZoomEaseIn ?? DEFAULT_ZOOM_EASE_IN)}
						{renderZoomEaseControl(
							"Ease Out",
							"easeOut",
							selectedZoomEaseOut ?? DEFAULT_ZOOM_EASE_OUT,
						)}
					</div>
					<div className="grid grid-cols-2 gap-2 mb-3">
						<div className="p-2 rounded-lg bg-white/5 border border-white/5">
							<div className="flex items-center justify-between mb-1">
								<div className="text-[10px] font-medium text-slate-300">Motion Blur</div>
								<span className="text-[10px] text-slate-500 font-mono">
									{zoomMotionBlur.toFixed(2)}×
								</span>
							</div>
							<Slider
								value={[zoomMotionBlur]}
								onValueChange={(values) => onZoomMotionBlurChange?.(values[0])}
								min={0}
								max={2}
								step={0.05}
								className="w-full"
							/>
						</div>
						<div className="flex items-center justify-between p-2 rounded-lg bg-white/5 border border-white/5">
							<div className="text-[10px] font-medium text-slate-300">Connect Zooms</div>
							<Switch
								checked={connectZooms}
								onCheckedChange={onConnectZoomsChange}
								className="data-[state=checked]:bg-[#2563EB] scale-90"
							/>
						</div>
					</div>
					<Button
						onClick={handleDeleteClick}
						variant="destructive"
						size="sm"
						className="mt-3 w-full gap-2 bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20 hover:border-red-500/30 transition-all h-8 text-xs"
					>
						<Trash2 className="w-3 h-3" />
						Delete Zoom
					</Button>
				</div>
			</div>
		);
	}

	if (trimEnabled) {
		return (
			<div className="flex-[2] min-w-0 bg-[#09090b] border border-white/5 rounded-2xl p-4 flex flex-col shadow-xl h-full overflow-y-auto custom-scrollbar">
				<div className="mb-6">
					<div className="flex items-center justify-between mb-4">
						<div className="flex items-center gap-2">
							<Scissors className="h-4 w-4 text-red-400" />
							<span className="text-sm font-medium text-slate-200">Trim Settings</span>
						</div>
						<span className="text-[10px] uppercase tracking-wider font-medium text-red-400 bg-red-500/10 px-2 py-1 rounded-full">
							Active
						</span>
					</div>
					<Button
						onClick={handleTrimDeleteClick}
						variant="destructive"
						size="sm"
						className="w-full gap-2 bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20 hover:border-red-500/30 transition-all h-8 text-xs"
					>
						<Trash2 className="w-3 h-3" />
						Delete Trim Region
					</Button>
				</div>
			</div>
		);
	}

	if (selectedSpeedId) {
		return (
			<div className="flex-[2] min-w-0 bg-[#09090b] border border-white/5 rounded-2xl p-4 flex flex-col shadow-xl h-full overflow-y-auto custom-scrollbar">
				<div className="mb-6">
					<div className="flex items-center justify-between mb-4">
						<div className="flex items-center gap-2">
							<Gauge className="h-4 w-4 text-[#d97706]" />
							<span className="text-sm font-medium text-slate-200">Speed Settings</span>
						</div>
						{selectedSpeedValue && (
							<span className="text-[10px] uppercase tracking-wider font-medium text-[#d97706] bg-[#d97706]/10 px-2 py-1 rounded-full">
								{SPEED_OPTIONS.find((option) => option.speed === selectedSpeedValue)?.label ??
									`${selectedSpeedValue}×`}
							</span>
						)}
					</div>
					<ToggleGroup
						type="single"
						value={selectedSpeedValue ? String(selectedSpeedValue) : undefined}
						onValueChange={(value) => {
							const nextSpeed = Number(value) as PlaybackSpeed;
							if (SPEED_OPTIONS.some((option) => option.speed === nextSpeed)) {
								onSpeedChange?.(nextSpeed);
							}
						}}
						className="mb-3 grid grid-cols-7 rounded-lg border border-white/5 bg-white/5 p-1"
					>
						{SPEED_OPTIONS.map((option) => (
							<ToggleGroupItem
								key={option.speed}
								value={String(option.speed)}
								className="h-8 text-xs"
							>
								{option.label}
							</ToggleGroupItem>
						))}
					</ToggleGroup>
					<Button
						onClick={() => onSpeedDelete?.(selectedSpeedId)}
						variant="destructive"
						size="sm"
						className="mt-3 w-full gap-2 bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20 hover:border-red-500/30 transition-all h-8 text-xs"
					>
						<Trash2 className="w-3 h-3" />
						Delete Speed Region
					</Button>
				</div>
			</div>
		);
	}

	const ActiveTabIcon = activeTabDefinition.icon;

	const renderBackgroundControls = () => (
		<Tabs
			value={backgroundTab}
			onValueChange={(value) => setBackgroundTab(value as typeof backgroundTab)}
			className="w-full"
		>
			<TabsList className="mb-2 bg-white/5 border border-white/5 p-0.5 w-full grid grid-cols-3 h-7 rounded-lg">
				<TabsTrigger
					value="image"
					className="data-[state=active]:bg-[#2563EB] data-[state=active]:text-white text-slate-400 text-[10px] py-1 rounded-md transition-all"
				>
					Image
				</TabsTrigger>
				<TabsTrigger
					value="color"
					className="data-[state=active]:bg-[#2563EB] data-[state=active]:text-white text-slate-400 text-[10px] py-1 rounded-md transition-all"
				>
					Color
				</TabsTrigger>
				<TabsTrigger
					value="gradient"
					className="data-[state=active]:bg-[#2563EB] data-[state=active]:text-white text-slate-400 text-[10px] py-1 rounded-md transition-all"
				>
					Gradient
				</TabsTrigger>
			</TabsList>

			<div className="max-h-[min(200px,25vh)] overflow-y-auto custom-scrollbar">
				<TabsContent value="image" className="mt-0 space-y-2">
					<input
						type="file"
						ref={fileInputRef}
						onChange={handleImageUpload}
						accept=".jpg,.jpeg,image/jpeg"
						className="hidden"
					/>
					<Button
						onClick={() => fileInputRef.current?.click()}
						variant="outline"
						className="w-full gap-2 bg-white/5 text-slate-200 border-white/10 hover:bg-[#2563EB] hover:text-white hover:border-[#2563EB] transition-all h-7 text-[10px]"
					>
						<Upload className="w-3 h-3" />
						Upload Custom
					</Button>

					<div className="grid grid-cols-7 gap-1.5">
						{customImages.map((imageUrl, idx) => {
							const isSelected = selected === imageUrl;
							return (
								<WallpaperPreviewTile
									key={`custom-${idx}`}
									label={`Custom wallpaper ${idx + 1}`}
									previewSrc={imageUrl}
									isSelected={isSelected}
									onSelect={() => onWallpaperChange(imageUrl)}
								>
									<button
										type="button"
										onClick={(e) => handleRemoveCustomImage(imageUrl, e)}
										className="absolute top-0.5 right-0.5 w-3 h-3 bg-red-500/90 hover:bg-red-500 rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity z-10"
									>
										<X className="w-2 h-2 text-white" />
									</button>
								</WallpaperPreviewTile>
							);
						})}

						{BUILT_IN_WALLPAPERS.map((wallpaper) => (
							<WallpaperPreviewTile
								key={wallpaper.id}
								label={wallpaper.label}
								previewSrc={wallpaper.thumbnailPublicPath}
								isSelected={Boolean(selected) && isBuiltInWallpaperSelected(selected, wallpaper)}
								onSelect={() => onWallpaperChange(wallpaper.publicPath)}
							/>
						))}
					</div>
				</TabsContent>

				<TabsContent value="color" className="mt-0">
					<div className="p-1">
						<Block
							color={selectedColor}
							colors={COLOR_PALETTE}
							onChange={(color) => {
								setSelectedColor(color.hex);
								onWallpaperChange(color.hex);
							}}
							style={{
								width: "100%",
								borderRadius: "8px",
							}}
						/>
					</div>
				</TabsContent>

				<TabsContent value="gradient" className="mt-0">
					<div className="grid grid-cols-7 gap-1.5">
						{GRADIENTS.map((currentGradient, idx) => (
							<div
								key={currentGradient}
								className={cn(
									"aspect-square w-9 h-9 rounded-md border-2 overflow-hidden cursor-pointer transition-all duration-200 shadow-sm",
									gradient === currentGradient
										? "border-[#2563EB] ring-1 ring-[#2563EB]/30"
										: "border-white/10 hover:border-[#2563EB]/40 opacity-80 hover:opacity-100 bg-white/5",
								)}
								style={{ background: currentGradient }}
								aria-label={`Gradient ${idx + 1}`}
								onClick={() => {
									setGradient(currentGradient);
									onWallpaperChange(currentGradient);
								}}
								role="button"
							/>
						))}
					</div>
				</TabsContent>
			</div>
		</Tabs>
	);

	const renderSelectedTabContent = () => {
		switch (activeTabDefinition.id) {
			case "appearance":
				return (
					<div className="space-y-3">
						<div className="grid grid-cols-1 gap-2">
							<div className="p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="flex items-center justify-between mb-1">
									<div className="text-[10px] font-medium text-slate-300">Shadow</div>
									<span className="text-[10px] text-slate-500 font-mono">
										{Math.round(shadowIntensity * 100)}%
									</span>
								</div>
								<Slider
									value={[shadowIntensity]}
									onValueChange={(values) => onShadowChange?.(values[0])}
									min={0}
									max={1}
									step={0.01}
									className="w-full"
								/>
							</div>
							<div className="p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="flex items-center justify-between mb-1">
									<div className="text-[10px] font-medium text-slate-300">Roundness</div>
									<span className="text-[10px] text-slate-500 font-mono">{borderRadius}px</span>
								</div>
								<Slider
									value={[borderRadius]}
									onValueChange={(values) => onBorderRadiusChange?.(values[0])}
									min={0}
									max={25}
									step={0.5}
									className="w-full"
								/>
							</div>
						</div>
						<div className="grid grid-cols-1 gap-2">
							<div className="p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="flex items-center justify-between mb-1">
									<div className="text-[10px] font-medium text-slate-300">Padding</div>
									<span className="text-[10px] text-slate-500 font-mono">{padding}%</span>
								</div>
								<Slider
									value={[padding]}
									onValueChange={(values) => onPaddingChange?.(values[0])}
									min={0}
									max={100}
									step={1}
									className="w-full"
								/>
							</div>
							<div className="p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="flex items-center justify-between mb-1">
									<div className="text-[10px] font-medium text-slate-300">Background Blur</div>
									<span className="text-[10px] text-slate-500 font-mono">
										{backgroundBlur.toFixed(1)}px
									</span>
								</div>
								<Slider
									value={[backgroundBlur]}
									onValueChange={(values) => onBackgroundBlurChange?.(values[0])}
									min={0}
									max={8}
									step={0.25}
									className="w-full"
								/>
							</div>
						</div>

						<Button
							onClick={handleCropToggle}
							variant="outline"
							className="w-full gap-1.5 bg-white/5 text-slate-200 border-white/10 hover:bg-white/10 hover:border-white/20 hover:text-white text-[10px] h-8 transition-all"
						>
							<Crop className="w-3 h-3" />
							Crop Video
						</Button>

						<div className="space-y-2 border-t border-white/5 pt-3">
							<div className="flex items-center gap-2">
								<Palette className="h-3.5 w-3.5 text-[#2563EB]" />
								<div className="text-[10px] font-medium text-slate-300">Background</div>
							</div>
							{renderBackgroundControls()}
						</div>
					</div>
				);
			case "cursor":
				return (
					<div className="space-y-3">
						<div className="grid grid-cols-1 gap-2">
							<div className="flex items-center justify-between p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="text-[10px] font-medium text-slate-300">Show Cursor</div>
								<Switch
									checked={showCursor}
									onCheckedChange={onShowCursorChange}
									className="data-[state=checked]:bg-[#2563EB] scale-90"
								/>
							</div>
							<div className="flex items-center justify-between p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="text-[10px] font-medium text-slate-300">Loop Cursor</div>
								<Switch
									checked={loopCursor}
									onCheckedChange={onLoopCursorChange}
									className="data-[state=checked]:bg-[#2563EB] scale-90"
								/>
							</div>
						</div>
						<div className="grid grid-cols-1 gap-2">
							<div className="p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="flex items-center justify-between mb-1">
									<div className="text-[10px] font-medium text-slate-300">Size</div>
									<span className="text-[10px] text-slate-500 font-mono">
										{cursorSize.toFixed(2)}×
									</span>
								</div>
								<Slider
									value={[cursorSize]}
									onValueChange={(values) => onCursorSizeChange?.(values[0])}
									min={0.5}
									max={10}
									step={0.05}
									className="w-full"
								/>
							</div>
							<div className="p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="flex items-center justify-between mb-1">
									<div className="text-[10px] font-medium text-slate-300">Smoothing</div>
									<span className="text-[10px] text-slate-500 font-mono">
										{cursorSmoothing <= 0 ? "Off" : cursorSmoothing.toFixed(2)}
									</span>
								</div>
								<Slider
									value={[cursorSmoothing]}
									onValueChange={(values) => onCursorSmoothingChange?.(values[0])}
									min={0}
									max={2}
									step={0.01}
									className="w-full"
								/>
							</div>
						</div>
						<div className="grid grid-cols-1 gap-2">
							<div className="p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="flex items-center justify-between mb-1">
									<div className="text-[10px] font-medium text-slate-300">Motion Blur</div>
									<span className="text-[10px] text-slate-500 font-mono">
										{cursorMotionBlur.toFixed(2)}×
									</span>
								</div>
								<Slider
									value={[cursorMotionBlur]}
									onValueChange={(values) => onCursorMotionBlurChange?.(values[0])}
									min={0}
									max={2}
									step={0.05}
									className="w-full"
								/>
							</div>
							<div className="p-2 rounded-lg bg-white/5 border border-white/5">
								<div className="flex items-center justify-between mb-1">
									<div className="text-[10px] font-medium text-slate-300">Click Bounce</div>
									<span className="text-[10px] text-slate-500 font-mono">
										{cursorClickBounce.toFixed(2)}×
									</span>
								</div>
								<Slider
									value={[cursorClickBounce]}
									onValueChange={(values) => onCursorClickBounceChange?.(values[0])}
									min={0}
									max={5}
									step={0.05}
									className="w-full"
								/>
							</div>
						</div>
					</div>
				);
			case "camera":
				return (
					<div className="space-y-3">
						<div className="flex items-center justify-between gap-3 p-2 rounded-lg bg-white/5 border border-white/5">
							<div>
								<div className="text-[11px] font-medium text-slate-200">Facecam</div>
								<div className="text-[10px] text-slate-500">
									{facecamAvailable
										? "Show a Loom-style facecam overlay."
										: "Record with facecam enabled to customize."}
								</div>
							</div>
							<Switch
								checked={facecamAvailable && facecamSettings.enabled}
								disabled={!facecamAvailable}
								onCheckedChange={(checked) =>
									updateFacecamSettings({ enabled: checked && facecamAvailable })
								}
							/>
						</div>

						{facecamAvailable && (
							<div className="space-y-3">
								<ToggleGroup
									type="single"
									value={facecamSettings.shape}
									onValueChange={(value) => {
										if (value === "circle" || value === "square") {
											updateFacecamSettings({ shape: value });
										}
									}}
									className="grid grid-cols-2 rounded-lg border border-white/5 bg-white/5 p-1"
								>
									<ToggleGroupItem value="circle" className="h-8 text-[10px]">
										Circle
									</ToggleGroupItem>
									<ToggleGroupItem value="square" className="h-8 text-[10px]">
										Square
									</ToggleGroupItem>
								</ToggleGroup>

								<div className="p-2 rounded-lg bg-white/5 border border-white/5">
									<div className="flex items-center justify-between mb-1">
										<div className="text-[10px] font-medium text-slate-300">Facecam Size</div>
										<span className="text-[10px] text-slate-500 font-mono">
											{facecamSettings.size.toFixed(0)}%
										</span>
									</div>
									<Slider
										value={[facecamSettings.size]}
										onValueChange={(values) => updateFacecamSettings({ size: values[0] })}
										min={12}
										max={40}
										step={1}
										className="w-full"
									/>
								</div>

								{facecamSettings.shape === "square" && (
									<div className="p-2 rounded-lg bg-white/5 border border-white/5">
										<div className="flex items-center justify-between mb-1">
											<div className="text-[10px] font-medium text-slate-300">Square Roundness</div>
											<span className="text-[10px] text-slate-500 font-mono">
												{facecamSettings.cornerRadius.toFixed(0)}%
											</span>
										</div>
										<Slider
											value={[facecamSettings.cornerRadius]}
											onValueChange={(values) => updateFacecamSettings({ cornerRadius: values[0] })}
											min={0}
											max={50}
											step={1}
											className="w-full"
										/>
									</div>
								)}
								<div className="p-2 rounded-lg bg-white/5 border border-white/5">
									<div className="flex items-center justify-between mb-1">
										<div className="text-[10px] font-medium text-slate-300">Border Width</div>
										<span className="text-[10px] text-slate-500 font-mono">
											{facecamSettings.borderWidth.toFixed(0)}px
										</span>
									</div>
									<Slider
										value={[facecamSettings.borderWidth]}
										onValueChange={(values) => updateFacecamSettings({ borderWidth: values[0] })}
										min={0}
										max={16}
										step={1}
										className="w-full"
									/>
								</div>

								<div className="p-2 rounded-lg bg-white/5 border border-white/5">
									<div className="text-[10px] font-medium text-slate-300 mb-1.5">Border Color</div>
									<Block
										color={facecamSettings.borderColor}
										colors={COLOR_PALETTE}
										onChange={(color) => updateFacecamSettings({ borderColor: color.hex })}
									/>
								</div>

								<div className="p-2 rounded-lg bg-white/5 border border-white/5">
									<div className="flex items-center justify-between mb-1">
										<div className="text-[10px] font-medium text-slate-300">Margin</div>
										<span className="text-[10px] text-slate-500 font-mono">
											{facecamSettings.margin.toFixed(0)}%
										</span>
									</div>
									<Slider
										value={[facecamSettings.margin]}
										onValueChange={(values) => updateFacecamSettings({ margin: values[0] })}
										min={0}
										max={12}
										step={1}
										className="w-full"
									/>
								</div>

								<div className="p-2 rounded-lg bg-white/5 border border-white/5">
									<div className="text-[10px] font-medium text-slate-300 mb-1.5">Position</div>
									<ToggleGroup
										type="single"
										value={facecamSettings.anchor ?? "bottom-right"}
										onValueChange={(value) => {
											if (FACECAM_ANCHORS.includes(value as FacecamAnchor)) {
												updateFacecamSettings({
													anchor: value as FacecamAnchor,
													customX: undefined,
													customY: undefined,
												});
											}
										}}
										className="grid grid-cols-2 rounded-lg border border-white/5 bg-white/5 p-1"
									>
										{FACECAM_ANCHORS.map((anchorOption) => {
											const labels: Record<string, string> = {
												"top-left": "Top Left",
												"top-right": "Top Right",
												"bottom-left": "Bottom Left",
												"bottom-right": "Bottom Right",
											};
											const isActive =
												facecamSettings.anchor === anchorOption ||
												(!facecamSettings.anchor && anchorOption === "bottom-right");
											return (
												<ToggleGroupItem
													key={anchorOption}
													value={anchorOption}
													className={cn("h-7 text-[9px]", isActive && "text-white")}
												>
													{labels[anchorOption] ?? anchorOption}
												</ToggleGroupItem>
											);
										})}
									</ToggleGroup>
									{facecamSettings.anchor === "custom" && (
										<div className="mt-1.5 text-[9px] text-slate-500">
											Drag the bubble in the preview to reposition.
										</div>
									)}
								</div>
							</div>
						)}
					</div>
				);
			case "audio":
				return (
					<div className="space-y-3">
						<div className="flex items-center justify-between gap-3 p-2 rounded-lg bg-white/5 border border-white/5">
							<div>
								<div className="text-[11px] font-medium text-slate-200">Mute Audio</div>
								<div className="text-[10px] text-slate-500">
									Silence preview playback and MP4 exports.
								</div>
							</div>
							<Switch
								checked={audioMuted}
								onCheckedChange={onAudioMutedChange}
								className="data-[state=checked]:bg-[#2563EB] scale-90"
							/>
						</div>

						<div className="p-2 rounded-lg bg-white/5 border border-white/5">
							<div className="flex items-center justify-between mb-1">
								<div className="text-[10px] font-medium text-slate-300">Master Volume</div>
								<span className="text-[10px] text-slate-500 font-mono">
									{Math.round(audioVolume * 100)}%
								</span>
							</div>
							<Slider
								value={[audioVolume]}
								onValueChange={(values) => onAudioVolumeChange?.(values[0])}
								min={0}
								max={1}
								step={0.01}
								className="w-full"
							/>
						</div>

						<div className="rounded-lg border border-white/5 bg-white/[0.03] p-2 text-[10px] text-slate-500">
							These controls affect editor playback immediately and apply to MP4 exports.
						</div>
					</div>
				);
		}
	};

	return (
		<Card className="flex h-full min-w-0 flex-[2] flex-col overflow-hidden border-border/70 bg-card/90 shadow-2xl shadow-black/20">
			<CardContent className="flex min-h-0 flex-1 p-0">
				<div className="flex flex-1 min-h-0 overflow-hidden">
					<div
						className="flex flex-col items-center gap-2 border-r border-border/60 bg-muted/30 px-2 py-3"
						role="tablist"
						aria-orientation="vertical"
					>
						{SETTINGS_SIDEBAR_TABS.map((tab) => {
							const TabIcon = tab.icon;
							const isActive = tab.id === activeTabDefinition.id;

							return (
								<Tooltip key={tab.id}>
									<TooltipTrigger asChild>
										<Button
											type="button"
											role="tab"
											id={`settings-tab-${tab.id}`}
											aria-selected={isActive}
											aria-controls={`settings-panel-${tab.id}`}
											aria-label={tab.label}
											onClick={() => setActiveTab(tab.id)}
											variant={isActive ? "secondary" : "ghost"}
											size="icon"
											className={cn(
												"size-10 rounded-lg",
												isActive
													? "bg-primary/15 text-primary hover:bg-primary/20"
													: "text-muted-foreground hover:bg-muted hover:text-foreground",
											)}
										>
											<TabIcon />
										</Button>
									</TooltipTrigger>
									<TooltipContent side="left">{tab.label}</TooltipContent>
								</Tooltip>
							);
						})}
					</div>

					<div className="flex flex-1 min-h-0 flex-col">
						<div className="flex-1 overflow-y-auto custom-scrollbar p-4 pb-0">
							<div
								role="tabpanel"
								id={`settings-panel-${activeTabDefinition.id}`}
								aria-labelledby={`settings-tab-${activeTabDefinition.id}`}
								className="rounded-lg border border-border/70 bg-background/60 p-4"
							>
								<div className="mb-4">
									<div className="flex items-center gap-2">
										<ActiveTabIcon className="size-4 text-primary" />
										<h3 className="text-sm font-medium text-foreground">
											{activeTabDefinition.label}
										</h3>
										<Badge variant="secondary" className="ml-auto text-[10px]">
											{activeTabDefinition.id}
										</Badge>
									</div>
									<p className="mt-1 text-[10px] text-muted-foreground">
										{activeTabDefinition.description}
									</p>
								</div>
								{renderSelectedTabContent()}
							</div>
						</div>

						<div className="flex-shrink-0 border-t border-border/60 bg-muted/20 p-4 pt-3">
							<div className="flex gap-2">
								<Button
									type="button"
									variant="ghost"
									size="sm"
									onClick={() => {
										openExternalUrl(
											"https://github.com/imbhargav5/open-recorder/issues/new/choose",
										);
									}}
									className="flex-1 text-[10px] text-muted-foreground"
								>
									<Bug data-icon="inline-start" />
									Report Bug
								</Button>
								<Button
									type="button"
									variant="ghost"
									size="sm"
									onClick={() => {
										openExternalUrl("https://github.com/imbhargav5/open-recorder");
									}}
									className="flex-1 text-[10px] text-muted-foreground"
								>
									<Star data-icon="inline-start" />
									Star on GitHub
								</Button>
							</div>
						</div>
					</div>
				</div>
			</CardContent>
			{showCropModal && cropRegion && onCropChange && (
				<>
					<div
						className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 animate-in fade-in duration-200"
						onClick={handleCropCancel}
					/>
					<div className="fixed top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 z-[60] bg-[#09090b] rounded-2xl shadow-2xl border border-white/10 p-8 w-[90vw] max-w-5xl max-h-[90vh] overflow-auto animate-in zoom-in-95 duration-200">
						<div className="flex items-center justify-between mb-6">
							<div>
								<span className="text-xl font-bold text-slate-200">Crop Video</span>
								<p className="text-sm text-slate-400 mt-2">
									Drag on each side to adjust the crop area
								</p>
							</div>
							<Button
								variant="ghost"
								size="icon"
								onClick={handleCropCancel}
								className="hover:bg-white/10 text-slate-400 hover:text-white"
							>
								<X className="w-5 h-5" />
							</Button>
						</div>
						<CropControl
							videoElement={videoElement || null}
							cropRegion={cropRegion}
							onCropChange={onCropChange}
							aspectRatio={aspectRatio}
						/>
						<div className="mt-6 flex justify-end">
							<Button
								onClick={() => setShowCropModal(false)}
								size="lg"
								className="bg-[#2563EB] hover:bg-[#2563EB]/90 text-white"
							>
								Done
							</Button>
						</div>
					</div>
				</>
			)}
		</Card>
	);
}

export const SettingsPanel = memo(SettingsPanelInner);
