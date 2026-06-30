# Open Recorder

<p align="center">
  <img src="./apps/macos/Resources/Branding/open-recorder-brand-image.png" width="220" alt="Open Recorder logo">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-111827?style=for-the-badge" alt="macOS" />
  <img src="https://img.shields.io/badge/Swift%20%2B%20Rust-2563eb?style=for-the-badge" alt="Swift and Rust" />
  <img src="https://img.shields.io/badge/open%20source-Apache%202.0-2563eb?style=for-the-badge" alt="Apache 2.0 license" />
</p>

Open Recorder is a macOS-only screen recorder, screenshot tool, and lightweight editor built as a native Swift app backed by a Rust service.

The product uses a small native stack: Swift owns the macOS experience, capture UI, recording controls, screenshot flow, playback, and Finder/privacy integrations. Rust owns durable local service work such as app paths, project metadata, recording registration, screenshot indexing, and export bookkeeping.

## Features

- Record a display, window, or interactive selected area on macOS
- Capture screenshots from displays, windows, or selected areas
- Choose microphone input, system audio, camera capture, cursor visibility, and click recording before capture
- Save recordings under `~/Movies/Open Recorder`
- Save screenshots under `~/Pictures/Open Recorder`
- Automatically create `.openrecorder` project metadata
- Browse projects in the native project library
- Preview recordings with the native AVKit player
- Export recordings through the Rust service
- Open Screen Recording privacy settings from inside the app

## Editor Capabilities

Open Recorder includes a native editor for turning raw captures into shareable videos and screenshots without leaving the app.

### Video Editor

- **Backgrounds** - place recordings on transparent, solid color, gradient, or bundled wallpaper backgrounds.
- **Framing** - adjust stage padding, background blur, shadow strength, and recording corner roundness.
- **Inset styling** - add an inset treatment around the recording with configurable amount, color, opacity, and balance.
- **Crop and aspect controls** - crop recordings visually and preview/export them in automatic or fixed aspect layouts.
- **Cursor overlays** - show or hide the captured cursor path, loop cursor motion, tune cursor size and smoothing, and choose from system, touch, and emphasis cursor styles.
- **Timeline playback** - use transport controls, frame stepping, hover scrubbing, preview speed controls, and timeline zooming while editing.
- **Zoom sections** - add manual zoom regions from the timeline, set zoom depth, and adjust X/Y focus. The app can also generate automatic zooms from recorded click telemetry.
- **Clip splitting and speed changes** - split the recording at the playhead, select clips, set clip speeds from 1x to 2x, merge adjacent split points, and delete selected clips while preserving at least one playable segment.
- **Camera clips** - when a camera track was recorded, split the camera layer independently, show or hide camera segments, place the facecam in a 3x3 position grid, and adjust camera size and border width per segment.
- **Autosaved edits** - video styling, crop selection, cursor settings, facecam settings, and timeline edits are saved into the `.openrecorder` project metadata.

### Screenshot Editor

- **Composed screenshots** - place screenshots on the same background system used by the video editor.
- **Layer styling** - adjust background padding, background roundness, background shadow, image roundness, and image shadow separately.
- **PNG output** - export the composed screenshot to a file or copy it directly to the clipboard.
- **Project persistence** - screenshot styling is autosaved with the project so the composition can be reopened later.

### Export

- Export styled video projects as MOV or MP4 files, or as animated GIFs.
- Choose 480p, 720p, 1080p, or 4K output presets for movie exports.
- Choose Low, Medium, or High MP4 quality presets.
- Choose Medium, Large, or Original GIF sizing, 15/20/25/30 FPS, and looping behavior.
- Exported videos and GIFs include the selected crop, background styling, inset styling, cursor overlay, timeline speed/deletion edits, zoom effects, and camera clip settings.

## Repository Layout

- `apps/macos` - native SwiftUI macOS app
- `apps/rust-service` - Rust JSON-lines service and one-shot command backend
- `apps/landing` - Next.js landing page for the project

## Build From Source

Requirements:

- macOS
- Xcode command line tools with Swift 6.2+
- Rust 1.93+

Install locked JavaScript dependencies and prefetch Rust crates:

```bash
pnpm run setup
```

Build everything:

```bash
make build-macos
```

Package a local `.app` bundle:

```bash
make package-macos
```

Run the native app:

```bash
make dev-macos
```

Development runs as a separate macOS app:

- `make dev-macos` builds, installs, and launches `/Applications/Open Recorder Dev.app`
- The development bundle identifier is `dev.openrecorder.app.dev`
- Production packaging remains `/Applications/Open Recorder.app` with bundle identifier `dev.openrecorder.app`
- Script entrypoints spell out their role: development scripts use `development`, production/release scripts use `production`, and shared helpers use `shared`.
- Development signing prefers a real development certificate when one is available. Without one, the dev bundle is ad-hoc signed with a stable designated requirement for `dev.openrecorder.app.dev`, so macOS privacy grants are not pinned to each rebuilt executable hash.

This keeps development and production installs from sharing macOS app identity, window state, and privacy permission records.

Run verification:

```bash
make test-macos
```

The root `pnpm dev`, `pnpm build`, and `pnpm test` aliases call those same macOS Swift/Rust targets.

Run the landing page locally:

```bash
pnpm dev:landing
```

## Rust Service Protocol

The Rust service can run as a long-lived JSON-lines process:

```bash
printf '%s\n' '{"id":1,"method":"health","params":{}}' | apps/rust-service/target/debug/open-recorder-service
```

It also supports one-shot calls used by the Swift app:

```bash
apps/rust-service/target/debug/open-recorder-service --oneshot paths '{}'
```

Primary methods:

- `health`
- `paths`
- `prepareRecordingFile`
- `registerRecording`
- `saveProject`
- `listProjects`
- `loadProject`
- `forgetProject`
- `rememberScreenshot`
- `exportRecording`

## macOS Permissions

Screen recording requires macOS Screen Recording permission for the app process. In development, the Swift app can open the relevant privacy pane from Settings. After granting access, restart the app so macOS refreshes the permission state.

## License

Open Recorder is licensed under the Apache License 2.0.
