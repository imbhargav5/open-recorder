# Open Recorder

<p align="center">
  <img src="./apps/macos/Resources/Branding/open-recorder-brand-image.png" width="220" alt="Open Recorder logo">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-111827?style=for-the-badge" alt="macOS" />
  <img src="https://img.shields.io/badge/Swift%20%2B%20Rust-2563eb?style=for-the-badge" alt="Swift and Rust" />
  <img src="https://img.shields.io/badge/open%20source-MIT-2563eb?style=for-the-badge" alt="MIT license" />
</p>

Open Recorder is now a macOS-only screen recorder, screenshot tool, and lightweight editor built as a native Swift app backed by a Rust service.

The product uses a small native stack: Swift owns the macOS experience, capture UI, recording controls, screenshot flow, playback, and Finder/privacy integrations. Rust owns durable local service work such as app paths, project metadata, recording registration, screenshot indexing, and export bookkeeping.

## Features

- Record a display, window, or interactive selected area on macOS
- Capture screenshots from displays, windows, or selected areas
- Save recordings under `~/Movies/Open Recorder`
- Save screenshots under `~/Pictures/Open Recorder`
- Automatically create `.openrecorder` project metadata
- Browse projects in the native project library
- Preview recordings with the native AVKit player
- Export recordings through the Rust service
- Open Screen Recording privacy settings from inside the app

## Repository Layout

- `apps/macos` - native SwiftUI macOS app
- `apps/rust-service` - Rust JSON-lines service and one-shot command backend

## Build From Source

Requirements:

- macOS
- Xcode command line tools with Swift 6.2+
- Rust 1.93+

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

Run verification:

```bash
make test-macos
```

The root `pnpm dev`, `pnpm build`, and `pnpm test` aliases now call those same macOS Swift/Rust targets.

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

Open Recorder is licensed under the MIT License.
