#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import * as readline from "node:readline";
import { createInterface } from "node:readline/promises";

function die(message) {
	console.error(`Error: ${message}`);
	process.exit(1);
}

function usage() {
	console.log(`Usage: node scripts/dispatch-release-build.mjs [options]

Dispatches the release PR GitHub Actions workflow. That workflow computes the
next semantic version, updates the desktop version files, and opens or updates
the release PR. Merging that PR triggers the actual Release Tauri App workflow.

Options:
  --release-type VALUE     Release type: patch, minor, or major. Uses a selector if omitted.
  --name VALUE             Optional release title override.
  --notes VALUE            Optional release notes body.
  --latest true|false      Whether the eventual release should be marked latest. Defaults to true.
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
			case "--":
				break;
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
		stdio: "inherit",
	});

	if (result.status !== 0) {
		process.exit(result.status ?? 1);
	}
}

function resolveRepo() {
	const remote = capture("git", ["remote", "get-url", "origin"]);
	const match = remote.match(/(?:git@github\.com:|https:\/\/github\.com\/)(.+?)(?:\.git)?$/);
	if (!match) {
		die("Could not resolve the GitHub repo from the origin remote. Pass --repo OWNER/REPO.");
	}
	return match[1];
}

function currentBranch() {
	return capture("git", ["branch", "--show-current"], { allowFailure: true });
}

function readDesktopVersionForRef(ref) {
	const packageJson = capture("git", ["show", `${ref}:apps/desktop/package.json`], {
		allowFailure: true,
	});
	if (!packageJson) {
		return "";
	}

	try {
		return JSON.parse(packageJson).version;
	} catch {
		return "";
	}
}

function clearRenderedMenu(lineCount) {
	if (lineCount <= 0 || !process.stdout.isTTY) {
		return;
	}

	readline.moveCursor(process.stdout, 0, -lineCount);
	readline.clearScreenDown(process.stdout);
}

async function selectReleaseType() {
	if (!process.stdin.isTTY || !process.stdout.isTTY || typeof process.stdin.setRawMode !== "function") {
		die("Interactive release selection requires a TTY. Pass --release-type patch, minor, or major.");
	}

	const choices = [
		{
			label: "patch  bug fixes and small improvements",
			value: "patch",
		},
		{
			label: "minor  new features without breaking changes",
			value: "minor",
		},
		{
			label: "major  breaking changes",
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

async function main() {
	const args = parseArgs(process.argv.slice(2));

	capture("gh", ["auth", "status"]);

	const repo = args.repo || resolveRepo();
	const branch = currentBranch();
	const ref = args.ref || branch;
	if (!ref) {
		die("Could not determine the git ref. Pass --ref with the branch that contains the workflow file.");
	}

	const releaseType = args.releaseType || (await selectReleaseType());
	const desktopVersion = readDesktopVersionForRef(ref);

	console.log(`Dispatching release PR workflow for repository: ${repo}`);
	console.log(`Git ref: ${ref}`);
	console.log(`Selected release type: ${releaseType}`);
	if (desktopVersion) {
		console.log(`Current desktop package version on ${ref}: ${desktopVersion}`);
	}
	console.log("The workflow will compute the next version, update version files in GitHub Actions, and open or update the release PR.");

	const confirmed = args.yes
		? true
		: await confirmPrompt(`Dispatch release PR workflow for a ${releaseType} release on ${ref}?`, true);

	if (!confirmed) {
		die("Aborted.");
	}

	const workflowArgs = [
		"workflow",
		"run",
		"release-pr.yml",
		"--repo",
		repo,
		"-f",
		`release_type=${releaseType}`,
		"-f",
		`release_name=${args.name}`,
		"-f",
		`release_notes=${args.notes}`,
		"-f",
		`make_latest=${args.latest}`,
		"-f",
		`base_ref=${ref}`,
		"--ref",
		ref,
	];

	run("gh", workflowArgs);

	console.log("");
	console.log("Workflow dispatched.");
	console.log("GitHub Actions will compute the next version, create or update the release PR, and wait for that PR to be merged before publishing the release.");
	console.log(`Check status with: gh run list --repo ${repo} --workflow release-pr.yml --limit 5`);
}

main().catch((error) => {
	if (error instanceof Error && error.message === "Aborted.") {
		die("Aborted.");
	}

	const message = error instanceof Error ? error.message : String(error);
	die(message);
});
