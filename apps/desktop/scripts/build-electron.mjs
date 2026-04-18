/**
 * Build script for the Electron main process and preload script.
 *
 * Bundles:
 *   electron/main.ts    → dist-electron/main.js    (main process, ESM)
 *   electron/preload.ts → dist-electron/preload.js  (preload, ESM)
 *
 * ESM output works with Electron 28+ when the package has "type": "module".
 * Uses esbuild for fast TypeScript transpilation and bundling.
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
  format: "esm",
  outdir: OUT_DIR,
  external: ["electron"],
  sourcemap: process.env.NODE_ENV !== "production",
  minify: process.env.NODE_ENV === "production",
};

await Promise.all([
  build({
    ...shared,
    entryPoints: [path.join(ROOT, "electron", "main.ts")],
  }),
  build({
    ...shared,
    entryPoints: [path.join(ROOT, "electron", "preload.ts")],
  }),
]);

console.log("✓ Electron main + preload built → dist-electron/ (ESM)");
