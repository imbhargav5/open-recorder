# Open Recorder Release Process

This reference explains how the repository release scripts work and how to use them.

## Package scripts

The main dispatcher is:

```bash
pnpm release:dispatch
```

It opens an interactive selector so you can choose:

- `patch`
- `minor`
- `major`

There are also direct wrappers for each release type:

```bash
pnpm release:patch
pnpm release:minor
pnpm release:major
```

Those root workspace wrappers call the same script with:

- `release:patch` -> `node scripts/dispatch-release-build.mjs --release-type patch`
- `release:minor` -> `node scripts/dispatch-release-build.mjs --release-type minor`
- `release:major` -> `node scripts/dispatch-release-build.mjs --release-type major`

Extra flags can still be passed after `--`:

```bash
pnpm release:patch -- --notes "Bug fixes and stability improvements"
pnpm release:minor -- --name "Open Recorder v1.4.0" --yes
pnpm release:major -- --latest false
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

The local dispatcher does the following:

1. Changes into the repo root.
2. Verifies GitHub CLI auth with `gh auth status`.
3. Resolves the repo slug from the `origin` remote unless `--repo` was supplied.
4. Resolves the target branch from `--ref` or the current branch.
5. Dispatches `.github/workflows/release-pr.yml` through `gh workflow run`.
6. Leaves the local worktree untouched.

`.github/workflows/release-pr.yml` then:

1. Checks out the requested base branch.
2. Fetches tags from `origin`.
3. Reads `apps/desktop/package.json` for the current version.
4. Looks for the latest local semver tag matching `v*`.
5. Uses the newer of those two versions as the base version.
6. Computes the next version:
   - patch -> increments patch
   - minor -> increments minor and resets patch to `0`
   - major -> increments major and resets minor and patch to `0`
7. Updates all release version files:
   - `apps/desktop/package.json`
   - `apps/desktop/src-tauri/Cargo.toml`
   - `apps/desktop/src-tauri/tauri.conf.json`
   - `apps/desktop/src-tauri/Cargo.lock` for the `open-recorder` package entry
8. Writes `.github/release-plan.json` with:
   - `tagName`
   - `releaseName`
   - `releaseNotes`
   - `makeLatest`
9. Opens or updates the release PR.

## Release workflow behavior after merge

Once the release PR is merged to `main`, `.github/workflows/release.yml` runs automatically.

That workflow:

1. Detects that `apps/desktop/package.json` changed on `main`.
2. Confirms the version actually changed.
3. Reads `.github/release-plan.json` for release metadata when it exists.
4. Builds macOS arm64.
5. Builds macOS x64.
6. Builds Windows x64.
7. Builds Linux x64.
8. Downloads and renames the uploaded artifacts into stable release filenames.
9. Generates `latest.json` for the auto-updater using the current tag and uploaded signatures.
10. Creates or updates the GitHub release with `ncipollo/release-action`.

The workflow still supports manual `workflow_dispatch` as a fallback, but the normal path is:

1. Run `pnpm release:patch`, `pnpm release:minor`, `pnpm release:major`, or `pnpm release:dispatch`.
2. Let GitHub Actions open or update the release PR.
3. Merge the release PR.
4. Let `.github/workflows/release.yml` publish the release.

## Practical release commands

Use these when you already know the release type:

```bash
pnpm release:patch
pnpm release:minor
pnpm release:major
```

Use this when you want the selector:

```bash
pnpm release:dispatch
```

Use this first if signing secrets still need to be uploaded:

```bash
pnpm release:setup-macos-signing
```

## Common failure modes

- `gh auth status` fails: run `gh auth login`.
- Wrong branch checked out: switch to the branch you intend to base the release PR on, or pass `--ref`.
- Missing signing secrets: run `pnpm release:setup-macos-signing` or configure the required GitHub secrets manually.
- Missing workflow permission: the release PR workflow cannot be dispatched.
- Missing merge step: the release PR exists, but no release is published until that PR is merged to `main`.
