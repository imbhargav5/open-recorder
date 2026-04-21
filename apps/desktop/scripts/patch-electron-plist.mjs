/**
 * Patch the Electron binary for development so macOS identifies the app as
 * "OpenRecorderDev" in System Preferences and TCC permission dialogs.
 *
 * What this script does:
 *  1. Renames Electron.app → OpenRecorderDev.app (keeps executable as "Electron")
 *  2. Updates CFBundleName, CFBundleDisplayName, and CFBundleIdentifier in
 *     every Info.plist (main app + helpers)
 *  3. Updates the electron package's path.txt so `require('electron')` resolves
 *  4. Re-signs the entire bundle — preferring a stable self-signed identity
 *     (see `OPEN_RECORDER_DEV_CODESIGN_IDENTITY` below) so macOS's TCC database
 *     recognizes the rebuilt bundle as the same app across reinstalls.  Falls
 *     back to an ad-hoc signature when no stable identity is available.
 *  5. Registers the app with LaunchServices
 *
 * The executable inside Contents/MacOS stays as "Electron" so that
 * app.isPackaged returns false in development (Electron checks the binary name).
 *
 * Run once after `pnpm install` (idempotent — safe to re-run).
 * macOS-only; exits silently on other platforms.
 *
 * ── Preserving TCC grants across `node_modules` rebuilds ──────────────────
 *
 * macOS keys Screen-Recording / Microphone / Camera grants on the combination
 * of the bundle identifier *and* the code-signing "designated requirement".
 * An ad-hoc signature's DR is derived from the content hash of the bundle —
 * so every time this script regenerates `OpenRecorderDev.app` (e.g. after a
 * `pnpm install` that wiped `node_modules`), the DR changes and TCC silently
 * invalidates the previously-granted permissions.  Users then land on the
 * "Denied" screen and have to re-grant from scratch.
 *
 * To avoid that, set the `OPEN_RECORDER_DEV_CODESIGN_IDENTITY` environment
 * variable to the *name* of a stable self-signed codesigning identity already
 * present in your login keychain (e.g. `"Open Recorder Dev"`).  One-time
 * setup:
 *
 *   # Create a self-signed certificate in Keychain Access:
 *   #   Keychain Access → Certificate Assistant → Create a Certificate…
 *   #   Name:          Open Recorder Dev
 *   #   Identity type: Self Signed Root
 *   #   Certificate type: Code Signing
 *   # Then add to your shell profile:
 *   export OPEN_RECORDER_DEV_CODESIGN_IDENTITY="Open Recorder Dev"
 *
 * With that set, every re-patch signs with the same identity and TCC keeps
 * the grants alive.  Without it, this script ad-hoc-signs and warns that
 * permissions will need to be re-granted.
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
const MICROPHONE_USAGE_DESCRIPTION =
	"Open Recorder uses the microphone for audio commentary during recordings.";
const CAMERA_USAGE_DESCRIPTION = "Open Recorder uses the camera for facecam recordings.";
const AUDIO_CAPTURE_USAGE_DESCRIPTION =
	"Open Recorder captures system audio when you choose to record it.";

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
plistSet(mainPlist, "NSMicrophoneUsageDescription", MICROPHONE_USAGE_DESCRIPTION);
plistSet(mainPlist, "NSCameraUsageDescription", CAMERA_USAGE_DESCRIPTION);
plistSet(mainPlist, "NSAudioCaptureUsageDescription", AUDIO_CAPTURE_USAGE_DESCRIPTION);
// Keep CFBundleExecutable as "Electron" — do NOT change it.

// ─── 3. Rename only the .app directory ───────────────────────────────────────

renameSync(originalApp, patchedApp);

// ─── 4. Update path.txt so require('electron') resolves ─────────────────────

writeFileSync(pathTxtFile, `${DEV_NAME}.app/Contents/MacOS/Electron`);

// ─── 5. Re-sign the entire bundle ───────────────────────────────────────────

/**
 * Prefer a stable self-signed identity from the user's keychain so the
 * designated-requirement hash stays constant across rebuilds — that is what
 * keeps macOS's TCC database from invalidating Screen-Recording, Mic, and
 * Camera grants every time `node_modules` is wiped.  Falls back to ad-hoc.
 */
function resolveCodesignIdentity() {
	const envIdentity = process.env.OPEN_RECORDER_DEV_CODESIGN_IDENTITY;
	if (!envIdentity) {
		return null;
	}
	try {
		const output = execSync(`security find-identity -v -p codesigning`, {
			encoding: "utf-8",
			stdio: ["ignore", "pipe", "ignore"],
		});
		if (output.includes(envIdentity)) {
			return envIdentity;
		}
		console.warn(
			`[patch-electron] OPEN_RECORDER_DEV_CODESIGN_IDENTITY="${envIdentity}" not found in keychain — falling back to ad-hoc.`,
		);
	} catch {
		// `security` isn't available — fall through to ad-hoc.
	}
	return null;
}

const stableIdentity = resolveCodesignIdentity();
const signingIdentityArg = stableIdentity ? `"${stableIdentity}"` : "-";

try {
	execSync(`codesign --force --deep --sign ${signingIdentityArg} "${patchedApp}"`, {
		stdio: "pipe",
	});
	if (stableIdentity) {
		console.log(`✓ Signed with stable identity "${stableIdentity}" — TCC grants should persist.`);
	} else {
		console.log(
			"[patch-electron] Signed with ad-hoc identity. Because the ad-hoc signature's\n" +
				"               designated-requirement hash changes with the bundle contents,\n" +
				"               macOS will invalidate previously-granted Screen Recording,\n" +
				"               Microphone, and Camera permissions on the next rebuild and\n" +
				"               you'll have to re-grant them.\n" +
				"               Set OPEN_RECORDER_DEV_CODESIGN_IDENTITY to a stable self-signed\n" +
				"               codesigning identity from your login keychain to avoid this —\n" +
				"               see the header comment of this script for setup instructions.",
		);
	}
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
