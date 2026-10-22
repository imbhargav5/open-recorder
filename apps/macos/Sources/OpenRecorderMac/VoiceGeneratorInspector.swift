import AppKit
import SwiftUI

struct VoiceGeneratorInspector: View {
    var controller: VoiceGeneratorController
    @State private var teleprompter = TeleprompterOverlayController()
    @State private var showsVoiceChooser = false
    @State private var showsDelivery = false
    var edits: TimelineEditDriver
    var playback: VideoPlaybackDriver

    private var track: CaptionTrack? { edits.snapshot.captions }
    private var script: Binding<NSAttributedString> {
        Binding(get: { controller.script }, set: { controller.script = $0 })
    }
    private var referenceAudioURL: URL? {
        controller.referenceAudioPath.map { URL(fileURLWithPath: $0) }
    }
    private var generatedText: String {
        let enteredScript = controller.script.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !enteredScript.isEmpty { return enteredScript }
        let captionText = track?.segments.sorted(by: { $0.start < $1.start }).map(\.text).joined(separator: " ") ?? ""
        return captionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var voiceoverDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenRecorder/generated-audio", isDirectory: true)
    }

    var body: some View {
        InspectorGroup(title: "Voiceover", symbolName: "waveform.and.mic", showsTopDivider: false) {
            VStack(alignment: .leading, spacing: 16) {
                teleprompterCard
                voiceCardRow
                actionsSection
                statusSection
                currentVoiceoverSection
            }
            .padding(.horizontal, 2)
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
        .onDisappear { teleprompter.dismiss() }
        .sheet(isPresented: $showsVoiceChooser) {
            VoiceChooserSheet(controller: controller, voiceoverDirectory: voiceoverDirectory)
        }
    }

    // MARK: Sidebar sections

    /// Which voice will narrate, with its delivery settings one tap away.
    private var voiceCardRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: controller.mode == .myVoice ? "person.wave.2.fill" : "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.fgMuted)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Voice").font(.caption).foregroundStyle(.secondary)
                    Text(controller.voiceSummary).font(.callout.weight(.medium)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Change") { showsVoiceChooser = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Text("Delivery").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%@Speed %.1f× · Pitch %.1f×", controller.mode == .myVoice || controller.config.tone == .neutral ? "" : "\(controller.config.tone.title) · ", controller.config.speed, controller.config.pitch))
                    .font(.caption.monospacedDigit())
                Spacer(minLength: 8)
                Button("Adjust") { showsDelivery.toggle() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .popover(isPresented: $showsDelivery, arrowEdge: .leading) { deliveryPopover }
            }
        }
        .voiceCard()
    }

    private var deliveryPopover: some View {
        @Bindable var controller = controller
        return VStack(alignment: .leading, spacing: 10) {
            if controller.mode != .myVoice {
                Picker("Tone", selection: $controller.config.tone) {
                    ForEach(VoiceGenerationConfig.Tone.allCases) { Text($0.title).tag($0) }
                }
                Text("Steers emotion for built-in voices. Your own cloned voice follows your sample.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            InspectorSlider(title: "Speed", valueText: String(format: "%.1f×", controller.config.speed),
                value: $controller.config.speed, range: 0.5...2.0, step: 0.1, defaultValue: 1.0, onEditingChanged: { _ in })
            InspectorSlider(title: "Pitch", valueText: String(format: "%.1f×", controller.config.pitch),
                value: $controller.config.pitch, range: 0.5...2.0, step: 0.1, defaultValue: 1.0, onEditingChanged: { _ in })
        }
        .padding(14)
        .frame(width: 250)
    }

    /// One prominent action; recording your own take is deliberately quieter.
    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button {
                generate()
            } label: {
                Text(controller.isBusy ? controller.phase.rawValue : "Generate voice")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.canGenerate || controller.isRecordingVoiceover)

            Button {
                toggleRecordingTake()
            } label: {
                Label(controller.isRecordingVoiceover
                      ? String(format: "Stop recording · %.0f s", controller.voiceoverRecordingSeconds)
                      : "Record your own take instead",
                      systemImage: controller.isRecordingVoiceover ? "stop.circle.fill" : "mic")
                    .font(.caption)
                    .foregroundStyle(controller.isRecordingVoiceover ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Read the script against the video. Recording and playback start together at the playhead; a new take replaces the previous voiceover.")
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(controller.serverReady ? Color.green : Color.red).frame(width: 6, height: 6)
                Text(controller.serverReady ? "Voice server connected" : "Voice server offline")
                    .font(.caption2).foregroundStyle(.secondary)
                if !controller.serverReady {
                    InfoButton("Start the local voice server on port 8880 with scripts/setup-qwen-tts.zsh. The model runs locally and is not bundled with the app.")
                    Button("Check") { controller.checkServer() }
                        .buttonStyle(.borderless).controlSize(.mini)
                }
                Spacer()
            }
            if controller.isBusy, let progress = controller.progress {
                ProgressView(value: progress).controlSize(.small)
            }
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    @ViewBuilder
    private var currentVoiceoverSection: some View {
        if let voiceover = edits.snapshot.voiceover {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Voiceover · \(voiceover.voiceName)").font(.caption).lineLimit(1)
                    Spacer()
                    Button("Remove") { edits.send(.replaceVoiceover(nil)) }
                        .buttonStyle(.borderless).controlSize(.small)
                }
                HStack {
                    Text("Starts at \(formattedTime(voiceover.startTime))")
                        .font(.caption).foregroundStyle(.secondary)
                    if voiceover.duration > 0 {
                        Text("· \(formattedTime(voiceover.duration))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Start at playhead") { updateVoiceoverStart(at: playback.currentTime) }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
            .voiceCard()
        }
    }

    // MARK: Actions

    private static let missingScriptMessage = "Write what the voice should say in the Teleprompter box above, then generate."

    private var scriptText: String { generatedText }

    private func generate() {
        guard !scriptText.isEmpty else { controller.error = Self.missingScriptMessage; return }
        switch controller.mode {
        case .aiVoice:
            controller.generatePresetVoice(text: scriptText, outputDir: voiceoverDirectory)
        case .myVoice:
            guard let referenceAudioURL else {
                controller.error = "Add your voice sample first."
                showsVoiceChooser = true
                return
            }
            guard controller.hasReadyVoiceProfile else {
                controller.error = "Wait for the sample transcript to finish, then try again."
                showsVoiceChooser = true
                return
            }
            controller.generateCustomVoice(text: scriptText, referenceAudio: referenceAudioURL, referenceTranscript: controller.referenceTranscript, outputDir: voiceoverDirectory)
        }
    }

    private func toggleRecordingTake() {
        if controller.isRecordingVoiceover {
            controller.stopVoiceoverRecording()
            playback.pause()
            teleprompter.hide()
        } else {
            controller.startVoiceoverRecording(outputDir: voiceoverDirectory) {
                teleprompter.show(script: controller.script)
                if !playback.isPlaying { playback.togglePlayback() }
            }
        }
    }

    private var teleprompterCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "text.quote")
                    .foregroundStyle(Theme.fg)
                    .font(.system(size: 14, weight: .semibold))
                Text("Teleprompter").font(.subheadline.weight(.semibold))
                InfoButton("Write the narration you want the generated voice to say. It floats above your video while you record and is never included in the export.")
                Spacer()
                Label("Private", systemImage: "eye.slash.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            TeleprompterRichTextEditor(text: script)
                .frame(minHeight: 82, maxHeight: 118)
                .overlay(alignment: .topLeading) {
                    if controller.script.string.isEmpty {
                        Text("Write what the voice should say…")
                            .font(.callout).foregroundStyle(.tertiary)
                            .padding(.horizontal, 9).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .background(Theme.scrim.opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Theme.borderSubtle, lineWidth: 1) }
                .accessibilityLabel("Voiceover teleprompter script")

            HStack(spacing: 5) {
                Text("Format").font(.caption2.weight(.medium)).foregroundStyle(Theme.fgMuted)
                TeleprompterToolbarButton(symbol: "bold", title: "Bold", action: Selector(("toggleBoldface:")))
                TeleprompterToolbarButton(symbol: "italic", title: "Italic", action: Selector(("toggleItalics:")))
                TeleprompterToolbarButton(symbol: "underline", title: "Underline", action: Selector(("toggleUnderline:")))
                Spacer()
                Button {
                    teleprompter.show(script: controller.script)
                } label: {
                    Label("Show", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(generatedText.isEmpty)
                .help("Show the teleprompter above the recording preview")
            }
        }
        .padding(12)
        .background(Theme.fg.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.borderSubtle, lineWidth: 1) }
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

private struct TeleprompterToolbarButton: View {
    var symbol: String
    var title: String
    var action: Selector

    var body: some View {
        Button {
            NSApp.sendAction(action, to: nil, from: nil)
        } label: {
            Image(systemName: symbol).frame(width: 12, height: 12)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Small "i" control that moves explanatory copy out of the sidebar. Hovering
/// previews the text; clicking pins it open for keyboard and trackpad users.
struct InfoButton: View {
    var text: String
    @State private var isPresented = false
    @State private var hoverTask: Task<Void, Never>?

    init(_ text: String) { self.text = text }

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More information")
        .accessibilityHint(text)
        .onHover { inside in
            hoverTask?.cancel()
            if inside {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    isPresented = true
                }
            } else {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    isPresented = false
                }
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(12)
        }
    }
}
private extension View {
    /// Groups a block of controls in the same rounded surface as the teleprompter
    /// so each section reads as its own container with breathing room.
    func voiceCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.fg.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.borderSubtle, lineWidth: 1) }
    }
}
