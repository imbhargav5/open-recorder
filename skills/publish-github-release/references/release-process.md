# Open Recorder Release Process

This reference explains how the repository release scripts work and how to use them.

## Package scripts

The main dispatcher is:

```bash
npm run release:dispatch
```

It opens an interactive selector so you can choose:

- `patch`
- `minor`
- `major`

There are also direct wrappers for each release type:

```bash
npm run release:patch
npm run release:minor
npm run release:major
```

Those wrappers call the same script with:

- `release:patch` -> `node scripts/dispatch-release-build.mjs --release-type patch`
- `release:minor` -> `node scripts/dispatch-release-build.mjs --release-type minor`
- `release:major` -> `node scripts/dispatch-release-build.mjs --release-type major`

Extra flags can still be passed after `--`:

```bash
npm run release:patch -- --notes "Bug fixes and stability improvements"
npm run release:minor -- --name "Open Recorder v1.4.0" --yes
npm run release:major -- --latest false
```

## Supported dispatcher flags

From `scripts/dispatch-release-build.mjs`:

- `--release-type patch|minor|major`
- `--name VALUE`
- `--notes VALUE`
- `--latest true|false`
- `--yes`
- `--ref VALUE`
- `--repo OWNER/REPO`

## Internal flow

The dispatcher does the following:

1. Changes into the repo root.
2. Verifies GitHub CLI auth with `gh auth status`.
3. Fetches tags from `origin` with `git fetch --tags origin`.
4. Resolves the repo slug from the `origin` remote unless `--repo` was supplied.
5. Reads the current branch and rejects mismatched `--ref` values.
6. Refuses to continue if `git status --short` is not empty.
7. Reads `package.json` for the current version.
8. Looks for the latest local semver tag matching `v*`.
9. Uses the latest tag as the base version when present, otherwise falls back to `package.json`.
10. Computes the next version:
    - patch -> increments patch
    - minor -> increments minor and resets patch to `0`
    - major -> increments major and resets minor and patch to `0`
11. Updates all release version files:
    - `package.json`
    - `package-lock.json`
    - `src-tauri/Cargo.toml`
    - `src-tauri/tauri.conf.json`
    - `src-tauri/Cargo.lock` for the `open-recorder` package entry
12. Stages those files.
13. Creates a git commit named `Bump version to <nextVersion>` if there are staged changes.
14. Pushes the current branch to `origin`.
15. Dispatches `.github/workflows/release.yml` through `gh workflow run`.

## GitHub Actions workflow behavior

`.github/workflows/release.yml` accepts:

- `tag_name`
- `release_name`
- `release_notes`
- `make_latest`

The workflow then:

1. Builds macOS arm64.
2. Builds macOS x64.
3. Builds Windows x64.
4. Builds Linux x64.
5. Downloads all artifacts in the `publish-release` job.
6. Renames the uploaded artifacts into stable release filenames.
7. Generates `latest.json` for the auto-updater using the current tag and uploaded signatures.
8. Creates or updates the GitHub release with `ncipollo/release-action`.

## Practical release commands

Use these when you already know the release type:

```bash
npm run release:patch
npm run release:minor
npm run release:major
```

Use this when you want the selector:

```bash
npm run release:dispatch
```

Use this first if signing secrets still need to be uploaded:

```bash
npm run release:setup-macos-signing
```

## Common failure modes

- Dirty worktree: commit or stash local changes first.
- `gh auth status` fails: run `gh auth login`.
- Wrong branch checked out: switch to the branch you intend to release from.
- Missing signing secrets: run `npm run release:setup-macos-signing` or configure the required GitHub secrets manually.
- Missing push permission: the version bump commit cannot be pushed, so the workflow is never dispatched.
