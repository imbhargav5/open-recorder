import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
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
} from "./imageEditor";

describe("imageEditor atoms – write / read", () => {
  it("imageSrcAtom can be set to a file path", () => {
    const store = createStore();
    store.set(imageSrcAtom, "/screenshots/capture.png");
    expect(store.get(imageSrcAtom)).toBe("/screenshots/capture.png");
  });

  it("imageSrcAtom can be cleared back to null", () => {
    const store = createStore();
    store.set(imageSrcAtom, "/screenshots/capture.png");
    store.set(imageSrcAtom, null);
    expect(store.get(imageSrcAtom)).toBeNull();
  });

  it("imageNaturalWidthAtom can be set to a positive integer", () => {
    const store = createStore();
    store.set(imageNaturalWidthAtom, 1920);
    expect(store.get(imageNaturalWidthAtom)).toBe(1920);
  });

  it("imageNaturalHeightAtom can be set to a positive integer", () => {
    const store = createStore();
    store.set(imageNaturalHeightAtom, 1080);
    expect(store.get(imageNaturalHeightAtom)).toBe(1080);
  });

  it("width and height can be set independently", () => {
    const store = createStore();
    store.set(imageNaturalWidthAtom, 800);
    store.set(imageNaturalHeightAtom, 600);
    expect(store.get(imageNaturalWidthAtom)).toBe(800);
    expect(store.get(imageNaturalHeightAtom)).toBe(600);
  });

  it("imageBackgroundTypeAtom can cycle through all types", () => {
    const types: ImageBackgroundType[] = [
      "wallpaper",
      "gradient",
      "color",
      "transparent",
    ];
    const store = createStore();
    for (const type of types) {
      store.set(imageBackgroundTypeAtom, type);
      expect(store.get(imageBackgroundTypeAtom)).toBe(type);
    }
  });

  it("imageWallpaperAtom can be set to a custom path", () => {
    const store = createStore();
    store.set(imageWallpaperAtom, "/assets/wallpapers/custom.jpg");
    expect(store.get(imageWallpaperAtom)).toBe("/assets/wallpapers/custom.jpg");
  });

  it("imageGradientAtom can be replaced with a new gradient", () => {
    const store = createStore();
    const newGradient = "radial-gradient(circle, #ff6b6b, #4ecdc4)";
    store.set(imageGradientAtom, newGradient);
    expect(store.get(imageGradientAtom)).toBe(newGradient);
  });

  it("imageSolidColorAtom can be updated to any hex color", () => {
    const store = createStore();
    store.set(imageSolidColorAtom, "#FF5733");
    expect(store.get(imageSolidColorAtom)).toBe("#FF5733");
  });

  it("imagePaddingAtom can be set to zero (no padding)", () => {
    const store = createStore();
    store.set(imagePaddingAtom, 0);
    expect(store.get(imagePaddingAtom)).toBe(0);
  });

  it("imagePaddingAtom can be set to a large value", () => {
    const store = createStore();
    store.set(imagePaddingAtom, 200);
    expect(store.get(imagePaddingAtom)).toBe(200);
  });

  it("imageBorderRadiusAtom can be set to 0 for sharp corners", () => {
    const store = createStore();
    store.set(imageBorderRadiusAtom, 0);
    expect(store.get(imageBorderRadiusAtom)).toBe(0);
  });

  it("imageBorderRadiusAtom can be set to a large value for round corners", () => {
    const store = createStore();
    store.set(imageBorderRadiusAtom, 50);
    expect(store.get(imageBorderRadiusAtom)).toBe(50);
  });

  it("imageShadowIntensityAtom can be set to 0 (no shadow)", () => {
    const store = createStore();
    store.set(imageShadowIntensityAtom, 0);
    expect(store.get(imageShadowIntensityAtom)).toBe(0);
  });

  it("imageShadowIntensityAtom can be set to 1.0 (max shadow)", () => {
    const store = createStore();
    store.set(imageShadowIntensityAtom, 1.0);
    expect(store.get(imageShadowIntensityAtom)).toBe(1.0);
  });

  it("imageWallpaperPreviewPathsAtom can have paths added", () => {
    const store = createStore();
    const paths = ["/wall/a.jpg", "/wall/b.jpg", "/wall/c.jpg"];
    store.set(imageWallpaperPreviewPathsAtom, paths);
    expect(store.get(imageWallpaperPreviewPathsAtom)).toEqual(paths);
  });

  it("imageExportingAtom can be set to true during export", () => {
    const store = createStore();
    store.set(imageExportingAtom, true);
    expect(store.get(imageExportingAtom)).toBe(true);
  });

  it("imageExportingAtom resets to false after export completes", () => {
    const store = createStore();
    store.set(imageExportingAtom, true);
    store.set(imageExportingAtom, false);
    expect(store.get(imageExportingAtom)).toBe(false);
  });

  it("writes to one store do not affect another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    storeA.set(imageSrcAtom, "/screenshots/foo.png");
    storeA.set(imageNaturalWidthAtom, 1920);
    storeA.set(imageNaturalHeightAtom, 1080);
    storeA.set(imageBackgroundTypeAtom, "color");
    storeA.set(imageExportingAtom, true);

    expect(storeB.get(imageSrcAtom)).toBeNull();
    expect(storeB.get(imageNaturalWidthAtom)).toBe(0);
    expect(storeB.get(imageNaturalHeightAtom)).toBe(0);
    expect(storeB.get(imageBackgroundTypeAtom)).toBe("wallpaper");
    expect(storeB.get(imageExportingAtom)).toBe(false);
  });
});
