---
name: publish-github-release
description: Publish an Open Recorder GitHub release by choosing a patch, minor, or major version bump, running the repository release scripts, and dispatching the Release Tauri App workflow. Use when the user asks to cut, ship, dispatch, or publish a GitHub release, or to bump the app version for a release.
compatibility: Requires this repository, git, the GitHub CLI with working auth, network access, push access to the repo, and a clean git worktree.
---

# Publish GitHub Release

Use this skill when the user wants to publish an Open Recorder release from this repository.

## Quick start

Pick the script that matches the release type:

```bash
pnpm release:patch
pnpm release:minor
pnpm release:major
```

If the user wants to choose interactively, use:

```bash
pnpm release:dispatch
```

## Preconditions

Before running a release command:

1. Make sure the repo is on the branch the user wants to release from.
2. Make sure the git worktree is clean.
3. Make sure `gh auth status` succeeds.
4. If this release needs signed macOS artifacts and secrets are not configured yet, run:

```bash
pnpm release:setup-macos-signing
```

## Release type guidance

- `patch`: bug fixes, small polish, or safe maintenance updates.
- `minor`: new backward-compatible features.
- `major`: breaking changes or compatibility resets.

## Useful command patterns

You can pass extra flags through pnpm with `--`:

```bash
pnpm release:patch -- --notes "Bug fixes and stability improvements"
pnpm release:minor -- --name "Open Recorder v1.4.0" --yes
pnpm release:major -- --latest false
```

Supported flags come from `scripts/dispatch-release-build.mjs`:

- `--notes VALUE`
- `--name VALUE`
- `--latest true|false`
- `--yes`
- `--ref VALUE`
- `--repo OWNER/REPO`

## What the skill should do

1. Confirm the intended release type if the user did not already specify patch, minor, or major.
2. Check the preconditions above.
3. Run the matching root workspace script.
4. Report the calculated version tag and whether the workflow dispatch succeeded.
5. If the user asks how the release process works or something fails, read [references/release-process.md](references/release-process.md).

## Important behaviors

- The dispatcher fetches tags and uses the latest `v*` semver tag as the base version when available.
- It updates version files, creates a `Bump version to <version>` commit, and pushes the current branch before dispatching the workflow.
- It will stop immediately on a dirty worktree or missing GitHub CLI auth.
