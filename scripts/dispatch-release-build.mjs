#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import * as readline from "node:readline";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");

process.chdir(repoRoot);

function die(message) {
	console.error(`Error: ${message}`);
	process.exit(1);
}

function usage() {
	console.log(`Usage: node scripts/dispatch-release-build.mjs [options]

Calculates the next semantic version tag, asks for confirmation, then triggers
the Release Builds GitHub Actions workflow.

Options:
  --release-type VALUE     Release type: patch, minor, or major. Uses a selector if omitted.
  --name VALUE             Release title. Defaults to "Open Recorder v<version>".
  --notes VALUE            Release notes body. Defaults to empty.
  --latest true|false      Whether to mark the release as latest. Defaults to true.
  --yes                    Skip the interactive confirmation prompt.
  --ref VALUE              Git branch that contains the workflow file. Defaults to the current branch.
  --repo OWNER/REPO        GitHub repository slug. Defaults to the current origin remote.
  -h, --help               Show this help message.
`);
}

function parseArgs(argv) {
	const args = {
		releaseType: "",
		name: "",
		notes: "",
		latest: "true",
		yes: false,
		repo: "",
		ref: "",
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
			case "--yes":
				args.yes = true;
				break;
			case "--repo":
				args.repo = argv[++index] ?? die("--repo requires a value");
				break;
			case "--ref":
				args.ref = argv[++index] ?? die("--ref requires a value");
				break;
			case "-h":
			case "--help":
				usage();
				process.exit(0);
			default:
				die(`Unknown option: ${arg}`);
		}
	}

	if (!["", "patch", "minor", "major"].includes(args.releaseType)) {
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

function run(command, args) {
	const result = spawnSync(command, args, {
		cwd: repoRoot,
		stdio: "inherit",
	});

	if (result.status !== 0) {
		process.exit(result.status ?? 1);
	}
}

function worktreeIsClean() {
	return capture("git", ["status", "--short"], { allowFailure: true }) === "";
}

function resolveRepo() {
	const remote = capture("git", ["remote", "get-url", "origin"]);
	const match = remote.match(/(?:git@github\.com:|https:\/\/github\.com\/)(.+?)(?:\.git)?$/);
	if (!match) {
		die("Could not resolve the GitHub repo from the origin remote. Pass --repo OWNER/REPO.");
	}
	return match[1];
}

function currentVersion() {
	const packageJson = JSON.parse(readFileSync("package.json", "utf8"));
	return packageJson.version;
}

function latestSemverTagVersion() {
	const tags = capture("git", ["tag", "--list", "v*", "--sort=-version:refname"], {
		allowFailure: true,
	});

	return tags
		.split(/\r?\n/)
		.map((tag) => /^v(\d+\.\d+\.\d+)$/.exec(tag)?.[1] ?? "")
		.find(Boolean) ?? "";
}

function updateJsonVersion(filePath, nextVersion, spacing) {
	const json = JSON.parse(readFileSync(filePath, "utf8"));
	json.version = nextVersion;
	writeFileSync(filePath, `${JSON.stringify(json, null, spacing)}\n`);
}

function updateTextVersion(filePath, pattern, replacement) {
	const current = readFileSync(filePath, "utf8");
	if (!current.match(pattern)) {
		die(`Could not update version in ${filePath}`);
	}

	const next = current.replace(pattern, replacement);
	writeFileSync(filePath, next);
}

function syncVersionFiles(nextVersion) {
	updateJsonVersion("package.json", nextVersion, "\t");
	updateJsonVersion("package-lock.json", nextVersion, "\t");
	updateTextVersion(
		"src-tauri/Cargo.toml",
		/^version = "\d+\.\d+\.\d+"$/m,
		`version = "${nextVersion}"`,
	);
	updateJsonVersion("src-tauri/tauri.conf.json", nextVersion, 2);
	updateTextVersion(
		"src-tauri/Cargo.lock",
		/(\[\[package\]\]\s+name = "open-recorder"\s+version = ")\d+\.\d+\.\d+(")/m,
		`$1${nextVersion}$2`,
	);
}

function commitVersionBump(nextVersion) {
	const versionFiles = [
		"package.json",
		"package-lock.json",
		"src-tauri/Cargo.toml",
		"src-tauri/tauri.conf.json",
		"src-tauri/Cargo.lock",
	];

	run("git", ["add", ...versionFiles]);

	const staged = capture("git", ["diff", "--cached", "--name-only"]);
	if (!staged) {
		return false;
	}

	run("git", ["commit", "-m", `Bump version to ${nextVersion}`]);
	return true;
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

function clearRenderedMenu(lineCount) {
	if (lineCount <= 0 || !process.stdout.isTTY) {
		return;
	}

	readline.moveCursor(process.stdout, 0, -lineCount);
	readline.clearScreenDown(process.stdout);
}

async function selectReleaseType(baseVersion) {
	if (!process.stdin.isTTY || !process.stdout.isTTY || typeof process.stdin.setRawMode !== "function") {
		die("Interactive release selection requires a TTY. Pass --release-type patch, minor, or major.");
	}

	const choices = [
		{
			label: `patch  bug fixes and small improvements -> v${bumpVersion(baseVersion, "patch")}`,
			value: "patch",
		},
		{
			label: `minor  new features without breaking changes -> v${bumpVersion(baseVersion, "minor")}`,
			value: "minor",
		},
		{
			label: `major  breaking changes -> v${bumpVersion(baseVersion, "major")}`,
			value: "major",
		},
	];

	return await new Promise((resolveChoice, rejectChoice) => {
		let selectedIndex = 0;
		let renderedLineCount = 0;

		const render = () => {
			clearRenderedMenu(renderedLineCount);

			const lines = [
				"Choose the release type (use arrow keys, press Enter):",
				"",
				...choices.map((choice, index) => `${index === selectedIndex ? ">" : " "} ${choice.label}`),
			];

			process.stdout.write(lines.join("\n"));
			renderedLineCount = lines.length;
		};

		const cleanup = () => {
			process.stdin.off("data", onData);
			process.stdin.setRawMode(false);
			process.stdin.pause();
			process.stdout.write("\n");
		};

		const onData = (buffer) => {
			const key = buffer.toString("utf8");

			if (key === "\u0003") {
				cleanup();
				rejectChoice(new Error("Aborted."));
				return;
			}

			if (key === "\r" || key === "\n") {
				const selectedChoice = choices[selectedIndex];
				cleanup();
				resolveChoice(selectedChoice.value);
				return;
			}

			if (key === "\u001b[A" || key.toLowerCase() === "k") {
				selectedIndex = (selectedIndex - 1 + choices.length) % choices.length;
				render();
				return;
			}

			if (key === "\u001b[B" || key.toLowerCase() === "j") {
				selectedIndex = (selectedIndex + 1) % choices.length;
				render();
			}
		};

		process.stdin.setRawMode(true);
		process.stdin.resume();
		process.stdin.on("data", onData);
		render();
	});
}

async function confirmPrompt(message, defaultValue = true) {
	if (!process.stdin.isTTY || !process.stdout.isTTY) {
		die("Interactive confirmation requires a TTY.");
	}

	const rl = createInterface({
		input: process.stdin,
		output: process.stdout,
	});

	const suffix = defaultValue ? "[Y/n]" : "[y/N]";
	const answer = (await rl.question(`${message} ${suffix} `)).trim().toLowerCase();
	rl.close();

	if (!answer) {
		return defaultValue;
	}

	return answer === "y" || answer === "yes";
}

async function chooseReleaseType(baseVersion) {
	return selectReleaseType(baseVersion);
}

async function main() {
	const args = parseArgs(process.argv.slice(2));

	capture("gh", ["auth", "status"]);
	capture("git", ["fetch", "--tags", "origin"]);

	const repo = args.repo || resolveRepo();
	const currentBranch = capture("git", ["branch", "--show-current"]);
	if (!currentBranch) {
		die("Could not determine the current git branch.");
	}

	const ref = args.ref || currentBranch;
	if (ref !== currentBranch) {
		die(`Current branch is ${currentBranch}, but --ref was ${ref}. Checkout ${ref} before dispatching.`);
	}

	if (!worktreeIsClean()) {
		die("Git worktree is dirty. Commit or stash your changes before dispatching a release.");
	}

	const packageVersion = currentVersion();
	const latestTagVersion = latestSemverTagVersion();

	const baseVersion = latestTagVersion || packageVersion;
	const versionSource = latestTagVersion ? "git tag" : "package.json";

	const releaseType = args.releaseType || (await chooseReleaseType(baseVersion));
	const nextVersion = bumpVersion(baseVersion, releaseType);
	const tag = `v${nextVersion}`;
	const name = args.name || `Open Recorder v${nextVersion}`;

	console.log(`Current package.json version: ${packageVersion}`);
	console.log(`Latest local release tag: ${latestTagVersion ? `v${latestTagVersion}` : "none"}`);
	console.log(`Using base version from ${versionSource}: ${baseVersion}`);
	console.log(`Selected release type: ${releaseType}`);
	console.log(`Syncing version files to: ${nextVersion}`);
	console.log(`Calculated release tag: ${tag}`);

	const confirmed = args.yes
		? true
		: await confirmPrompt(`Dispatch release workflow for ${tag}?`, true);

	if (!confirmed) {
		die("Aborted.");
	}

	syncVersionFiles(nextVersion);
	const createdVersionCommit = commitVersionBump(nextVersion);

	console.log(createdVersionCommit ? `Created version bump commit for ${nextVersion}.` : "Version files already matched the release version.");
	console.log(`Pushing ${ref} to origin...`);
	run("git", ["push", "origin", ref]);

	console.log(`Dispatching Release Builds workflow for ${repo}`);
	console.log(`Tag: ${tag}`);
	console.log(`Release title: ${name}`);
	console.log(`Git ref: ${ref}`);

	const workflowArgs = [
		"workflow",
		"run",
		"release.yml",
		"--repo",
		repo,
		"-f",
		`tag_name=${tag}`,
		"-f",
		`release_name=${name}`,
		"-f",
		`release_notes=${args.notes}`,
		"-f",
		`make_latest=${args.latest}`,
	];

	if (ref) {
		workflowArgs.push("--ref", ref);
	}

	run("gh", workflowArgs);

	console.log("");
	console.log(`Workflow dispatched.`);
	console.log(`Check status with: gh run list --repo ${repo} --workflow release.yml --limit 5`);
}

main().catch((error) => {
	if (error instanceof Error && error.message === "Aborted.") {
		die("Aborted.");
	}

	const message = error instanceof Error ? error.message : String(error);
	die(message);
});
