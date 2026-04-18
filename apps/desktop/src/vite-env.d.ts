/// <reference types="vite/client" />

declare global {
  interface ProcessedDesktopSource {
    id: string;
    name: string;
    display_id: string;
    displayId?: string;
    thumbnail: string | null;
    appIcon: string | null;
    originalName?: string;
    sourceType?: "screen" | "window";
    appName?: string;
    windowTitle?: string;
    windowId?: number;
    // snake_case variants (legacy backend compat)
    source_type?: string;
    app_icon?: string | null;
    original_name?: string;
    app_name?: string;
    window_title?: string;
    window_id?: number;
  }

  interface CursorTelemetryPoint {
    timeMs: number;
    cx: number;
    cy: number;
    interactionType?:
      | "move"
      | "click"
      | "double-click"
      | "right-click"
      | "middle-click"
      | "mouseup";
    cursorType?:
      | "arrow"
      | "text"
      | "pointer"
      | "crosshair"
      | "open-hand"
      | "closed-hand"
      | "resize-ew"
      | "resize-ns"
      | "not-allowed";
  }

  interface SystemCursorAsset {
    dataUrl: string;
    hotspotX: number;
    hotspotY: number;
    width: number;
    height: number;
  }
}

declare module 'pixi.js/unsafe-eval';

export {};
