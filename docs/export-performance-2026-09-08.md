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

Long cached exports: 1080p60-second median 6.632 s versus 9.729 s baseline; ten minutes 64.129 s versus 99.666 s. 4K60-second median 21.189 s versus 29.890 s; ten minutes 213.373 s versus 328.986 s. All requested/decoded 30-fps, dimension, duration, frame-count and cadence checks pass. The ten-minute cached runs are single stress measurements after the six 60-second runs, not five-run medians.

For comparable memory histories, compare the first ten-minute pass after the 60-second fixtures: baseline/cached peaks are 554/574 MiB at 1080p and 394/408 MiB at 4K. The baseline's *second* ten-minute pass had lower peaks (331/272 MiB) after additional reclamation and is not the matching first-pass memory control. Cached first/final ten-second RSS medians were 468/461 MiB at 1080p and 316/152 MiB at 4K; no sustained growth was observed.

Cached CPU preparation in the separate detailed run is 0.115 s versus 0.420 s baseline; Core Image kernel time remains 0.213 s versus 0.215 s, with unchanged passes/pixels. The 20 matching adaptive/legacy integration videos have minimum SSIM 0.999709, above the 0.999 gate.

All four long output comparisons (1080p/4K, 60 seconds/ten minutes) have whole-video SSIM 1.000000. The comparator reuses unchanged benchmark files' recorded decoded counts and performs the full SSIM decode with VideoToolbox, avoiding redundant full-file decoding solely for counting.

## Stage 3: native input formats — rejected

The experimental source requirements accepted 8-bit bi-planar video-range (`420v`) and full-range (`420f`) buffers alongside BGRA; output remained BGRA. Detailed counters confirmed actual `420v`/`420f` delivery. The alpha-bearing ProRes fixture correctly stayed BGRA and its captured frames were identical.

The YCbCr path failed correctness: full-range H.264 had whole-video SSIM 0.995687 and maximum pre-encode channel differences of 133, 154 and 200 at the sampled frames. Ordinary video-range H.264 had differences of 132, 135 and 202. Both exceed the maximum two-level tolerance. No speed result is accepted from this experiment. Its source-format changes and temporary diagnostics were reverted; inputs remain on the existing BGRA path. HDR support is unchanged.

## Stage 4: two render slots — rejected

The prototype admitted at most two requests before queueing retained work, gave each slot its own mutable caches, shared the thread-safe Core Image context, waited for each render task before finishing the request, and drained admitted/rejected requests on cancellation. Active cancellation/retry and decoded-output checks passed.

Fresh-process controls, one warm-up/five measurements per fixture, compared against the cached serial exporter:

| Fixture | Serial seconds | Two-slot seconds | Time reduction | Peak RSS increase |
| --- | ---: | ---: | ---: | ---: |
| Plain | 0.876 | 0.877 | -0.1% | 0.2% |
| Wallpaper | 1.042 | 0.993 | 4.7% | 16.7% |
| Rounded | 1.024 | 0.998 | 2.5% | 17.1% |
| Blurred background | 1.051 | 0.991 | 5.6% | 25.5% |
| Facecam | 1.264 | 0.990 | 21.7% | 28.2% |
| 4K rounded | 1.675 | 1.519 | 9.3% | 39.8% |

Median fixture-relative reduction across styled scenarios was only 5.6%, below the 10% gate; several memory peaks also exceeded the 25% limit. The prototype was reverted. Serial rendering remains the default, and no concurrency improvement is claimed. Failed gates make additional long-run acceptance tests for this prototype unnecessary.
