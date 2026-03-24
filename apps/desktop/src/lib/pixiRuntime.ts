let pixiRuntimePromise: Promise<void> | null = null;

/**
 * Tauri production builds enforce a CSP that blocks `unsafe-eval`.
 * Pixi ships a CSP-safe polyfill package that must run before we create
 * any renderer or filter instances in packaged builds.
 */
export function ensurePixiRuntime(): Promise<void> {
	if (!pixiRuntimePromise) {
		pixiRuntimePromise = import("pixi.js/unsafe-eval").then(() => undefined);
	}

	return pixiRuntimePromise;
}
