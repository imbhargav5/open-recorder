/**
 * TypeScript type-level assertions for backend.ts.
 *
 * This file is NOT a runtime test. It is checked by the TypeScript compiler
 * (`tsc --noEmit` / `pnpm typecheck`) to verify that the domain interfaces
 * used in backend.ts are correctly typed.
 *
 * How it works:
 *   - Lines marked `// @ts-expect-error` must produce a TypeScript error.
 *     If the error is absent (e.g., because a type regresses to `any`),
 *     TypeScript flags the directive itself as an "Unused '@ts-expect-error'
 *     directive" error, failing the type-check.
 *   - Positive assertions use `satisfies` to confirm valid property access.
 *
 * Run: pnpm typecheck
 */

import type { DesktopSource } from "@/components/launch/sourceSelectorState";
import type { NativeRecordingOptions, SourceListOptions } from "@/lib/backend";
import type { FacecamSettings, RecordingSession } from "@/lib/recordingSession";
import type { ShortcutBinding, ShortcutsConfig } from "@/lib/shortcuts";

// ─── RecordingSession ────────────────────────────────────────────────────────

declare const session: RecordingSession;

// Valid required property
void (session.screenVideoPath satisfies string);

// Valid optional properties
void (session.facecamVideoPath satisfies string | undefined);
void (session.facecamOffsetMs satisfies number | undefined);
void (session.facecamSettings satisfies FacecamSettings | undefined);
void (session.sourceName satisfies string | undefined);
void (session.showCursorOverlay satisfies boolean | undefined);

// @ts-expect-error: 'nonExistentField' does not exist on RecordingSession
void session.nonExistentField;

// @ts-expect-error: typo — 'screenVideoPah' does not exist on RecordingSession
void session.screenVideoPah;

// @ts-expect-error: 'videoPath' does not exist (correct name is screenVideoPath)
void session.videoPath;

// ─── ShortcutsConfig ─────────────────────────────────────────────────────────

declare const shortcuts: ShortcutsConfig;

// Valid shortcut keys
void (shortcuts.addZoom satisfies ShortcutBinding);
void (shortcuts.addTrim satisfies ShortcutBinding);
void (shortcuts.playPause satisfies ShortcutBinding);
void (shortcuts.deleteSelected satisfies ShortcutBinding);

// @ts-expect-error: 'addZomm' does not exist on ShortcutsConfig (typo)
void shortcuts.addZomm;

// @ts-expect-error: 'startStopRecording' is not an editor shortcut key
void shortcuts.startStopRecording;

// @ts-expect-error: 'pauseRecording' is not an editor shortcut key
void shortcuts.pauseRecording;

// ─── DesktopSource ───────────────────────────────────────────────────────────

declare const source: DesktopSource;

// Valid required properties
void (source.id satisfies string);
void (source.name satisfies string);

// Valid optional properties
void (source.sourceType satisfies "screen" | "window");
void (source.appName satisfies string | undefined);
void (source.windowTitle satisfies string | undefined);
void (source.windowId satisfies number | undefined);

// @ts-expect-error: 'nonExistentProp' does not exist on DesktopSource
void source.nonExistentProp;

// @ts-expect-error: typo — 'souceType' does not exist (correct: sourceType)
void source.souceType;

// @ts-expect-error: 'source_type' is the Rust snake_case name; TS type uses camelCase
void source.source_type;

// ─── SourceListOptions ───────────────────────────────────────────────────────

declare const opts: SourceListOptions;

// Valid properties
void (opts.types satisfies string[] | undefined);
void (opts.withThumbnails satisfies boolean | undefined);
void (opts.timeoutMs satisfies number | undefined);
void (opts.thumbnailSize satisfies { width?: number; height?: number } | undefined);

// @ts-expect-error: 'timeout' is not a valid key (correct name is timeoutMs)
void opts.timeout;

// @ts-expect-error: 'thumbnail_size' is the Rust snake_case name; TS type uses camelCase
void opts.thumbnail_size;

// ─── NativeRecordingOptions ──────────────────────────────────────────────────

declare const nativeOpts: NativeRecordingOptions;

// Valid properties
void (nativeOpts.captureCursor satisfies boolean | undefined);
void (nativeOpts.capturesSystemAudio satisfies boolean | undefined);
void (nativeOpts.capturesMicrophone satisfies boolean | undefined);
void (nativeOpts.microphoneDeviceId satisfies string | undefined);
void (nativeOpts.microphoneLabel satisfies string | undefined);

// @ts-expect-error: 'captureAudio' is not a valid key (correct: capturesSystemAudio)
void nativeOpts.captureAudio;

export {};
