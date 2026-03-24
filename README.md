# Open Recorder

<p align="center">
  <img src="./branding/source-assets/open-recorder-brand-image.png" width="220" alt="Open Recorder logo">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS%20%7C%20Windows%20%7C%20Linux-111827?style=for-the-badge" alt="macOS Windows Linux" />
  <img src="https://img.shields.io/badge/open%20source-MIT-2563eb?style=for-the-badge" alt="MIT license" />
</p>

### Create polished, pro-grade screen recordings and screenshots.
[Open Recorder](https://github.com/imbhargav5/open-recorder) is an **open-source screen recorder, screenshot tool, and editor** for creating **polished walkthroughs, demos, tutorials, and product videos**. Contribution encouraged.

<p align="center">
  <img src="./open-recorder-demo.gif" width="750" alt="Open Recorder demo video">
</p>

---
## What is Open Recorder?

Open Recorder lets you record your screen and capture screenshots, automatically transforming recordings into polished videos. It handles the heavy lifting of zooming into important actions and smoothing out jittery cursor movement so your demos look professional by default. Screenshots can be styled with custom backgrounds, padding, rounded corners, and shadows before saving or copying to clipboard.

Open Recorder runs on:

- **macOS**
- **Windows**
- **Linux**

Linux currently uses the browser capture path, which means the OS cursor cannot always be hidden during recording.



---

# Features

### Recording

- Record an entire screen or a single window
- Jump straight from recording into the editor
- Microphone or system audio recording
- Chromium capture APIs on Windows/Linux
- Native **ScreenCaptureKit** capture on macOS
- native WGC recording helper for display and app-window capture on Windows, native WASAPI for system/mic audio, and more

### Smart Motion

- Apple-style zoom animations
- Automatic zoom suggestions based on cursor activity
- Manual zoom regions
- Smooth pan transitions between zoom regions

### Cursor Controls

- Adjustable cursor size
- Cursor smoothing
- Motion blur
- Click bounce animation
- macOS-style cursor assets

### Cursor Loops
<p>
  <img src="./CursorLoop.gif" width="450" alt="Open Recorder demo video">
</p>

- Cursor returns to original position in a freeze-frame at end of video/GIF (off by default)

### Editing Tools

- Timeline trimming
- Speed-up / slow-down regions
- Annotations
- Zoom spans
- Project save + reopen (`.openrecorder` files, with `.openscreen` backward compatibility)

### Frame Styling

- Wallpapers
- Gradients
- Solid fills
- Padding
- Rounded corners
- Blur
- Drop shadows

### Screenshots

- Capture entire screen, a specific window, or a custom selected area
- Built-in image editor opens automatically after capture
- Background styling: wallpapers, gradients, solid colors, or transparent
- Adjustable padding, border radius, and shadow intensity
- Save as PNG or copy directly to clipboard
- Uses native `screencapture` on macOS for high-quality, silent captures

### Export

- MP4 video export
- GIF export
- Aspect ratio controls
- Quality settings

---

# Screenshots

<p align="center">
  <img src="https://i.postimg.cc/d0t09ypT/Screenshot-2026-03-09-at-8-10-08-pm.png" width="700" alt="Open Recorder editor screenshot">
</p>

<p align="center">
  <img src="https://i.postimg.cc/YSgdbvFj/Screenshot-2026-03-09-at-8-49-14-pm.png" width="700" alt="Open Recorder recording interface screenshot">
</p>

---

# Installation

## Download a build

Prebuilt releases are available here:

https://github.com/imbhargav5/open-recorder/releases

## Homebrew (Cask)

Open Recorder is distributed as a GUI app, so Homebrew support is done via cask.

For users:

```bash
brew tap imbhargav5/tap
brew install --cask open-recorder
```

---

## Build from source

```bash
git clone https://github.com/imbhargav5/open-recorder.git
cd open-recorder
pnpm install
pnpm dev
```

`pnpm dev` launches the desktop workspace app from `apps/desktop` using the root compatibility alias, and still uses the separate `Open Recorder Dev` app identity so it can coexist with the production app.

If you want to run the production identity from source instead, use:

```bash
pnpm dev:prod
```

---

## Signed macOS releases in GitHub Actions

The manual release workflow at `.github/workflows/release.yml` uses Tauri to produce signed and notarized macOS DMGs, Windows NSIS installers, and Linux AppImages when these GitHub repository secrets are configured:

- `APPLE_CERTIFICATE`: base64-encoded `Developer ID Application` `.p12` certificate export
- `APPLE_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`
- `APPLE_SIGNING_IDENTITY`: signing identity name
- `APPLE_ID`: Apple Developer account email
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization
- `APPLE_TEAM_ID`: your Apple Developer team ID
- `TAURI_SIGNING_PRIVATE_KEY`: Tauri updater signing private key
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`: password for the signing key (optional)

This repo now includes two helper scripts:

```bash
pnpm release:setup-macos-signing
pnpm release:dispatch
pnpm release:patch
pnpm release:minor
pnpm release:major
```

`release:setup-macos-signing` detects the local `Developer ID Application` identity, exports a `.p12`, and uploads the GitHub secrets.

`release:dispatch` uses an interactive selector to choose patch, minor, or major, calculates the next version from the latest release tag, updates the version files, commits and pushes that bump, and then dispatches the `Release Builds` workflow.

Use the explicit helpers when you already know the release type:

```bash
pnpm release:patch
pnpm release:minor
pnpm release:major
```

All three scripts call the same dispatcher under the hood and still support extra flags after `--`, for example:

```bash
pnpm release:patch -- --notes "Bug fixes and stability improvements"
pnpm release:minor -- --name "Open Recorder v1.4.0" --yes
pnpm release:major -- --latest false
```

Internally, the dispatcher:

1. Verifies `gh auth status` works and fetches tags from `origin`.
2. Refuses to continue if the git worktree is dirty or the current branch does not match `--ref`.
3. Picks the base version from the latest local `v*` tag, or falls back to `apps/desktop/package.json` if there are no release tags yet.
4. Bumps the version as patch, minor, or major.
5. Syncs `apps/desktop/package.json`, `apps/desktop/src-tauri/Cargo.toml`, `apps/desktop/src-tauri/tauri.conf.json`, and the `open-recorder` entry inside `apps/desktop/src-tauri/Cargo.lock`.
6. Creates a `Bump version to <version>` commit and pushes the current branch.
7. Dispatches `.github/workflows/release.yml`, which builds macOS arm64, macOS x64, Windows x64, and Linux x64 artifacts, generates `latest.json` for the updater, and creates or updates the GitHub release.

There is also a project skill at `skills/publish-github-release/` that captures this release flow for compatible agents.

Make sure `gh auth login` succeeds before running the release dispatch flow.

---

## macOS: "App cannot be opened"

Local source builds are not signed or notarized by default. macOS may quarantine apps built on your machine.

Remove the quarantine flag with:

```bash
xattr -rd com.apple.quarantine "/Applications/Open Recorder.app"
```

---

# Usage

## Screenshot

1. Launch Open Recorder
2. Choose **Screenshot** from the HUD overlay
3. Select a capture mode: **Screen**, **Window**, or **Area**
4. Click **Take Screenshot**
5. The image editor opens automatically with your capture
6. Customize the background (wallpaper, gradient, solid color, or transparent)
7. Adjust padding, border radius, and shadow intensity
8. **Save as PNG** or **Copy to clipboard**

---

## Record

1. Launch Open Recorder
2. Select a screen or window
3. Choose audio recording options
4. Start recording
5. Stop recording to open the editor

---

## Edit

Inside the editor you can:

- Add zoom regions manually
- Use automatic zoom suggestions
- Adjust cursor behavior
- Trim the video
- Add speed changes
- Add annotations
- Style the frame

Save your work anytime as an `.openrecorder` project.

---

## Export

Export options include:

- **MP4** for full-quality video
- **GIF** for lightweight sharing

Adjust:

- Aspect ratio
- Output resolution
- Quality settings

---

# Limitations

### Linux Cursor Capture

The browser capture API used on Linux does not allow hiding the system cursor during recording.

If you enable the animated cursor layer, recordings may contain **two cursors**.

Improving cross-platform cursor capture is an area where contributions are welcome.

---

### System Audio

System audio capture depends on platform support.

**Windows**
- Works out of the box

**Linux**
- Requires PipeWire (Ubuntu 22.04+, Fedora 34+)
- Older PulseAudio setups may not support system audio

**macOS**
- Requires macOS 12.3+
- Uses ScreenCaptureKit helper

---

# How It Works

Open Recorder is a **desktop video editor with a renderer-driven motion pipeline and platform-specific capture layer**.

**Capture**
- Tauri orchestrates recording
- macOS uses native ScreenCaptureKit helpers for capture and cursor telemetry
- Windows uses native WGC for screen capture
- Linux uses FFmpeg-based capture with browser fallback

**Motion**
- Zoom regions
- Cursor tracking
- Speed changes
- Timeline edits

**Rendering**
- Scene composition handled by **PixiJS**

**Export**
- Frames rendered through the same scene pipeline
- Encoded to MP4 or GIF

**Projects**
- `.openrecorder` files store the source video path and editor state

---

# Performance

Open Recorder is an opensource, blazing fast ScreenStudio alternative. Built with **Tauri and Rust**, it is highly performant but very small in size compared to its competitors. It adds auto-zoom, cursor animations, and more to your screen recordings — all without the overhead of traditional Electron-based tools.

### Lightweight Native Architecture

Unlike Electron apps that bundle an entire Chromium browser, Open Recorder uses **Tauri** — a Rust-based framework that leverages the operating system's native webview. This means:

- **Dramatically smaller binary size** — the app ships without a bundled browser engine, keeping the installer compact compared to Electron alternatives
- **Lower baseline memory usage** — no separate Chromium process tree consuming hundreds of megabytes at idle
- **Rust-powered backend** — the core orchestration layer is written in Rust with async I/O via Tokio, providing near-zero overhead for system-level operations like file handling, process management, and native API bridging

### Native Platform Capture — No Browser Bottleneck

Open Recorder bypasses slow browser-based capture APIs wherever possible by using **platform-specific native capture**:

- **macOS**: Uses Apple's **ScreenCaptureKit** framework directly via a native Swift sidecar, delivering hardware-optimized screen capture with cursor telemetry at minimal CPU cost
- **Windows**: Uses the native **Windows.Graphics.Capture (WGC)** API through a dedicated sidecar for display and app-window capture, plus native **WASAPI** for system and microphone audio
- **Linux**: FFmpeg-based capture pipeline with browser fallback

These native capture paths run outside the main application process as lightweight sidecar binaries, keeping the UI thread responsive during recording.

### Streaming Decoder — Single-Pass Frame Processing

The export pipeline uses a **streaming forward-pass decoder** built on the WebCodecs `VideoDecoder` API and `web-demuxer`. Instead of seeking to each frame individually (which is extremely slow with compressed video), Open Recorder decodes frames in a single continuous pass:

- Frames flow through the decoder in order — no costly random seeks into the compressed bitstream
- Trimmed regions are decoded (necessary for P-frame and B-frame reference chains) but their output is discarded immediately, avoiding unnecessary rendering work
- Frames are resampled to the target frame rate during the same streaming pass, eliminating a separate processing step

This architecture is **significantly faster than seek-per-frame approaches**, especially for longer recordings.

### Hardware-Accelerated Video Encoding

Export uses the **WebCodecs API** with `hardwareAcceleration: 'prefer-hardware'`, offloading H.264 encoding to the GPU when available:

- Encodes to `avc1.640033` (H.264 High Profile) for broad compatibility
- **Variable bitrate** mode adapts quality dynamically — 30 Mbps at 1080p, scaling up to 80 Mbps at 5K+ resolutions
- A deep encode queue of **120 frames** keeps the hardware encoder saturated for maximum throughput
- Falls back gracefully to software encoding when GPU encoding is unavailable

### Efficient Rendering with PixiJS

All frame composition — video, cursor, annotations, zoom transforms — is handled by **PixiJS**, a GPU-accelerated 2D rendering engine:

- Separate canvas layers for background, scene content, and shadow compositing avoid redundant GPU draw calls
- Textures are destroyed immediately after replacement, preventing GPU memory leaks during long exports
- Drop shadows use lightweight CSS `drop-shadow()` filters composited on a separate canvas, rather than expensive per-frame GPU shader passes

### Math-Driven Smooth Animations

Cursor smoothing, zoom transitions, and pan animations all use **spring physics** (via the `motion` library) rather than simple linear interpolation:

- Custom stiffness and damping parameters produce natural, Apple-style motion curves
- Stationary detection with configurable snap behavior (52ms delay, sub-pixel epsilon) eliminates visual jitter when the cursor pauses
- Deadzone filtering on zoom scale and translation prevents micro-jitters from triggering unnecessary re-renders
- Motion blur intensity is computed directly from cursor velocity, applied only when meaningful

### Optimized Build Pipeline

The production build is tuned for minimal bundle size:

- **Terser minification** with `drop_console` and `drop_debugger` strips all debug logging from production builds
- **Manual code splitting** isolates heavy dependencies — PixiJS, React, and video processing libraries each load in their own chunk, enabling parallel downloads and better caching
- **Tree-shaking** eliminates unused code paths from icon libraries and utility packages
- **Strict TypeScript** (`noUnusedLocals`, `noUnusedParameters`) catches dead code at compile time before it reaches the bundle

### Resource Management

Open Recorder is designed for long recording and editing sessions without degradation:

- Explicit cleanup of PixiJS textures, decoder instances, and audio processors prevents memory leaks
- Streaming decoder reuses a single `VideoDecoder` instance across the export rather than creating and destroying decoders per segment
- Facecam frame syncing uses queue management to bound memory usage during multi-stream exports
- All native sidecar processes are lifecycle-managed by Tauri and terminated cleanly on app exit

---

# Contribution

All contributors welcomed!

Areas where help is especially valuable:

- Smooth cursor pipeline for **Linux**
- **Webcam** overlay bubble
- **Localisation** support, especially Chinese
- UI/UX **design** **improvements**
- **Export speed** improvements

Please:
- Keep pull requests **focused and modular**
- Test playback, editing, and export flows
- Avoid large unrelated refactors

See `CONTRIBUTING.md` for guidelines.

---

# Community

Bug reports and feature requests:

https://github.com/imbhargav5/open-recorder/issues

Pull requests are welcome.

---

# License

Open Recorder is licensed under the **MIT License**.

---

# Credits

## Acknowledgements

Thanks to [Recordly](https://github.com/AdrianMPC/recordly) and [OpenScreen](https://github.com/siddharthvaddem/openscreen).

---
