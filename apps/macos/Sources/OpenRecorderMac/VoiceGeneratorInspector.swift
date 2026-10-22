import AppKit
import SwiftUI

struct VoiceGeneratorInspector: View {
    @State private var controller = VoiceGeneratorController()
    @State private var script = ""
    @State private var referenceAudioURL: URL?
    var edits: TimelineEditDriver
    var playback: VideoPlaybackDriver

    private var track: CaptionTrack? { edits.snapshot.captions }
    private var generatedText: String {
        let enteredScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if !enteredScript.isEmpty { return enteredScript }
        let captionText = track?.segments.sorted(by: { $0.start < $1.start }).map(\.text).joined(separator: " ") ?? ""
        if !captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return captionText }
        return controller.referenceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var voiceoverDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenRecorder/generated-audio", isDirectory: true)
    }

    var body: some View {
        InspectorGroup(title: "Voiceover", symbolName: "waveform.and.mic", showsTopDivider: false) {
            Text("Write a script, then record your narration against the video. Recording and playback begin together at the current playhead.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Script").font(.subheadline.weight(.semibold))
            TextEditor(text: $script)
                .font(.system(size: 12))
                .frame(minHeight: 70, maxHeight: 110)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(Theme.borderSubtle) }
                .accessibilityLabel("Voiceover script")

            HStack {
                Button(controller.isRecordingVoiceover ? "Stop recording" : "Record & play") {
                    if controller.isRecordingVoiceover {
                        controller.stopVoiceoverRecording()
                        playback.pause()
                    } else {
                        controller.startVoiceoverRecording(outputDir: voiceoverDirectory) {
                            if !playback.isPlaying { playback.togglePlayback() }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isRecordingVoiceover ? .red : nil)
                Text(controller.isRecordingVoiceover ? String(format: "Recording · %.0f sec", controller.voiceoverRecordingSeconds) : "")
                    .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Text("You can stop and retake at any time. A new take replaces the previous voiceover on this project.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Text("Generate with AI · optional").font(.subheadline.weight(.semibold))
            HStack {
                Circle()
                    .fill(controller.serverReady ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(controller.serverReady ? "TTS server connected" : "TTS server offline")
                    .font(.caption)
                Spacer()
                Button("Check") { controller.checkServer() }
                    .disabled(controller.isBusy)
                    .controlSize(.small)
            }

            if !controller.serverReady {
                Text("Start a local TTS server (Qwen2.5-TTS) on port 8880. The model runs locally and is not bundled with the app.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.isBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(controller.phase.rawValue).font(.caption)
                }
            }

            if let error = controller.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Picker("Voice", selection: $controller.config.voice) {
                ForEach(VoiceGenerationConfig.Voice.allCases) { voice in
                    Text(voice.title).tag(voice)
                }
            }
            .pickerStyle(.menu)
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("Custom voice · optional").font(.subheadline.weight(.semibold))
                Text("Use 3–30 seconds of clear, single-speaker speech. Its transcript is created automatically; correct it if needed for the best clone.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(controller.isRecordingReference ? "Stop recording" : "Record reference") {
                        if controller.isRecordingReference { controller.stopReferenceRecording() }
                        else { controller.startReferenceRecording() }
                    }
                    .buttonStyle(.bordered)
                    .tint(controller.isRecordingReference ? .red : nil)
                    Text(controller.isRecordingReference ? String(format: "%.0f / 30 sec", controller.referenceRecordingSeconds) : "")
                        .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Choose WAV…") { chooseReferenceAudio() }
                    .lineLimit(1)
                    if referenceAudioURL != nil { Button("Clear") { controller.clearReferenceAudio() } }
                }
                if let referenceAudioURL { Text(referenceAudioURL.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if referenceAudioURL != nil {
                    if controller.isTranscribingReference {
                        HStack {
                            ProgressView(value: controller.referenceTranscriptProgress).controlSize(.small)
                            Text("Transcribing reference…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TextField("Reference transcript", text: $controller.referenceTranscript, axis: .vertical)
                        .lineLimit(2...3)
                }
            }
            InspectorSlider(title: "Speed", valueText: String(format: "%.1f×", controller.config.speed),
                value: $controller.config.speed, range: 0.5...2.0, step: 0.1, onEditingChanged: { _ in })
            InspectorSlider(title: "Pitch", valueText: String(format: "%.1f×", controller.config.pitch),
                value: $controller.config.pitch, range: 0.5...2.0, step: 0.1, onEditingChanged: { _ in })

            Button("Generate voice") {
                let sourceText = generatedText
                if let referenceAudioURL {
                    controller.generateCustomVoice(text: sourceText, referenceAudio: referenceAudioURL, referenceTranscript: controller.referenceTranscript, outputDir: voiceoverDirectory)
                } else if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let track {
                    controller.generateFromSegments(track.segments, outputDir: voiceoverDirectory)
                } else {
                    controller.generate(text: sourceText, outputDir: voiceoverDirectory)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!controller.canGenerate || generatedText.isEmpty)
            if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(referenceAudioURL == nil
                     ? "Leave the script blank to generate from the current screen transcript."
                     : "Leave the script blank to use the recorded reference transcript; edit it above if needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let voiceover = edits.snapshot.voiceover {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Voiceover · \(voiceover.voiceName)").font(.caption).lineLimit(1)
                    Spacer()
                    Button("Remove") { edits.send(.replaceVoiceover(nil)) }.controlSize(.small)
                }
                HStack {
                    Text("Starts at \(formattedTime(voiceover.startTime))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Start at playhead") { updateVoiceoverStart(at: playback.currentTime) }
                        .controlSize(.small)
                }
                if voiceover.duration > 0 {
                    Text("Length \(formattedTime(voiceover.duration))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { controller.checkServer() }
        .onChange(of: controller.generatedAudioPath) { _, path in
            guard let path else { return }
            edits.send(.replaceVoiceover(TimelineVoiceover(
                path: path,
                startTime: max(0, playback.currentTime),
                voiceName: controller.generatedAudioName,
                duration: controller.generatedAudioDuration
            )))
        }
        .onChange(of: controller.referenceAudioPath) { _, path in
            referenceAudioURL = path.map { URL(fileURLWithPath: $0) }
        }
    }

    private func chooseReferenceAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.wav]
        guard panel.runModal() == .OK else { return }
        guard let url = panel.url else { return }
        controller.selectReferenceAudio(url)
    }

    private func updateVoiceoverStart(at time: Double) {
        guard var voiceover = edits.snapshot.voiceover else { return }
        voiceover.startTime = max(0, min(time, playback.duration))
        edits.send(.replaceVoiceover(voiceover))
    }

    private func formattedTime(_ seconds: Double) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%05.2f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }
}
