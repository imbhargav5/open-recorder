/**
 * Build script for the Electron main process and preload script.
 *
 * Bundles:
 *   electron/main.ts   → dist-electron/main.cjs   (main process, CommonJS)
 *   electron/preload.ts → dist-electron/preload.cjs (preload, CommonJS)
 *
 * Uses esbuild for fast TypeScript transpilation and bundling.
 * The output is CommonJS so it works reliably as Electron entry points,
 * regardless of the renderer's "type": "module" in package.json.
 */

import { build } from "esbuild";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync } from "node:fs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, "..");
const OUT_DIR = path.join(ROOT, "dist-electron");

mkdirSync(OUT_DIR, { recursive: true });

const shared = {
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  outdir: OUT_DIR,
  external: ["electron"],
  sourcemap: process.env.NODE_ENV !== "production",
  minify: process.env.NODE_ENV === "production",
};

await Promise.all([
  build({
    ...shared,
    entryPoints: [path.join(ROOT, "electron", "main.ts")],
    outExtension: { ".js": ".cjs" },
    // Mark handler sub-modules as external so they get bundled into main
  }),
  build({
    ...shared,
    entryPoints: [path.join(ROOT, "electron", "preload.ts")],
    outExtension: { ".js": ".cjs" },
  }),
]);

console.log("✓ Electron main + preload built → dist-electron/");
