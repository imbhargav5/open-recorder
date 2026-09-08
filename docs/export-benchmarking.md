# Native export benchmarking

Production bundles use optimized Swift/Rust release builds. Development bundles default to debug; use `zsh scripts/package-macos-development-app.zsh --configuration release` for an optimized app under the development identity. Production rejects debug configuration. Bundles contain `OpenRecorderBuildConfiguration` and `OpenRecorderSourceRevision` metadata and are checked before signing.

Create a local JSON manifest, for example:

```json
[
  {"name":"1080-wallpaper","path":"/absolute/path/1080p.mp4","appearance":"wallpaper","fps":30,"repeats":5},
  {"name":"4k-rounded","path":"/absolute/path/4k.mp4","appearance":"rounded","fps":30,"repeats":5}
]
```

Run `python3 scripts/benchmark-macos-export.py manifest.json /tmp/export-baseline --configuration release`. Supported appearances: plain, wallpaper, rounded, blur, facecam. Sources should have upright dimensions; the harness preserves source resolution. The harness performs one warm-up followed by the requested measured runs, uses real MOV export, and separately measures the save-copy phase. JSON includes revision/configuration, metadata, composition request count, output frame count/PTS ordering, elapsed times and resident-memory samples at 100 ms intervals. Baseline memory includes the test host; peaks are sampled rather than exact allocation high-water marks. Frames are decoded outside the timed export to verify counts and presentation timestamps; compressed encoder preroll is not counted as output.

Use `--diagnostics` in a separate run to gather Core Image kernel time, passes, processed pixels and CPU preparation time. Use `--capture-frames` in a separate run to save pre-encode frames at 0, 1 and 2 seconds. These diagnostic modes perturb timing and must not be used for performance acceptance. Plain exports use AVFoundation's built-in compositor, so their custom-compositor counter is zero; output frame count remains available.

Comparative measurements use identical fixtures and hardware, one warm-up and five short runs. Include 1080p/4K, 60 seconds and ten minutes; use one measured run for the ten-minute stress case. Compare matching frames with FFmpeg SSIM (minimum 0.999) and captured pre-encode SDR PNG channels (maximum difference two). Check audio timing and decode every output independently. Retain a pixel-format/concurrency experiment only at >=10% improvement, <=5% slowdown in every measured scenario, and (for concurrency) <=25% peak-memory increase. Inspect long-run memory samples for growth.

The harness intentionally fails on requested-versus-actual FPS mismatch and retains its JSON report. The previously observed 60-to-30 fps output discrepancy must not be counted as an optimization.

Fixtures and outputs remain local; do not commit recordings or upload benchmark reports containing private file paths.

Release tests and the benchmark runner enable `OPEN_RECORDER_TESTING` for existing test accessors. Normal packaging does not define it. `make test-macos-release` runs the optimized test suite; CI exercises both Apple Silicon and Intel and exposes one aggregate required check that fails if either architecture fails.

The local validation fixtures can be reproduced using FFmpeg's `testsrc2=size=1920x1080:rate=30:duration=8` video and `sine=frequency=440:sample_rate=48000:duration=8` audio, encoded with `h264_videotoolbox` at 12 Mbps and AAC. Scale that fixture to 3840x2160 for a four-second 4K input (30 Mbps); stream-loop the 1080p fixture with stream copy and trim to 60 and 600 seconds for stress inputs. These are synthetic workloads, not evidence for every screen recording.

For long stress fixtures that follow shorter warm-up runs in the same process, set `"warmup":false,"repeats":1` to measure the long export once. Short comparative fixtures retain the default one warm-up and five measured runs. Resident memory excludes some GPU/IOSurface allocations; it must not be described as total GPU memory use.

Compare two matching artifact directories with `python3 scripts/compare-export-artifacts.py BASELINE CANDIDATE` (FFmpeg/ffprobe required). It decodes the first measured MOV from each fixture, compares stream settings/counts/timing, requires whole-video SSIM >=0.999, and compares any first-measured-run pre-encode PNG captures with maximum per-channel difference two. Run comparisons outside timed benchmarks.

Exercise cancellation while real compositor requests are active, followed by a fresh export:

```sh
OPEN_RECORDER_EXPORT_CANCEL_FIXTURE=/absolute/path/local-video.mp4 \
  swift test --package-path apps/macos -c release -Xswiftc -DOPEN_RECORDER_TESTING \
  --filter VideoExportCancellationIntegrationTests
```

Use `--uncached-masks` as an A/B control when evaluating mask caching. This control exists only in builds compiled with `OPEN_RECORDER_TESTING`; production packages always use the cache. For memory comparisons, put one short fixture in each manifest and run each control/candidate in a fresh process. This separates per-scenario peaks from delayed AVFoundation/Core Image reclamation across a batch of many completed exports.
