/**
 * Launch Electron.app via macOS `open` so the OS treats it as a standalone
 * application.  This is necessary because macOS TCC (Privacy permissions)
 * attributes screen-recording / accessibility requests to the "responsible
 * process".  When Electron is spawned as a child of Terminal, Terminal is
 * the responsible process and the permission dialog says "Terminal wants to
 * record your screen" instead of "OpenRecorderDev".
 *
 * On non-macOS platforms, falls back to the regular `electron` CLI.
 */

import { execSync, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_DIR = path.resolve(__dirname, "..");

function resolveElectronApp() {
	// require.resolve would need CJS; use the electron package's index.js
	// which exports the path to the binary.
	const electronBin = execSync("pnpm node -e \"process.stdout.write(require('electron'))\"", {
		cwd: PROJECT_DIR,
		encoding: "utf-8",
	}).trim();
	// electronBin = /…/Electron.app/Contents/MacOS/Electron
	const appBundle = path.resolve(electronBin, "..", "..", "..");
	if (!existsSync(appBundle)) {
		throw new Error(`Electron.app not found at ${appBundle}`);
	}
	return appBundle;
}

if (process.platform === "darwin") {
	const appBundle = resolveElectronApp();
	// -W  = wait for app to exit (so concurrently can detect exit)
	// -n  = open a new instance even if one is already running
	// --args = pass remaining args to the app
	const child = spawn("open", ["-W", "-n", appBundle, "--args", PROJECT_DIR], {
		stdio: "inherit",
	});
	child.on("exit", (code) => process.exit(code ?? 0));
} else {
	// Non-macOS: fall back to the regular electron CLI
	const child = spawn("electron", ["."], {
		cwd: PROJECT_DIR,
		stdio: "inherit",
		shell: true,
	});
	child.on("exit", (code) => process.exit(code ?? 0));
}
