import { spawnSync } from "node:child_process";

function die(message) {
	throw new Error(message);
}

export function captureGit(args, { cwd = process.cwd(), allowFailure = false } = {}) {
	const result = spawnSync("git", args, {
		cwd,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	});

	if (result.status === 0) {
		return result.stdout.trim();
	}

	if (allowFailure) {
		return "";
	}

	const errorText = result.stderr.trim() || result.stdout.trim() || `git exited with status ${result.status}`;
	die(errorText);
}

export function semverTagVersion(tagName) {
	return /^v(\d+\.\d+\.\d+)$/.exec(tagName)?.[1] ?? "";
}

export function latestSemverTag({ cwd = process.cwd(), excludedTagNames = [] } = {}) {
	const excludedTags = new Set(excludedTagNames.filter(Boolean));
	const tags = captureGit(["tag", "--list", "v*", "--sort=-version:refname"], {
		cwd,
		allowFailure: true,
	});

	for (const tagName of tags.split(/\r?\n/)) {
		const version = semverTagVersion(tagName);
		if (version && !excludedTags.has(tagName)) {
			return { tagName, version };
		}
	}

	return { tagName: "", version: "" };
}

export function buildCommitReleaseNotes({ previousTagName, toRef = "HEAD", cwd = process.cwd() } = {}) {
	const range = previousTagName ? `${previousTagName}..${toRef}` : toRef;
	const logOutput = captureGit(["log", range, "--format=%h%x09%s"], {
		cwd,
		allowFailure: true,
	});
	const heading = previousTagName ? `## Commits since ${previousTagName}` : "## Commits";
	const commits = logOutput
		.split(/\r?\n/)
		.map((line) => line.trim())
		.filter(Boolean)
		.map((line) => {
			const separatorIndex = line.indexOf("\t");
			if (separatorIndex === -1) {
				return `- ${line}`;
			}

			const shortSha = line.slice(0, separatorIndex);
			const subject = line.slice(separatorIndex + 1);
			return `- ${shortSha} ${subject}`;
		});

	if (commits.length === 0) {
		const emptyMessage = previousTagName
			? `No commits found after ${previousTagName}.`
			: "No commits found for this release.";
		return [heading, "", emptyMessage].join("\n");
	}

	return [heading, "", ...commits].join("\n");
}
