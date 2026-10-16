import AppKit
import SwiftUI

struct VoiceGeneratorInspector: View {
    @State private var controller = VoiceGeneratorController()
    @State private var script = ""
    @State private var referenceAudioURL: URL?
    var edits: TimelineEditDriver

    private var track: CaptionTrack? { edits.snapshot.captions }
    private var generatedText: String {
        let enteredScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if !enteredScript.isEmpty { return enteredScript }
        let captionText = track?.segments.sorted(by: { $0.start < $1.start }).map(\.text).joined(separator: " ") ?? ""
        if !captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return captionText }
        return controller.referenceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        InspectorGroup(title: "Voice Generation", symbolName: "waveform.and.mic", showsTopDivider: false) {
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

            TextEditor(text: $script)
                .font(.system(size: 12))
                .frame(minHeight: 70, maxHeight: 110)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(Theme.borderSubtle) }
                .accessibilityLabel("Voice script")
            Picker("Voice", selection: $controller.config.voice) {
                ForEach(VoiceGenerationConfig.Voice.allCases) { voice in
                    Text(voice.title).tag(voice)
                }
            }
            .pickerStyle(.menu)
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("Custom voice · optional").font(.subheadline.weight(.semibold))
                Text("Record a clean reference here. Its transcript is created automatically and can be edited below.")
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
                    Button("Choose file…") { chooseReferenceAudio() }
                    .lineLimit(1)
                    if referenceAudioURL != nil { Button("Clear") { referenceAudioURL = nil; controller.referenceTranscript = "" } }
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
                let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("OpenRecorder/generated-audio", isDirectory: true)
                let sourceText = generatedText
                if let referenceAudioURL {
                    controller.generateCustomVoice(text: sourceText, referenceAudio: referenceAudioURL, referenceTranscript: controller.referenceTranscript, outputDir: supportDir)
                } else if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let track {
                    controller.generateFromSegments(track.segments, outputDir: supportDir)
                } else {
                    controller.generate(text: sourceText, outputDir: supportDir)
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
            if controller.generatedAudioPath != nil {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Added to timeline · \(controller.config.voice.title)").font(.caption)
                    Spacer()
                    Button("Remove") { edits.send(.replaceVoiceover(nil)) }.controlSize(.small)
                }
            }
        }
        .onAppear { controller.checkServer() }
        .onChange(of: controller.generatedAudioPath) { _, path in
            guard let path else { return }
            edits.send(.replaceVoiceover(TimelineVoiceover(path: path, voiceName: controller.config.voice.title)))
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
        panel.allowedContentTypes = [.audio, .mpeg4Audio]
        guard panel.runModal() == .OK else { return }
        referenceAudioURL = panel.url
    }
}
