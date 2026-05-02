import Block from "@uiw/react-color-block";
import { useAtom } from "jotai";
import { ArrowLeft, Check, ClipboardCopy, Download, Palette } from "lucide-react";
import { useCallback, useEffect, useRef } from "react";
import { toast } from "sonner";
import {
	type ImageBackgroundType,
	imageBackgroundTypeAtom,
	imageBorderRadiusAtom,
	imageExportingAtom,
	imageGradientAtom,
	imageNaturalHeightAtom,
	imageNaturalWidthAtom,
	imagePaddingAtom,
	imageShadowIntensityAtom,
	imageSolidColorAtom,
	imageSrcAtom,
	imageWallpaperAtom,
	imageWallpaperPreviewPathsAtom,
} from "@/atoms/imageEditor";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import { Toaster } from "@/components/ui/sonner";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { getAssetPath } from "@/lib/assetPath";
import * as backend from "@/lib/backend";
import { copyCanvasImageToClipboard } from "@/lib/clipboard";
import { getSuggestedExportFileName } from "@/lib/exportFileName";
import { cn } from "@/lib/utils";
import { WALLPAPER_PATHS, WALLPAPER_RELATIVE_PATHS } from "@/lib/wallpapers";

// ─── Constants ───────────────────────────────────────────────────────────────

const GRADIENTS = [
	"linear-gradient(135deg, #667eea 0%, #764ba2 100%)",
	"linear-gradient(120deg, #d4fc79 0%, #96e6a1 100%)",
	"linear-gradient(135deg, #FBC8B4, #2447B1)",
	"linear-gradient(109.6deg, #F635A6, #36D860)",
	"linear-gradient(45deg, #ff9a9e 0%, #fad0c4 99%)",
	"linear-gradient(to top, #a18cd1 0%, #fbc2eb 100%)",
	"linear-gradient(120deg, #84fab0 0%, #8fd3f4 100%)",
	"linear-gradient(to right, #4facfe 0%, #00f2fe 100%)",
	"linear-gradient(to right, #fa709a 0%, #fee140 100%)",
	"linear-gradient(to top, #30cfd0 0%, #330867 100%)",
	"linear-gradient(to top, #c471f5 0%, #fa71cd 100%)",
	"linear-gradient(to right, #0acffe 0%, #495aff 100%)",
	"linear-gradient(315deg, #EC0101, #5044A9)",
	"linear-gradient(to top, #48c6ef 0%, #6f86d6 100%)",
	"radial-gradient(circle at 10% 20%, rgba(2,37,78,1) 0%, rgba(4,56,126,1) 20%, rgba(85,245,221,1) 100%)",
	"linear-gradient(109.6deg, rgba(15,2,2,1) 11.2%, rgba(36,163,190,1) 91.1%)",
	"linear-gradient(111.6deg, rgba(114,167,232,1) 9%, rgba(253,129,82,1) 44%, rgba(249,202,86,1) 86%)",
	"radial-gradient(circle at 3% 50%, rgba(80,12,139,0.87) 0%, rgba(161,10,144,0.72) 84%)",
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

// ─── Component ───────────────────────────────────────────────────────────────

export default function ImageEditor() {
	// Image state
	const [imageSrc, setImageSrc] = useAtom(imageSrcAtom);
	const [imageNaturalWidth, setImageNaturalWidth] = useAtom(imageNaturalWidthAtom);
	const [imageNaturalHeight, setImageNaturalHeight] = useAtom(imageNaturalHeightAtom);

	// Settings
	const [backgroundType, setBackgroundType] = useAtom(imageBackgroundTypeAtom);
	const [wallpaper, setWallpaper] = useAtom(imageWallpaperAtom);
	const [gradient, setGradient] = useAtom(imageGradientAtom);
	const [solidColor, setSolidColor] = useAtom(imageSolidColorAtom);
	const [padding, setPadding] = useAtom(imagePaddingAtom);
	const [borderRadius, setBorderRadius] = useAtom(imageBorderRadiusAtom);
	const [shadowIntensity, setShadowIntensity] = useAtom(imageShadowIntensityAtom);

	// Wallpaper previews
	const [wallpaperPreviewPaths, setWallpaperPreviewPaths] = useAtom(imageWallpaperPreviewPathsAtom);

	// Export state
	const [exporting, setExporting] = useAtom(imageExportingAtom);

	const imageRef = useRef<HTMLImageElement | null>(null);

	// ─── Load screenshot path from backend ───────────────────────────────────

	useEffect(() => {
		let mounted = true;
		(async () => {
			try {
				const path = await backend.getCurrentScreenshotPath();
				if (!path || !mounted) return;
				const src = await backend.convertFileToSrc(path);
				if (mounted) setImageSrc(src);
			} catch (err) {
				console.error("Failed to load screenshot:", err);
			}
		})();
		return () => {
			mounted = false;
		};
	}, []);

	// ─── Resolve wallpaper preview paths ─────────────────────────────────────

	useEffect(() => {
		let mounted = true;
		(async () => {
			try {
				const resolved = await Promise.all(
					WALLPAPER_RELATIVE_PATHS.map((path) => getAssetPath(path)),
				);
				if (!mounted) return;

				setWallpaperPreviewPaths(resolved);
				setWallpaper((current) => {
					const defaultWallpaper = WALLPAPER_PATHS[0];
					if (current === defaultWallpaper || current === WALLPAPER_RELATIVE_PATHS[0]) {
						return resolved[0] ?? current;
					}

					return current;
				});
			} catch {
				if (mounted) setWallpaperPreviewPaths(WALLPAPER_PATHS);
			}
		})();
		return () => {
			mounted = false;
		};
	}, []);

	// ─── Track natural image dimensions ──────────────────────────────────────

	const handleImageLoad = (e: React.SyntheticEvent<HTMLImageElement>) => {
		const img = e.currentTarget;
		setImageNaturalWidth(img.naturalWidth);
		setImageNaturalHeight(img.naturalHeight);
		imageRef.current = img;
	};

	// ─── Derived background style ────────────────────────────────────────────

	const getBackgroundStyle = useCallback((): React.CSSProperties => {
		switch (backgroundType) {
			case "wallpaper":
				return {
					backgroundImage: `url(${wallpaper})`,
					backgroundSize: "cover",
					backgroundPosition: "center",
				};
			case "gradient":
				return { background: gradient };
			case "color":
				return { backgroundColor: solidColor };
			case "transparent":
				return {
					backgroundImage: "repeating-conic-gradient(#808080 0% 25%, #c0c0c0 0% 50%)",
					backgroundSize: "20px 20px",
				};
		}
	}, [backgroundType, wallpaper, gradient, solidColor]);

	// ─── Render to canvas for export and clipboard flows ─────────────────────

	const renderToCanvas = useCallback(async (): Promise<HTMLCanvasElement | null> => {
		const img = imageRef.current;
		if (!img || !imageNaturalWidth || !imageNaturalHeight) return null;

		const totalW = imageNaturalWidth + padding * 2;
		const totalH = imageNaturalHeight + padding * 2;

		const canvas = document.createElement("canvas");
		canvas.width = totalW;
		canvas.height = totalH;
		const ctx = canvas.getContext("2d");
		if (!ctx) return null;

		// 1. Draw background
		if (backgroundType === "wallpaper") {
			const bgImg = new Image();
			bgImg.crossOrigin = "anonymous";
			await new Promise<void>((resolve) => {
				bgImg.onload = () => resolve();
				bgImg.onerror = () => resolve();
				bgImg.src = wallpaper;
			});
			// Cover-fit the wallpaper
			const bgAspect = bgImg.naturalWidth / bgImg.naturalHeight;
			const canvasAspect = totalW / totalH;
			let sx = 0,
				sy = 0,
				sw = bgImg.naturalWidth,
				sh = bgImg.naturalHeight;
			if (bgAspect > canvasAspect) {
				sw = bgImg.naturalHeight * canvasAspect;
				sx = (bgImg.naturalWidth - sw) / 2;
			} else {
				sh = bgImg.naturalWidth / canvasAspect;
				sy = (bgImg.naturalHeight - sh) / 2;
			}
			ctx.drawImage(bgImg, sx, sy, sw, sh, 0, 0, totalW, totalH);
		} else if (backgroundType === "gradient") {
			// Parse and draw gradient — simplified: use a temporary canvas
			const tempDiv = document.createElement("div");
			tempDiv.style.width = `${totalW}px`;
			tempDiv.style.height = `${totalH}px`;
			tempDiv.style.background = gradient;
			tempDiv.style.position = "fixed";
			tempDiv.style.left = "-9999px";
			document.body.appendChild(tempDiv);
			const foreignCanvas = document.createElement("canvas");
			foreignCanvas.width = totalW;
			foreignCanvas.height = totalH;
			// Use html2canvas-like approach or just fill with a simple gradient
			// For simplicity, parse the first two colors
			document.body.removeChild(tempDiv);

			// Fallback: draw a simple linear gradient from the gradient string
			const colors = gradient.match(/#[0-9a-fA-F]{3,8}|rgba?\([^)]+\)/g) || ["#667eea", "#764ba2"];
			const grd = ctx.createLinearGradient(0, 0, totalW, totalH);
			colors.forEach((c, i) => grd.addColorStop(i / Math.max(colors.length - 1, 1), c));
			ctx.fillStyle = grd;
			ctx.fillRect(0, 0, totalW, totalH);
		} else if (backgroundType === "color") {
			ctx.fillStyle = solidColor;
			ctx.fillRect(0, 0, totalW, totalH);
		}
		// transparent: leave canvas transparent (alpha 0)

		// 2. Draw shadow
		if (shadowIntensity > 0) {
			ctx.save();
			ctx.shadowColor = `rgba(0,0,0,${0.5 * shadowIntensity})`;
			ctx.shadowBlur = 40 * shadowIntensity;
			ctx.shadowOffsetX = 0;
			ctx.shadowOffsetY = 10 * shadowIntensity;

			// Draw a filled rounded rect to cast the shadow
			const x = padding;
			const y = padding;
			const w = imageNaturalWidth;
			const h = imageNaturalHeight;
			const r = borderRadius;
			ctx.beginPath();
			ctx.moveTo(x + r, y);
			ctx.lineTo(x + w - r, y);
			ctx.quadraticCurveTo(x + w, y, x + w, y + r);
			ctx.lineTo(x + w, y + h - r);
			ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
			ctx.lineTo(x + r, y + h);
			ctx.quadraticCurveTo(x, y + h, x, y + h - r);
			ctx.lineTo(x, y + r);
			ctx.quadraticCurveTo(x, y, x + r, y);
			ctx.closePath();
			ctx.fillStyle = "rgba(0,0,0,0.01)"; // nearly invisible fill, just for shadow
			ctx.fill();
			ctx.restore();
		}

		// 3. Draw screenshot image with border-radius clip
		ctx.save();
		const x = padding;
		const y = padding;
		const w = imageNaturalWidth;
		const h = imageNaturalHeight;
		const r = borderRadius;
		ctx.beginPath();
		ctx.moveTo(x + r, y);
		ctx.lineTo(x + w - r, y);
		ctx.quadraticCurveTo(x + w, y, x + w, y + r);
		ctx.lineTo(x + w, y + h - r);
		ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
		ctx.lineTo(x + r, y + h);
		ctx.quadraticCurveTo(x, y + h, x, y + h - r);
		ctx.lineTo(x, y + r);
		ctx.quadraticCurveTo(x, y, x + r, y);
		ctx.closePath();
		ctx.clip();
		ctx.drawImage(img, x, y, w, h);
		ctx.restore();

		return canvas;
	}, [
		imageNaturalWidth,
		imageNaturalHeight,
		padding,
		borderRadius,
		shadowIntensity,
		backgroundType,
		wallpaper,
		gradient,
		solidColor,
	]);

	// ─── Export handlers ─────────────────────────────────────────────────────

	const handleSave = async () => {
		setExporting(true);
		try {
			const canvas = await renderToCanvas();
			const blob = await new Promise<Blob | null>((resolve) =>
				canvas?.toBlob(resolve, "image/png"),
			);
			if (!blob) {
				toast.error("Failed to render image");
				return;
			}
			const arr = new Uint8Array(await blob.arrayBuffer());
			const saved = await backend.saveScreenshotFile(
				arr,
				getSuggestedExportFileName("screenshot", "png"),
			);
			if (saved) {
				toast.success("Screenshot saved!", { description: saved });
			}
		} catch (err) {
			console.error("Save failed:", err);
			toast.error("Failed to save screenshot");
		} finally {
			setExporting(false);
		}
	};

	const handleCopyToClipboard = async () => {
		try {
			const canvas = await renderToCanvas();
			if (!canvas) {
				toast.error("Failed to render image");
				return;
			}

			try {
				await copyCanvasImageToClipboard(canvas);
			} catch (nativeError) {
				const blob = await new Promise<Blob | null>((resolve) =>
					canvas.toBlob(resolve, "image/png"),
				);
				if (!blob || !navigator.clipboard?.write || typeof ClipboardItem === "undefined") {
					throw nativeError;
				}

				await navigator.clipboard.write([new ClipboardItem({ [blob.type || "image/png"]: blob })]);
			}
			toast.success("Copied to clipboard!");
		} catch (err) {
			console.error("Copy failed:", err);
			toast.error("Failed to copy to clipboard");
		}
	};

	const handleBackToCapture = async () => {
		try {
			// Show HUD overlay again, then close this window
			await backend.hudOverlayShow();
			window.close();
		} catch {
			// ignore
		}
	};

	// ─── Select wallpaper ────────────────────────────────────────────────────

	const handleWallpaperSelect = (path: string) => {
		setWallpaper(path);
		setBackgroundType("wallpaper");
	};

	// ─── Render ──────────────────────────────────────────────────────────────

	const shadowStyle =
		shadowIntensity > 0
			? `0 ${Math.round(10 * shadowIntensity)}px ${Math.round(40 * shadowIntensity)}px rgba(0,0,0,${(0.5 * shadowIntensity).toFixed(2)})`
			: "none";

	return (
		<div className="flex h-screen bg-[#09090b] text-white overflow-hidden">
			<Toaster />

			{/* ─── Preview Area ─────────────────────────────────────────────── */}
			<div className="flex-1 flex items-center justify-center p-8 overflow-auto">
				{/* macOS traffic-light padding */}
				<div className="absolute top-0 left-0 w-full h-10" />

				{imageSrc ? (
					<div
						className="relative flex items-center justify-center overflow-hidden"
						style={{
							...getBackgroundStyle(),
							padding: `${padding}px`,
							borderRadius: `${borderRadius + (padding > 0 ? 8 : 0)}px`,
							maxWidth: "90%",
							maxHeight: "85vh",
						}}
					>
						<img
							src={imageSrc}
							crossOrigin="anonymous"
							onLoad={handleImageLoad}
							alt="Screenshot"
							className="block max-w-full max-h-[70vh] object-contain"
							style={{
								borderRadius: `${borderRadius}px`,
								boxShadow: shadowStyle,
							}}
						/>
					</div>
				) : (
					<div className="flex flex-col items-center gap-4 text-white/40">
						<Palette size={48} strokeWidth={1} />
						<p className="text-sm">No screenshot loaded</p>
						<Button
							variant="outline"
							size="sm"
							onClick={handleBackToCapture}
							className="gap-2 border-white/15 bg-white/5 text-white/70 hover:bg-white/10 hover:text-white"
						>
							<ArrowLeft size={14} /> Back to Capture
						</Button>
					</div>
				)}
			</div>

			{/* ─── Settings Sidebar ─────────────────────────────────────────── */}
			<div className="w-[300px] border-l border-white/10 bg-[#09090b] flex flex-col overflow-hidden">
				<div className="flex-1 overflow-y-auto custom-scrollbar p-4 space-y-5">
					{/* Header */}
					<div className="pt-6">
						<h2 className="text-sm font-semibold text-white/90 tracking-tight">
							Screenshot Settings
						</h2>
						<p className="text-[11px] text-white/40 mt-0.5">
							Customize background, padding & effects
						</p>
					</div>

					{/* ── Background ─────────────────────────────────────────────── */}
					<div>
						<div className="text-[10px] font-medium tracking-[0.18em] uppercase text-white/50 mb-2">
							Background
						</div>
						<Tabs
							value={backgroundType}
							onValueChange={(v) => setBackgroundType(v as ImageBackgroundType)}
						>
							<TabsList className="grid grid-cols-4 bg-white/5 rounded-lg mb-3 h-7">
								<TabsTrigger
									value="wallpaper"
									className="text-[10px] data-[state=active]:bg-[#2563EB] data-[state=active]:text-white rounded-md py-0.5"
								>
									Image
								</TabsTrigger>
								<TabsTrigger
									value="gradient"
									className="text-[10px] data-[state=active]:bg-[#2563EB] data-[state=active]:text-white rounded-md py-0.5"
								>
									Gradient
								</TabsTrigger>
								<TabsTrigger
									value="color"
									className="text-[10px] data-[state=active]:bg-[#2563EB] data-[state=active]:text-white rounded-md py-0.5"
								>
									Color
								</TabsTrigger>
								<TabsTrigger
									value="transparent"
									className="text-[10px] data-[state=active]:bg-[#2563EB] data-[state=active]:text-white rounded-md py-0.5"
								>
									None
								</TabsTrigger>
							</TabsList>

							{/* Wallpaper grid */}
							<TabsContent value="wallpaper" className="mt-0">
								<div className="grid grid-cols-4 gap-1.5 max-h-[200px] overflow-y-auto custom-scrollbar pr-1">
									{wallpaperPreviewPaths.map((path, idx) => {
										const isSelected = wallpaper === path || wallpaper === WALLPAPER_PATHS[idx];
										return (
											<button
												key={path}
												onClick={() => handleWallpaperSelect(path)}
												className={cn(
													"relative aspect-video rounded-lg overflow-hidden border-2 transition-all",
													isSelected
														? "border-[#2563EB] ring-1 ring-[#2563EB]/50"
														: "border-transparent hover:border-white/20",
												)}
											>
												<img src={path} alt="" className="w-full h-full object-cover" />
												{isSelected && (
													<div className="absolute inset-0 flex items-center justify-center bg-black/30">
														<Check size={14} className="text-white" />
													</div>
												)}
											</button>
										);
									})}
								</div>
							</TabsContent>

							{/* Gradient grid */}
							<TabsContent value="gradient" className="mt-0">
								<div className="grid grid-cols-4 gap-1.5 max-h-[200px] overflow-y-auto custom-scrollbar pr-1">
									{GRADIENTS.map((g) => {
										const isSelected = gradient === g && backgroundType === "gradient";
										return (
											<button
												key={g}
												onClick={() => {
													setGradient(g);
													setBackgroundType("gradient");
												}}
												className={cn(
													"aspect-video rounded-lg border-2 transition-all",
													isSelected
														? "border-[#2563EB] ring-1 ring-[#2563EB]/50"
														: "border-transparent hover:border-white/20",
												)}
												style={{ background: g }}
											/>
										);
									})}
								</div>
							</TabsContent>

							{/* Color picker */}
							<TabsContent value="color" className="mt-0">
								<Block
									color={solidColor}
									colors={COLOR_PALETTE}
									onChange={(c) => {
										setSolidColor(c.hex);
										setBackgroundType("color");
									}}
								/>
							</TabsContent>

							{/* Transparent info */}
							<TabsContent value="transparent" className="mt-0">
								<p className="text-[11px] text-white/40">
									No background will be applied. Export as PNG to preserve transparency.
								</p>
							</TabsContent>
						</Tabs>
					</div>

					{/* ── Padding ────────────────────────────────────────────────── */}
					<div>
						<div className="flex items-center justify-between mb-2">
							<span className="text-[10px] font-medium tracking-[0.18em] uppercase text-white/50">
								Padding
							</span>
							<span className="text-[10px] text-white/40 font-mono">{padding}px</span>
						</div>
						<Slider
							value={[padding]}
							onValueChange={([v]) => setPadding(v)}
							min={0}
							max={120}
							step={1}
							className="w-full"
						/>
					</div>

					{/* ── Border Radius ──────────────────────────────────────────── */}
					<div>
						<div className="flex items-center justify-between mb-2">
							<span className="text-[10px] font-medium tracking-[0.18em] uppercase text-white/50">
								Border Radius
							</span>
							<span className="text-[10px] text-white/40 font-mono">{borderRadius}px</span>
						</div>
						<Slider
							value={[borderRadius]}
							onValueChange={([v]) => setBorderRadius(v)}
							min={0}
							max={50}
							step={0.5}
							className="w-full"
						/>
					</div>

					{/* ── Shadow ─────────────────────────────────────────────────── */}
					<div>
						<div className="flex items-center justify-between mb-2">
							<span className="text-[10px] font-medium tracking-[0.18em] uppercase text-white/50">
								Shadow
							</span>
							<span className="text-[10px] text-white/40 font-mono">
								{(shadowIntensity * 100).toFixed(0)}%
							</span>
						</div>
						<Slider
							value={[shadowIntensity]}
							onValueChange={([v]) => setShadowIntensity(v)}
							min={0}
							max={1}
							step={0.01}
							className="w-full"
						/>
					</div>
				</div>

				{/* ── Actions ──────────────────────────────────────────────────── */}
				<div className="border-t border-white/10 p-4 space-y-2">
					<div className="grid grid-cols-2 gap-2">
						<Button
							onClick={handleSave}
							disabled={!imageSrc || exporting}
							className="gap-1.5 bg-[#2563EB] text-white hover:bg-[#2563EB]/80 text-xs h-9"
						>
							<Download size={14} />
							{exporting ? "Saving..." : "Save PNG"}
						</Button>
						<Button
							onClick={handleCopyToClipboard}
							disabled={!imageSrc}
							variant="outline"
							className="gap-1.5 border-white/15 bg-white/5 text-white/80 hover:bg-white/10 text-xs h-9"
						>
							<ClipboardCopy size={14} />
							Copy
						</Button>
					</div>
					<Button
						onClick={handleBackToCapture}
						variant="ghost"
						className="w-full gap-2 text-white/50 hover:text-white/80 hover:bg-white/5 text-xs h-8"
					>
						<ArrowLeft size={14} />
						Back to Capture
					</Button>
				</div>
			</div>
		</div>
	);
}
