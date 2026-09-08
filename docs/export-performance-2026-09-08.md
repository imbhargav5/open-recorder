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

Additional 4K rounded baseline: 60-second median 29.890 s across five measured runs; ten-minute export 328.986 s after a 335.714 s warm-up. Decoded 30 fps, dimensions, duration, frame count and cadence checks pass. Ten-minute sampled peak RSS was 272 MiB; first/final ten-second medians were 199/99 MiB, without sustained growth. RSS does not include all GPU/IOSurface memory.

A separate detailed 1080p rounded run recorded 240 compositor frames, 0.420 s CPU preparation, 0.215 s Core Image kernel execution, 960 render passes and 1,983,369,600 processed pixels. These timings are diagnostic only. Whole-video debug/release comparisons of all six short fixtures produced SSIM 1.000000, with matching decoded stream settings, frame counts and audio/video timing metadata.

## Stage 2: invariant masks

One raster is retained for recording content and one for facecam, keyed by integer bitmap dimensions and the exact effective radius. Placement uses transforms. Inset/decorative masks and content-dependent shadows keep their existing dynamic path. Cancellation and render-context changes invalidate both retained masks.

Fresh-process A/B controls use the same optimized test binary with caching disabled only by the testing flag. One warm-up and five measured runs per fixture:

| Fixture | Uncached seconds | Cached seconds | Time reduction | Uncached peak MiB | Cached peak MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Plain | 0.882 | 0.876 | 0.7% | 61 | 61 |
| Wallpaper | 1.335 | 1.042 | 21.9% | 656 | 661 |
| Rounded | 1.436 | 1.024 | 28.7% | 670 | 660 |
| Blurred background | 1.360 | 1.051 | 22.8% | 524 | 612 |
| Facecam | 1.640 | 1.264 | 23.0% | 538 | 597 |
| 4K rounded | 2.295 | 1.675 | 27.0% | 573 | 611 |

An earlier multi-fixture batch peaked near 2.1 GiB, then dropped to approximately 0.7 GiB while continuing to export. Its peak combines delayed reclamation across prior exports and is not a clean per-scenario comparison. Fresh-process controls show bounded additional memory (largest observed peak increase 17%), not a promise of zero memory overhead.

Five styled whole-video comparisons have SSIM 1.000000; all 15 captured pre-encode PNG frames have maximum per-channel difference zero. The expanded integration suite produces 22 exports and includes visible cursor/annotation output, inspected in the generated frame. A synthetic flash/beep fixture has matching video and audio onsets at 0, 2, 4 and 6 seconds after export (audio detection resolution 10 ms). Active Task/token cancellation followed by another export passes, including no late compositor-counter changes after cancellation returns. Local full suites pass: 31 Rust and 698 Swift tests in debug and release, with three explicit opt-in tests skipped and exercised separately as relevant.
