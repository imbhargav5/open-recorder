#!/usr/bin/env node

import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");
const desktopPackageJsonPath = resolve(repoRoot, "apps", "desktop", "package.json");
const releasePlanPath = resolve(repoRoot, ".github", "release-plan.json");

process.chdir(repoRoot);

function die(message) {
	console.error(`Error: ${message}`);
	process.exit(1);
}

function parseArgs(argv) {
	const args = {
		eventName: "",
		before: "",
		tagName: "",
		releaseName: "",
		releaseNotes: "",
		makeLatest: "",
		output: "",
	};

	for (let index = 0; index < argv.length; index += 1) {
		const arg = argv[index];

		switch (arg) {
			case "--event-name":
				args.eventName = argv[++index] ?? die("--event-name requires a value");
				break;
			case "--before":
				args.before = argv[++index] ?? die("--before requires a value");
				break;
			case "--tag-name":
				args.tagName = argv[++index] ?? die("--tag-name requires a value");
				break;
			case "--release-name":
				args.releaseName = argv[++index] ?? die("--release-name requires a value");
				break;
			case "--release-notes":
				args.releaseNotes = argv[++index] ?? die("--release-notes requires a value");
				break;
			case "--make-latest":
				args.makeLatest = argv[++index] ?? die("--make-latest requires a value");
				break;
			case "--output":
				args.output = argv[++index] ?? die("--output requires a value");
				break;
			case "-h":
			case "--help":
				console.log(`Usage: node scripts/resolve-release-context.mjs --event-name EVENT [options]

Resolves release metadata for .github/workflows/release.yml.

Options:
  --event-name VALUE      GitHub event name, for example push or workflow_dispatch.
  --before VALUE          Previous commit SHA for push events.
  --tag-name VALUE        Manual workflow tag override.
  --release-name VALUE    Manual workflow release title override.
  --release-notes VALUE   Manual workflow release notes override.
  --make-latest VALUE     Manual workflow latest flag override.
  --output PATH           Optional GitHub Actions output file to append to.
  -h, --help              Show this help message.
`);
				process.exit(0);
			default:
				die(`Unknown option: ${arg}`);
		}
	}

	if (!args.eventName) {
		die("--event-name is required");
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

function currentPackageVersion() {
	const packageJson = JSON.parse(readFileSync(desktopPackageJsonPath, "utf8"));
	return packageJson.version;
}

function previousPackageVersion(beforeSha) {
	if (!beforeSha || /^0+$/.test(beforeSha)) {
		return "";
	}

	const packageJson = capture("git", ["show", `${beforeSha}:apps/desktop/package.json`], {
		allowFailure: true,
	});
	if (!packageJson) {
		return "";
	}

	return JSON.parse(packageJson).version;
}

function readReleasePlan() {
	if (!existsSync(releasePlanPath)) {
		return null;
	}

	return JSON.parse(readFileSync(releasePlanPath, "utf8"));
}

function hasVersionChanged(previousVersion, currentVersion) {
	return !previousVersion || previousVersion !== currentVersion;
}

const args = parseArgs(process.argv.slice(2));
const currentVersion = currentPackageVersion();
const defaultTagName = `v${currentVersion}`;
const releasePlan = readReleasePlan();

let shouldRelease = false;
let tagName = defaultTagName;
let releaseName = `Open Recorder ${defaultTagName}`;
let releaseNotes = "";
let makeLatest = "true";

if (args.eventName === "workflow_dispatch") {
	shouldRelease = true;
	tagName = args.tagName || defaultTagName;
	releaseName = args.releaseName || `Open Recorder ${tagName}`;
	releaseNotes = args.releaseNotes;
	makeLatest = args.makeLatest || "true";
} else if (args.eventName === "push") {
	const previousVersion = previousPackageVersion(args.before);
	shouldRelease = hasVersionChanged(previousVersion, currentVersion);

	if (shouldRelease && !releasePlan) {
		die("Push-triggered releases require .github/release-plan.json to match the desktop package version bump.");
	}

	if (releasePlan?.tagName) {
		if (releasePlan.tagName !== defaultTagName) {
			die(`release-plan tag ${releasePlan.tagName} does not match package version ${defaultTagName}`);
		}
		tagName = releasePlan.tagName;
		releaseName = releasePlan.releaseName || `Open Recorder ${tagName}`;
		releaseNotes = releasePlan.releaseNotes || "";
		makeLatest = String(releasePlan.makeLatest ?? true);
	}
} else {
	die(`Unsupported event name: ${args.eventName}`);
}

appendGithubOutput(args.output, "should_release", shouldRelease);
appendGithubOutput(args.output, "tag_name", tagName);
appendGithubOutput(args.output, "release_name", releaseName);
appendGithubOutput(args.output, "release_notes", releaseNotes);
appendGithubOutput(args.output, "make_latest", makeLatest);

console.log(
	shouldRelease
		? `Resolved release metadata for ${tagName}`
		: `No release needed for apps/desktop/package.json version ${currentVersion}`,
);
