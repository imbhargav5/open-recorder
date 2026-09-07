# Video export performance investigation — 2026-09-07

## Conclusion

Default styled export repeatedly renders an unchanged wallpaper/background. Materializing that background once into an IOSurface-backed CVPixelBuffer reduced export time from 2.915s to 1.406s (2.07x throughput, 51.8% less elapsed time) in a controlled synthetic probe. The encoder, output quality setting, and serial compositor scheduling were unchanged. This identifies avoidable composition work as a major cost for this scenario; it does not profile an unspecified user recording.

The previous investigation's prototypes were removed at its conclusion. Inspection of the current checkout confirms that the repeated work remains. The initial experiments were reverted, then the bounded background cache described below was implemented and verified for the follow-up PR.

## Fresh measurements

Open Recorder commit: `897e2b2`. Machine: Apple M1 Max. SwiftPM debug test invoking the real `VideoExportRenderer.export` API. Existing synthetic H.264 fixture independently checked with ffprobe: 1920x1080, 60 fps, 8 seconds. Output: MOV/H.264, 1920x1080, 30 fps, high-source quality, 240 frames. No audio, cursor telemetry, facecam, or timeline edits were supplied. Default editor appearance: default wallpaper, padding ratio 0.036, radius 0, shadow 0.35, no background blur or inset. Three runs per case; table reports medians including the first run. Build time excluded. These are short synthetic measurements, not packaged-app or production performance guarantees.

| Appearance | Current code | CGImage background cache | CVPixelBuffer background cache |
| --- | ---: | ---: | ---: |
| Plain, no styling | 0.889s | 0.876s | 0.884s |
| Default wallpaper styling | 2.915s | 1.862s | 1.406s |
| Same layout, solid background | 1.308s | 1.637s | 1.262s |
| Wallpaper styling, shadow disabled | 2.576s | 1.482s | 1.127s |

Removing shadows alone yields a much smaller change than eliminating repeated background rendering. Blindly rasterizing cheap solid colors into CGImages can make them slower. Retain a simple path for solid/transparent backgrounds.

The pixel-buffer prototype output was checked with ffprobe and all 240 decoded frames compared using FFmpeg SSIM: overall 0.999428 versus baseline. This is high similarity, not pixel identity or comprehensive color/alpha validation.

## Current pipeline findings

- `apps/macos/Sources/OpenRecorderMac/VideoBackgroundCompositor.swift:198`: already creates a reusable Metal-backed CIContext when Metal is available. Enabling GPU rendering is not a missing first step.
- `VideoBackgroundCompositor.swift:239`: synchronous serial rendering deliberately applies backpressure; the comment documents decoded-buffer retention from a backlog. Do not replace it with unbounded asynchronous requests.
- `VideoBackgroundCompositor.swift:361`: builds the background graph for every frame, including blur when enabled. Wallpaper source images are already cached by `WallpaperImageCache`; the missing cache is the rendered background at output dimensions, not the image file decode.
- `VideoBackgroundCompositor.swift:785`: gradients allocate and draw a full-size CGContext on each call.
- `VideoBackgroundCompositor.swift:857`: rounded masks allocate a new bitmap on every call, even for radius zero. Source layout/mask geometry is usually invariant within an export instruction. This is another candidate, not separately timed here.
- `VideoBackgroundCompositor.swift:887`: the ordinary shadow blurs the changing source image. Caching that entire shadow as static would freeze content-dependent appearance. Only invariant inset shadows can safely be precomputed without changing the design.
- `apps/macos/Sources/OpenRecorderMac/VideoExportOptions.swift:612`: every movie export assigns a video composition. The styling `isPassthrough` branch means simpler composition, not compressed-stream passthrough.
- `apps/macos/Sources/OpenRecorderMac/AppModel.swift:649`: saving copies the completed temporary file, then removes it. This adds a file operation but is outside the renderer timings above.

Core Image intermediate caching is explicitly disabled. Apple documents the speed/memory tradeoff, and recommends disabling general intermediate caching for changing video frames in its video pipeline guidance. Prefer a small explicit cache for known static assets rather than enabling arbitrary intermediate retention: [cacheIntermediates](https://developer.apple.com/documentation/coreimage/cicontextoption/cacheintermediates), [video pipeline guidance](https://developer.apple.com/videos/play/wwdc2020/10008/).

## OpenCut comparison

Cloned the requested [OpenCut repository](https://github.com/OpenCut-app/OpenCut) into `/tmp/opencut-export-investigation-20260907`, main commit `400f097becba5db0fbc305d5a65348cb81c20356`. Its README says it is being rewritten and directs users to Classic. The current desktop code is a GPUI scaffold, not a completed export engine to adopt. Also inspected its `deploy` branch at `fdb4dff755faff2ee48efb673410438c55214046`, then cloned canonical Classic into `/tmp/opencut-classic-export-20260907` at `cf5e79e919144200294fb9fed22a222592a0aeea`.

Useful patterns verified in Classic:

1. **Cache unchanged visual resources.** [`wasm-compositor.ts`](https://github.com/opencut-app/opencut-classic/blob/cf5e79e919144200294fb9fed22a222592a0aeea/apps/web/src/services/renderer/compositor/wasm-compositor.ts) checks content hashes/source identity and dimensions; skips unchanged uploads, reuses backing canvases, and releases absent texture IDs. This is the strongest directly applicable idea.
2. **Reuse GPU scratch resources.** [`texture_pool.rs`](https://github.com/opencut-app/opencut-classic/blob/cf5e79e919144200294fb9fed22a222592a0aeea/rust/crates/compositor/src/texture_pool.rs) recycles render textures by dimensions between frames. Open Recorder already uses AVFoundation's output pixel-buffer pool; focus additional reuse on its manually created masks/backgrounds.
3. **Measure stages.** [`render-perf.ts`](https://github.com/opencut-app/opencut-classic/blob/cf5e79e919144200294fb9fed22a222592a0aeea/apps/web/src/diagnostics/render-perf.ts) records stage timings, percentiles and texture-upload/cache-hit counters. Equivalent measurements would distinguish decode, composition, encode, and final-save costs for real projects.
4. **Bounded forward decoding.** [`video-cache/service.ts`](https://github.com/opencut-app/opencut-classic/blob/cf5e79e919144200294fb9fed22a222592a0aeea/apps/web/src/services/video-cache/service.ts) uses a forward iterator and current/next-frame prefetching. Native movie export already delegates media scheduling to AVFoundation; this is more relevant if replacing the sequential image-generator GIF path.

Classic's [`scene-exporter.ts`](https://github.com/opencut-app/opencut-classic/blob/cf5e79e919144200294fb9fed22a222592a0aeea/apps/web/src/services/renderer/scene-exporter.ts) uses Mediabunny CanvasSource, AVC for MP4 / VP9 for WebM, and sequentially awaits rendering and adding each frame. It buffers the output through BufferTarget. Its GPU compositor is Rust/wgpu with browser backend support. Neither Rust nor this export loop establishes superior end-to-end speed. No OpenCut export benchmark was run, and no claim is made that it exports faster than Open Recorder.

## Recommended implementation order

1. Add a bounded, instruction-scoped cache of rendered wallpapers/gradients and static blur in an IOSurface-backed pixel buffer. Retain ownership, key/invalidate for instruction, dimensions and style, release on context/lifecycle changes; keep solid and transparent backgrounds cheap.
2. Cache invariant masks with geometry/radius keys. Preserve crop edges and alpha; skipping radius-zero masks is safe only after proving equivalent clipping. Keep changing source-dependent shadows dynamic.
3. Add render-stage timing and cache counters. Validate longer real projects at 1080p and 4K with zoom, cursor, facecam, blur, cancellation, and repeated exports; measure peak memory and compare rendered appearance/colors.
4. Only then measure bounded two-frame concurrency if composition is still limiting throughput. Preserve backpressure and synchronization; concurrency is not required for the measured 2.07x gain.
5. Separately implement eligible compressed-stream passthrough and a same-volume move with cross-volume fallback. Respect output resolution, frame rate, codec/container, transforms, styling, overlays and edits before selecting passthrough.

## Reproduction artifacts

Temporary investigation files retained on this machine:

- `/tmp/ExportInvestigationProbeTests.swift` — disposable XCTest source; place into `apps/macos/Tests/OpenRecorderMacTests/` to rerun.
- `/tmp/export-investigation-baseline-20260907.log`
- `/tmp/export-investigation-cached-20260907.log`
- `/tmp/export-investigation-pixelbuffer-20260907.log`
- `/tmp/export-investigation-cgimage-cache.patch`
- `/tmp/export-investigation-pixelbuffer-cache.patch` — experiment only; not hardened for release.
- `/tmp/export-investigation-ssim-pixelbuffer.log`

Command: `swift test --package-path apps/macos --filter ExportInvestigationProbeTests`. Input path is in the test. All three test runs passed. The disposable benchmark test was removed after measuring. The production cache and permanent regression tests remain in the PR.


## Implemented change and final validation

`VideoStaticBackgroundCache` stores one rendered wallpaper/gradient (including static blur) in a BGRA IOSurface pixel buffer. Keys include background style, extent and blur radius. Context changes and cancellation invalidate the cache; replacing keys releases the previous entry. Solid/transparent colors bypass rasterization. AVFoundation encoding, serial backpressure, rounded masks, source-dependent shadows and animated overlays keep their existing behavior.

Final A/B run on the same M1 Max and original compositor at `897e2b2`, build time excluded:

| Fixture / actual output | Original | Final cache | Speedup |
| --- | ---: | ---: | ---: |
| 8 seconds, 1080p30 | 3.013s | 1.496s | 2.01x |
| 4 seconds, 4K30 | 2.304s | 1.897s | 1.21x |
| 60 seconds, 1080p30 | 19.845s | 8.509s | 2.33x |

These are synthetic clips and single A/B measurements of the final code; the earlier prototype table used three-run medians. FFmpeg verified matching duration, dimensions and decoded frame counts (240 / 120 / 1800). Whole-video SSIM was 0.999428 / 0.999328 / 0.999157. Test-run maximum resident set size from `time -l` was 409,714,688 bytes original and 394,100,736 bytes optimized; this is not a packaged-app memory benchmark.

The 4K fixture contains 60 fps and the probe requested 60 fps, but both baseline and optimized exports actually encoded 30 fps. That pre-existing frame-rate discrepancy is outside this performance patch; the table reports the verified output rate rather than the requested rate.

Validation completed:

- `make test-macos`: 31 Rust tests passed; 691 Swift tests executed, one opt-in test skipped, zero failures.
- `OPEN_RECORDER_ZOOM_RENDER_CHECK=1 swift test --package-path apps/macos --filter AdaptiveZoomRenderTests`: passed separately; 20 encoded videos covering ten scenarios, including cached wallpaper/blurred-gradient backgrounds, crop/aspect ratios, adaptive/legacy zoom, inset and fixed/moving facecam. Sampled marker positions and decoded durations are asserted; representative frames were visually inspected.
- Five permanent cache tests verify repeated-frame reuse, size/style/blur invalidation, capacity-one eviction/release, constant-color bypass and gradient/blur/alpha fidelity (maximum channel difference two 8-bit levels).
- `make package-macos-dev` and `codesign --verify --deep --strict` passed.
- Computer Use launched that package, opened the synthetic `.openrecorder` project, used Export Video, observed rendering and the Save dialog, and saved `/tmp/export-cache-native-wallpaper.mov`. ffprobe confirmed 1920x1080, 30 fps, six seconds, 180 frames; an extracted frame was visually inspected. The save click's post-action AX read and subsequent editor AX/screenshot reads timed out, so return-to-editor interaction and a second native export were not verified. A process sample showed the main thread idle in its event loop. The saved output itself was successfully verified.

Final experiment artifacts: `/tmp/ExportCacheFinalProbeTests.swift`, `/tmp/export-cache-{baseline,optimized}-performance.log`, `/tmp/export-cache-ssim-{1080p,4k,long}.log`, `/tmp/export-cache-full-tests.log`, `/tmp/export-cache-integration.log`, `/tmp/export-cache-package.log`. These temporary paths are local evidence, not repository fixtures.
