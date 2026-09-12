# Local captions

Open a video, select **Captions** in the editor inspector, and expand **Local AI setup**. Download the multilingual base speech model (148 MB), open Ollama, and choose an installed local text model. Generation requires both services. Audio and transcript processing stay on the Mac; there is no cloud fallback. The model download is the only network transfer to a model host and begins only after clicking Download.

Choose a language or Auto detect, then Generate captions. The app prepares the source audio, transcribes with whisper.cpp, and asks Ollama to adjust punctuation/capitalization. It rejects rewritten words, changed caption IDs, and malformed responses. If cleanup fails, Retry cleanup reuses the transcript. Existing captions are replaced only on success; edited tracks require confirmation. Cancel, project close, and source changes invalidate pending results.

Select a timestamp to seek, edit the text, and use Apply for time changes (seconds). Times must remain within the recording and cannot overlap another caption. Text edits commit on Return or when focus leaves the field. Undo/redo includes captions and timeline edits in order. Caption edits and styling are saved in the project, and reopening/editing/exporting saved captions does not require Ollama.

Style controls apply to every caption: visibility, font size (relative to a 1080-pixel short edge), text/background colors, background opacity, and top/bottom placement. Long captions shrink to fit two lines. Captions remain fixed to the final canvas through zooms/crops. Video export defaults Include captions to the visibility setting; it can be overridden for that export. Subtitle files, translation, diarization, and animated word highlights are outside this version.

## Building

Install CMake and the repository's existing Swift/Rust prerequisites. `zsh scripts/build-caption-helper.zsh` builds whisper.cpp v1.8.3 at pinned commit `2eeeba56e9edd762b4b38467bab96c2517163158`. `CMAKE_COMMAND` can name an alternate CMake executable. Packaging calls this script and bundles/signs `Contents/MacOS/whisper-cli`, including its license. The helper links only system frameworks/libraries; Metal is embedded. Release/nightly architecture checks and universal binary assembly include the helper. No model is included in the app or fetched during packaging.

SwiftPM development runs resolve the helper from `apps/macos/.build/caption-helper/bin/whisper-cli`. Model installation uses the current app variant's Application Support directory (`Open Recorder/CaptionModels` or `OpenRecorderNightly/CaptionModels`) and verifies SHA-256 before atomically publishing the file. The model is shared across editor windows of that variant. Ollama discovery uses loopback only and filters cloud aliases and non-completion models. A saved model selection is never silently replaced if removed.

## Verification

- `make test-macos` and `make test-macos-release` run the standard suites.
- `swift test --package-path apps/macos --filter Caption` exercises project compatibility/history, setup, cleanup validation, cancellation, source-time mapping, and real video export compared with the shared preview raster.
- Set `OPEN_RECORDER_CAPTION_ARTIFACTS` to save exported PNGs from the rendering tests.
- For opt-in real speech/Ollama integration, set `OPEN_RECORDER_CAPTION_AUDIO` to an audio/video file and optionally `OPEN_RECORDER_CAPTION_MODEL` to a verified base-model file, then run `swift test --package-path apps/macos --filter CaptionExportTests.testLocalSpeechAndOllamaIntegration`. This test does not download models.
- Manually verify setup/download/cancel, caption editing with keyboard and VoiceOver, regeneration confirmation, reopening projects, independent windows, and playback responsiveness in the packaged app.
