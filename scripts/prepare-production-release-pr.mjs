#!/usr/bin/env node

import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { buildCommitReleaseNotes, latestSemverTag } from "./production-release-notes.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");
const rustServiceRoot = resolve(repoRoot, "apps", "rust-service");
const rustServiceCargoTomlPath = resolve(rustServiceRoot, "Cargo.toml");
const rustServiceCargoLockPath = resolve(rustServiceRoot, "Cargo.lock");
const macosInfoPlistPath = resolve(repoRoot, "apps", "macos", "Resources", "Info.plist");
const releasePlanPath = resolve(repoRoot, ".github", "release-plan.json");

process.chdir(repoRoot);

function die(message) {
	console.error(`Error: ${message}`);
	process.exit(1);
}

function parseArgs(argv) {
	const args = {
		releaseType: "",
		name: "",
		notes: "",
		latest: "true",
		output: "",
	};

	for (let index = 0; index < argv.length; index += 1) {
		const arg = argv[index];

		switch (arg) {
			case "--release-type":
				args.releaseType = argv[++index] ?? die("--release-type requires a value");
				break;
			case "--name":
				args.name = argv[++index] ?? die("--name requires a value");
				break;
			case "--notes":
				args.notes = argv[++index] ?? die("--notes requires a value");
				break;
			case "--latest":
				args.latest = argv[++index] ?? die("--latest requires true or false");
				break;
			case "--output":
				args.output = argv[++index] ?? die("--output requires a value");
				break;
			case "-h":
			case "--help":
				console.log(`Usage: node scripts/prepare-production-release-pr.mjs --release-type patch|minor|major [options]

Prepares the next release bump inside GitHub Actions by updating the native
Rust service version and writing .github/release-plan.json.

Options:
  --release-type VALUE     Release type: patch, minor, or major.
  --name VALUE             Optional release title override.
  --notes VALUE            Optional release notes body. Defaults to commits since the previous release.
  --latest true|false      Whether the eventual release should be marked latest.
  --output PATH            Optional GitHub Actions output file to append to.
  -h, --help               Show this help message.
`);
				process.exit(0);
			default:
				die(`Unknown option: ${arg}`);
		}
	}

	if (!["patch", "minor", "major"].includes(args.releaseType)) {
		die("--release-type must be patch, minor, or major");
	}

	if (!["true", "false"].includes(args.latest)) {
		die("--latest must be true or false");
	}

	return args;
}

function capture(command, args, { allowFailure = false } = {}) {
	const result = spawnSync(command, args, {
		cwd: repoRoot,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	});

	if (result.status === 0) {
		return result.stdout.trim();
	}

	if (allowFailure) {
		return "";
	}

	const errorText = result.stderr.trim() || result.stdout.trim() || `${command} exited with status ${result.status}`;
	die(errorText);
}

function parseSemver(version) {
	const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
	if (!match) {
		die(`Invalid semantic version: ${version}`);
	}
	return match.slice(1).map(Number);
}

function compareVersions(first, second) {
	const [aMajor, aMinor, aPatch] = parseSemver(first);
	const [bMajor, bMinor, bPatch] = parseSemver(second);

	if (aMajor !== bMajor) {
		return aMajor > bMajor ? 1 : -1;
	}
	if (aMinor !== bMinor) {
		return aMinor > bMinor ? 1 : -1;
	}
	if (aPatch !== bPatch) {
		return aPatch > bPatch ? 1 : -1;
	}
	return 0;
}

function bumpVersion(baseVersion, releaseType) {
	const [major, minor, patch] = parseSemver(baseVersion);

	switch (releaseType) {
		case "patch":
			return `${major}.${minor}.${patch + 1}`;
		case "minor":
			return `${major}.${minor + 1}.0`;
		case "major":
			return `${major + 1}.0.0`;
		default:
			die(`Unsupported release type: ${releaseType}`);
	}
}

function currentPackageVersion() {
	const cargoToml = readFileSync(rustServiceCargoTomlPath, "utf8");
	const match = cargoToml.match(/^version\s*=\s*"(\d+\.\d+\.\d+)"/m);
	if (!match) {
		die(`Could not find a semantic version in ${rustServiceCargoTomlPath}`);
	}
	return match[1];
}

function updateCargoVersion(filePath, nextVersion) {
	const current = readFileSync(filePath, "utf8");
	const updated = current.replace(/^version\s*=\s*"\d+\.\d+\.\d+"/m, `version = "${nextVersion}"`);
	writeFileSync(filePath, updated);
}

function updateCargoLockVersion(filePath, nextVersion) {
	const current = readFileSync(filePath, "utf8");
	const updated = current.replace(
		/(\[\[package\]\]\nname = "open-recorder-service"\nversion = ")\d+\.\d+\.\d+(")/m,
		`$1${nextVersion}$2`,
	);
	writeFileSync(filePath, updated);
}

function escapeRegExp(value) {
	return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function validatePlist(filePath) {
	const result = spawnSync("plutil", ["-lint", filePath], {
		cwd: repoRoot,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	});

	if (result.status === 0) {
		return;
	}

	const errorText = result.stderr.trim() || result.stdout.trim() || `plutil exited with status ${result.status}`;
	die(errorText);
}

function updatePlistStringValue(content, key, value) {
	const pattern = new RegExp(`(<key>${escapeRegExp(key)}</key>\\s*<string>)([^<]*)(</string>)`);
	if (!pattern.test(content)) {
		die(`Could not find ${key} string value in ${macosInfoPlistPath}`);
	}
	return content.replace(pattern, `$1${value}$3`);
}

function updateMacOSBundleVersion(filePath, nextVersion) {
	let updated = readFileSync(filePath, "utf8");
	updated = updatePlistStringValue(updated, "CFBundleShortVersionString", nextVersion);
	updated = updatePlistStringValue(updated, "CFBundleVersion", nextVersion);
	writeFileSync(filePath, updated);
	validatePlist(filePath);
}

function syncVersionFiles(nextVersion) {
	updateCargoVersion(rustServiceCargoTomlPath, nextVersion);
	if (existsSync(rustServiceCargoLockPath)) {
		updateCargoLockVersion(rustServiceCargoLockPath, nextVersion);
	}
	updateMacOSBundleVersion(macosInfoPlistPath, nextVersion);
}

function determineBaseVersion(packageVersion, latestTagVersion) {
	if (!latestTagVersion) {
		return {
			baseVersion: packageVersion,
			versionSource: "apps/rust-service/Cargo.toml",
		};
	}

	if (compareVersions(packageVersion, latestTagVersion) >= 0) {
		return {
			baseVersion: packageVersion,
			versionSource: "apps/rust-service/Cargo.toml",
		};
	}

	return {
		baseVersion: latestTagVersion,
		versionSource: "git tag",
	};
}

function writeReleasePlan({ tagName, releaseName, releaseNotes, makeLatest }) {
	mkdirSync(dirname(releasePlanPath), { recursive: true });
	writeFileSync(
		releasePlanPath,
		`${JSON.stringify(
			{
				tagName,
				releaseName,
				releaseNotes,
				makeLatest,
			},
			null,
			2,
		)}\n`,
	);
}

function appendGithubOutput(filePath, name, value) {
	if (!filePath) {
		return;
	}

	const stringValue = String(value);
	if (stringValue.includes("\n")) {
		appendFileSync(filePath, `${name}<<__CODEX_EOF__\n${stringValue}\n__CODEX_EOF__\n`);
		return;
	}

	appendFileSync(filePath, `${name}=${stringValue}\n`);
}

function buildPrBody({
	releaseType,
	baseVersion,
	versionSource,
	nextVersion,
	tagName,
	releaseName,
	makeLatest,
	releaseNotes,
}) {
	const lines = [
		"## Release Summary",
		`- Release type: ${releaseType}`,
		`- Base version: ${baseVersion} (${versionSource})`,
		`- Next version: ${nextVersion}`,
		`- Tag: ${tagName}`,
		`- Release title: ${releaseName}`,
		`- Mark as latest: ${makeLatest ? "true" : "false"}`,
		"",
		"Merging this PR will trigger `.github/workflows/release.yml`, which builds the macOS Swift/Rust artifacts and publishes the GitHub release.",
	];

	if (releaseNotes) {
		lines.push("", "## Release Notes", "", releaseNotes);
	}

	return lines.join("\n");
}

const args = parseArgs(process.argv.slice(2));
const packageVersion = currentPackageVersion();
const latestTag = latestSemverTag({ cwd: repoRoot });
const latestTagVersion = latestTag.version;
const { baseVersion, versionSource } = determineBaseVersion(packageVersion, latestTagVersion);
const nextVersion = bumpVersion(baseVersion, args.releaseType);
const tagName = `v${nextVersion}`;
const releaseName = args.name || `Open Recorder v${nextVersion}`;
const makeLatest = args.latest === "true";
const releaseNotes =
	args.notes.trim() ||
	buildCommitReleaseNotes({
		previousTagName: latestTag.tagName,
		toRef: "HEAD",
		cwd: repoRoot,
	});
const branchName = `release/${tagName}`;
const commitMessage = `Prepare release ${tagName}`;
const prTitle = `Prepare release ${tagName}`;
const prBody = buildPrBody({
	releaseType: args.releaseType,
	baseVersion,
	versionSource,
	nextVersion,
	tagName,
	releaseName,
	makeLatest,
	releaseNotes,
});

syncVersionFiles(nextVersion);
writeReleasePlan({
	tagName,
	releaseName,
	releaseNotes,
	makeLatest,
});

appendGithubOutput(args.output, "package_version", packageVersion);
appendGithubOutput(args.output, "latest_tag_version", latestTagVersion);
appendGithubOutput(args.output, "base_version", baseVersion);
appendGithubOutput(args.output, "version_source", versionSource);
appendGithubOutput(args.output, "next_version", nextVersion);
appendGithubOutput(args.output, "tag_name", tagName);
appendGithubOutput(args.output, "release_name", releaseName);
appendGithubOutput(args.output, "release_notes", releaseNotes);
appendGithubOutput(args.output, "make_latest", makeLatest);
appendGithubOutput(args.output, "branch_name", branchName);
appendGithubOutput(args.output, "commit_message", commitMessage);
appendGithubOutput(args.output, "pr_title", prTitle);
appendGithubOutput(args.output, "pr_body", prBody);

console.log(`Prepared release PR files for ${tagName}`);
