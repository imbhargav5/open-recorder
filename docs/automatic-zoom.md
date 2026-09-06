# Automatic zoom

New recordings use adaptive automatic zoom when **Create zooms automatically** is enabled in Settings → Recording. **Maximum zoom** limits generated magnification (default 2×, range 1×–3×). A 1× limit creates no automatic zooms. Animation style controls motion timing; framing determines magnification.

The timeline's **Regenerate automatic zooms** sparkle button analyzes existing recording telemetry. It preserves manual regions and automatic regions edited since this version, skips their occupied intervals, and applies its result as one undoable edit. The inspector labels protected regions **Edited · protected**.

## Planning and playback

- Clicks within 1.5 seconds and 20% of the recording diagonal form an interaction sequence.
- Deliberate cursor arrival followed by at least 900 ms of dwell can create a weaker candidate. Idle tails do not repeatedly generate zooms.
- Local movement determines framing, with 10% source-width/height context padding on each side. A final pass checks each action against the planned camera position and widens the whole interaction when a suppressed or unfinished pan would hide its context. Interactions needing less than 1.15× are omitted.
- Balanced motion uses a 600 ms entrance, 1.4 second post-action hold, and 700 ms exit, with a two-second minimum region. Recording boundaries can shorten those intervals.
- Targets stay within a central safe zone where possible. Panning requires at least 200 ms of continuous samples outside the same side of that zone within a 300 ms lookahead, with no sample gap over 250 ms. Click-only windows fall back to explicit click targets. Related targets receive eased pans of at least 600 ms. Unrelated overlapping candidates use a whole-interaction evidence score: the strongest action plus bounded support from other actions. This is a heuristic, not a probability; equal scores retain the earlier interaction.
- Camera-overlay overlap is a conservative framing hint and caps magnification at 1.35×. It cannot recover content already obscured by a camera overlay.
- The stored camera path uses source timestamps and normalized source coordinates. Preview and export apply the same crop, placement, viewport, and magnification mapping. Trim and speed changes sample that source path through the edit plan.

Existing projects without camera paths retain legacy zoom rendering until explicit regeneration. Changing an automatic region's timing retimes its saved path; changing depth rescales its magnification; changing focus pins its target. Each edit protects the region from regeneration.

Analysis is local and runs off the main actor. A project switch, newer generation request, or intervening timeline edit invalidates pending results. Generation uses recorded pointer activity; imported videos without telemetry receive no automatic regions.

## Verification

Run the regular suite:

```sh
make test-macos
```

Run real AVFoundation exports with synthetic screen content:

```sh
cd apps/macos
OPEN_RECORDER_ZOOM_RENDER_CHECK=1 swift test --filter AdaptiveZoomRenderTests
```

The opt-in check exports eight scenarios with adaptive and saved legacy zooms, extracts frames, and compares visible marker positions against preview geometry. Cases include plain and styled exports, crop, portrait, square, asymmetric inset panning, and fixed/moving facecam. Output is saved under `apps/macos/.build/auto-zoom-validation/`.

The normal suite includes 1-, 10-, and 60-minute telemetry benchmarks and prints `AUTO_ZOOM_BENCH`, plus a dense-click regression case. These measure synthetic planner time, not end-to-end recording latency. Runtime timing for telemetry decoding and camera planning is available in the `dev.openrecorder.app` / `AutoZoom` log category. The `RecordingLatency` category measures stop through editor presentation dispatch, with stage timings; it does not measure the first rendered editor frame.

Native playback, timeline dragging, Settings layout, and real capture still require an unlocked Mac for interactive verification.
