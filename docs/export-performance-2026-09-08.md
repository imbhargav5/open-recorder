# Export optimization measurements — 2026-09-08

Hardware: Apple M1 Max, 32 GiB memory, macOS 26.5 (25F71). Local synthetic H.264/AAC fixtures; no recordings uploaded. Baseline includes the static-background cache merged in #1097. Packaging/measurement source is the tree introduced in `c328cb1` (initial measurements used that uncommitted tree over `06309ee`). Detailed composition diagnostics and frame capture are disabled for comparative timings.

## Stage 1: build configuration

One warm-up and five measured exports per short fixture; medians in seconds. Upright source resolution, requested and decoded 30 fps, unchanged default codec/quality settings. 1080p clips contain 240 frames over eight seconds; 4K contains 120 over four seconds. Decoded counts, dimensions, duration, audio-track presence and strictly increasing presentation timestamps pass in both configurations.

| Fixture | Debug | Release |
| --- | ---: | ---: |
| Plain 1080p | 0.874 | 0.872 |
| Wallpaper 1080p | 1.391 | 1.378 |
| Rounded 1080p | 1.499 | 1.483 |
| Blurred background 1080p | 1.397 | 1.391 |
| Facecam 1080p | 1.596 | 1.569 |
| Rounded 4K | 2.334 | 2.329 |

The observed 0–2% differences do not establish a material export speedup. Production release configuration remains a build-correctness fix. Most expensive compositor operations already execute in system frameworks/on the GPU, so optimizing Swift alone need not substantially change these workloads.

Same-volume save-copy medians were approximately 0.3 ms on APFS; this is not a cross-volume copy measurement. Resident memory is sampled every 100 ms, includes the XCTest host and AVFoundation caches, and is not an exact allocation high-water mark. Decode verification happens outside timed export; memory comparisons must use matching fixture order and fresh processes.

Local debug and optimized suites: 31 Rust tests and 692 Swift tests per configuration, with two explicit opt-in tests skipped. Real export benchmarks run those encoding paths separately. Release tests use `OPEN_RECORDER_TESTING` to expose test accessors without enabling DEBUG behavior in optimized code.

Long 1080p rounded baseline: 60-second median 9.729 s (five measured runs), ten-minute measured export 99.666 s after a 99.238 s warm-up. The latter's sampled peak was 331 MiB; first/middle/final ten-second resident-memory medians were approximately 296/297/289 MiB, with no sustained growth observed. Stream-looped fixtures have fractional final frames: 60.017 s input produces 1,801 frames and 600.014 s produces 18,001. The initial harness incorrectly rounded frame counts down; verification uses the ceiling of output duration times FPS, and checks frame cadence separately. This measurement correction changes no export behavior.

A separate 4K requested-60-fps probe reproduces the existing mismatch: 30 fps and 120 frames over four seconds, rather than the requested 240. Its benchmark intentionally fails and its timings are excluded from performance comparisons. Fixing that discrepancy is separate work.

The opt-in optimized integration suite produced 20 real exports covering plain/padded, wallpaper, blurred gradient, crop, portrait/square aspect, inset, adaptive/legacy zoom and fixed/moving facecam. Native packaging completed with configuration `release`, matching source binary UUIDs/resources, arm64 architecture, version 0.2.49, and a valid development signature. Apple Silicon and Intel debug/release CI passed on the initial implementation. Interactive export/save/playback/settings/repeat validation is blocked by a locked Mac; Computer Use's automatic unlock failed. Compilation, packaging and API integration tests do not substitute for that UI coverage.
