/**
 * Patch the Electron binary for development so macOS identifies the app as
 * "OpenRecorderDev" in System Preferences and TCC permission dialogs.
 *
 * What this script does:
 *  1. Renames Electron.app → OpenRecorderDev.app (keeps executable as "Electron")
 *  2. Updates CFBundleName, CFBundleDisplayName, and CFBundleIdentifier in
 *     every Info.plist (main app + helpers)
 *  3. Updates the electron package's path.txt so `require('electron')` resolves
 *  4. Re-signs the entire bundle with an ad-hoc signature
 *  5. Registers the app with LaunchServices
 *
 * The executable inside Contents/MacOS stays as "Electron" so that
 * app.isPackaged returns false in development (Electron checks the binary name).
 *
 * Run once after `pnpm install` (idempotent — safe to re-run).
 * macOS-only; exits silently on other platforms.
 */

import { execSync } from "node:child_process";
import { existsSync, renameSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

if (process.platform !== "darwin") {
	process.exit(0);
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE_ROOT = path.resolve(__dirname, "..", "..", "..");

const DEV_NAME = "OpenRecorderDev";
const DEV_BUNDLE_ID = "dev.openrecorder.app.dev";

// ─── Locate the electron package directory ───────────────────────────────────

function findElectronPkgDir() {
	const direct = path.join(WORKSPACE_ROOT, "node_modules", "electron");
	if (existsSync(path.join(direct, "path.txt"))) return direct;

	try {
		const result = execSync(
			`find "${WORKSPACE_ROOT}/node_modules/.pnpm" -path "*/electron/path.txt" 2>/dev/null`,
			{ encoding: "utf-8" },
		).trim();
		if (result) return path.dirname(result.split("\n")[0]);
	} catch {
		// ignore
	}
	return null;
}

const electronPkgDir = findElectronPkgDir();
if (!electronPkgDir) {
	console.warn("[patch-electron] electron package not found — skipping.");
	process.exit(0);
}

const distDir = path.join(electronPkgDir, "dist");
const pathTxtFile = path.join(electronPkgDir, "path.txt");

// ─── Check if already patched ────────────────────────────────────────────────

const patchedApp = path.join(distDir, `${DEV_NAME}.app`);
const originalApp = path.join(distDir, "Electron.app");

if (existsSync(patchedApp)) {
	console.log(`✓ Electron already patched → ${DEV_NAME}.app`);
	process.exit(0);
}

if (!existsSync(originalApp)) {
	console.warn("[patch-electron] Electron.app not found — skipping.");
	process.exit(0);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function plistSet(plistPath, key, value) {
	execSync(`plutil -replace "${key}" -string "${value}" "${plistPath}"`);
}

// ─── 1. Patch helper app plists ──────────────────────────────────────────────

const frameworksDir = path.join(originalApp, "Contents", "Frameworks");
const helpers = [
	"Electron Helper.app",
	"Electron Helper (GPU).app",
	"Electron Helper (Renderer).app",
	"Electron Helper (Plugin).app",
];

for (const helperDir of helpers) {
	const plist = path.join(frameworksDir, helperDir, "Contents", "Info.plist");
	if (!existsSync(plist)) continue;

	plistSet(plist, "CFBundleIdentifier", `${DEV_BUNDLE_ID}.helper`);
}

// ─── 2. Patch the main app plist ─────────────────────────────────────────────

const mainPlist = path.join(originalApp, "Contents", "Info.plist");
plistSet(mainPlist, "CFBundleName", DEV_NAME);
plistSet(mainPlist, "CFBundleDisplayName", DEV_NAME);
plistSet(mainPlist, "CFBundleIdentifier", DEV_BUNDLE_ID);
// Keep CFBundleExecutable as "Electron" — do NOT change it.

// ─── 3. Rename only the .app directory ───────────────────────────────────────

renameSync(originalApp, patchedApp);

// ─── 4. Update path.txt so require('electron') resolves ─────────────────────

writeFileSync(pathTxtFile, `${DEV_NAME}.app/Contents/MacOS/Electron`);

// ─── 5. Re-sign the entire bundle ───────────────────────────────────────────

try {
	execSync(`codesign --force --deep --sign - "${patchedApp}"`, { stdio: "pipe" });
} catch (err) {
	console.warn("[patch-electron] codesign warning:", err.message);
}

// ─── 6. Register with LaunchServices ─────────────────────────────────────────

try {
	execSync(
		`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${patchedApp}"`,
		{ stdio: "pipe" },
	);
} catch {
	// non-fatal
}

console.log(`✓ Patched & signed → ${DEV_NAME}.app (${DEV_BUNDLE_ID})`);
