import AppKit
import SwiftUI

/// Modal for choosing who narrates: a ready-made AI voice or a clone of the
/// user's own voice. Keeps the sample recording workflow out of the sidebar.
struct VoiceChooserSheet: View {
    var controller: VoiceGeneratorController
    var voiceoverDirectory: URL
    @Environment(\.dismiss) private var dismiss

    private var referenceAudioURL: URL? {
        controller.referenceAudioPath.map { URL(fileURLWithPath: $0) }
    }

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Choose a voice").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            Picker("Voice type", selection: $controller.mode) {
                ForEach(VoiceGeneratorController.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                switch controller.mode {
                case .aiVoice: aiVoices
                case .myVoice: myVoice
                }
            }
            .scrollIndicators(.hidden)

            if let error = controller.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(22)
        .frame(width: 440, height: 460)
    }

    // MARK: AI voices

    private var aiVoices: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Female", voices: VoiceGenerationConfig.Voice.allCases.filter(\.isFemale))
            group("Male", voices: VoiceGenerationConfig.Voice.allCases.filter { !$0.isFemale })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func group(_ title: String, voices: [VoiceGenerationConfig.Voice]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).kerning(1).foregroundStyle(.secondary)
            ForEach(voices) { voice in
                let selected = controller.config.voice == voice
                Button { controller.config.voice = voice } label: {
                    HStack {
                        Text(voice.title).font(.callout)
                        Spacer()
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(selected ? Color.accentColor.opacity(0.14) : Theme.fg.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(selected ? Color.accentColor.opacity(0.6) : Theme.borderSubtle, lineWidth: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: My voice

    private var myVoice: some View {
        @Bindable var controller = controller
        return VStack(alignment: .leading, spacing: 18) {
            step(1, "Record a sample") {
                HStack(spacing: 8) {
                    Button(controller.isRecordingReference ? "Stop" : "Record") {
                        if controller.isRecordingReference { controller.stopReferenceRecording() }
                        else { controller.startReferenceRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.isRecordingReference ? .red : nil)
                    Button("Choose WAV…") { chooseReferenceAudio() }
                    if referenceAudioURL != nil { Button("Clear", role: .destructive) { controller.clearReferenceAudio() } }
                    if controller.isRecordingReference {
                        Text(String(format: "%.0f / 30 s", controller.referenceRecordingSeconds))
                            .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    InfoButton("Speak naturally for 3–30 seconds in a quiet room, close to the microphone. Your narration is cloned from this sample.")
                }
                if let referenceAudioURL {
                    Label(referenceAudioURL.lastPathComponent, systemImage: "waveform")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            if referenceAudioURL != nil {
                step(2, "Check what was heard") {
                    if controller.isTranscribingReference {
                        HStack {
                            ProgressView(value: controller.referenceTranscriptProgress).controlSize(.small)
                            Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .top, spacing: 5) {
                        TextField("Words spoken in your sample", text: $controller.referenceTranscript, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder)
                        InfoButton("Fix any misheard words, especially names. Only the sample has to match; your narration can say anything. Write new words in the script, not here.")
                            .padding(.top, 5)
                    }
                }
            }

            if controller.hasReadyVoiceProfile {
                step(3, "Try it") {
                    HStack(spacing: 8) {
                        Button("Test my voice") {
                            guard let referenceAudioURL else { return }
                            controller.generateVoiceProfilePreview(
                                referenceAudio: referenceAudioURL,
                                referenceTranscript: controller.referenceTranscript,
                                outputDir: voiceoverDirectory
                            )
                        }
                        .disabled(!controller.canGenerate)
                        if controller.previewAudioPath != nil {
                            Button(controller.isPreviewing ? "Stop" : "Play") { controller.togglePreviewPlayback() }
                        }
                        if controller.isBusy {
                            ProgressView().controlSize(.small)
                            Text(controller.phase.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.accentColor))
                Text(title).font(.subheadline.weight(.semibold))
            }
            content()
        }
    }

    private func chooseReferenceAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.wav]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.selectReferenceAudio(url)
    }
}
