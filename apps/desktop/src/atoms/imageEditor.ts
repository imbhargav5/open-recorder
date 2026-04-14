import { atom } from "jotai";
import { DEFAULT_WALLPAPER_PATH } from "@/lib/wallpapers";

export type ImageBackgroundType = "wallpaper" | "gradient" | "color" | "transparent";

const DEFAULT_IMAGE_GRADIENT = "linear-gradient(135deg, #667eea 0%, #764ba2 100%)";

export const imageSrcAtom = atom<string | null>(null);
export const imageNaturalWidthAtom = atom<number>(0);
export const imageNaturalHeightAtom = atom<number>(0);
export const imageBackgroundTypeAtom = atom<ImageBackgroundType>("wallpaper");
export const imageWallpaperAtom = atom<string>(DEFAULT_WALLPAPER_PATH);
export const imageGradientAtom = atom<string>(DEFAULT_IMAGE_GRADIENT);
export const imageSolidColorAtom = atom<string>("#2563EB");
export const imagePaddingAtom = atom<number>(48);
export const imageBorderRadiusAtom = atom<number>(12);
export const imageShadowIntensityAtom = atom<number>(0.6);
export const imageWallpaperPreviewPathsAtom = atom<string[]>([]);
export const imageExportingAtom = atom<boolean>(false);
