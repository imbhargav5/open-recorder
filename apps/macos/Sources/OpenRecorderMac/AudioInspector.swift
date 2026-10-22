import SwiftUI

struct AudioInspector: View {
    var voiceGenerator: VoiceGeneratorController
    var edits: TimelineEditDriver
    var playback: VideoPlaybackDriver
    private var settings: AudioProcessingSettings { edits.snapshot.audio }
    private var enhanceSettings: AIAudioEnhanceSettings { edits.snapshot.aiEnhance }
    private func binding<T>(_ key: WritableKeyPath<AudioProcessingSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: key] }, set: { value in
            var next = settings
            next[keyPath: key] = value
            edits.send(.updateAudio(next))
        })
    }
    private func enhanceBinding<T>(_ key: WritableKeyPath<AIAudioEnhanceSettings, T>) -> Binding<T> {
        Binding(get: { enhanceSettings[keyPath: key] }, set: { value in
            var next = enhanceSettings
            next[keyPath: key] = value
            edits.send(.updateAIEnhance(next))
        })
    }
    var body: some View {
        VoiceGeneratorInspector(controller: voiceGenerator, edits: edits, playback: playback)
        DisclosureGroup {
            audioControls.padding(.top, 8)
        } label: {
            Label("Audio cleanup & mix", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.top, 2)
    }

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorGroup(title: "Voice Enhance", symbolName: "waveform.badge.plus", showsTopDivider: false) {
                Button(enhanceSettings.enabled ? "Voice Enhance: On" : "Enhance voice") {
                    var next = enhanceSettings
                    next.enabled.toggle()
                    if next.enabled && next == .default { next = .podcastReady }
                    edits.send(.updateAIEnhance(next))
                }
                .buttonStyle(.borderedProminent)
                .tint(enhanceSettings.enabled ? .green : .accentColor)
                .frame(maxWidth: .infinity)
                if enhanceSettings.enabled {
                    enhanceControl("Intensity", key: \.intensity, range: 0...1)
                }
                Text("Local processing: noise reduction between words, rumble removal, vocal presence, de-essing, compression, and peak protection. Replay after changing it to compare.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            InspectorGroup(title: "Voice", symbolName: "waveform") {
                HStack {
                    Button("Voice preset") {
                        var preset = AudioProcessingSettings.voice
                        preset.routing = settings.routing
                        preset.syncOffsetMs = settings.syncOffsetMs
                        edits.send(.updateAudio(preset))
                    }
                    Button("Reset") { edits.send(.updateAudio(.default)) }
                }
                Picker("Channels", selection: binding(\.routing)) {
                    ForEach(AudioProcessingSettings.Routing.allCases) { routing in
                        Text(routing.title).tag(routing)
                    }
                }
                Text("Choose the connected input to hear a single microphone in both speakers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Loudness, sync & tone") {
                advancedControls.padding(.top, 8)
            }
        }
    }

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: 14) {
        InspectorGroup(title: "Loudness", symbolName: "speaker.wave.2") {
            Toggle("Normalize loudness", isOn: binding(\.normalize))
            if settings.normalize {
                control("Target", key: \.targetLUFS, range: -24 ... -9, suffix: " LUFS")
            }
            control("Gain", key: \.gainDB, range: -24 ... 24, suffix: " dB")
            if playback.audioIsProcessing { ProgressView("Measuring audio…").controlSize(.small) }
            else { Text(playback.audioStatus).font(.caption).foregroundStyle(.secondary) }
            Text("−14 LUFS is a starting target. Gain is reduced when needed to preserve a −1 dB sample peak ceiling.")
                .font(.caption).foregroundStyle(.secondary)
        }
        InspectorGroup(title: "Audio Sync", symbolName: "clock") {
            HStack {
                Text("Offset")
                Spacer()
                Text(String(format: "%+.0f ms", settings.syncOffset)).monospacedDigit()
            }.font(.caption)
            Slider(value: Binding(get: { settings.syncOffset }, set: { value in
                var next = settings
                next.syncOffsetMs = value == 0 ? nil : value
                edits.send(.updateAudio(next))
            }), in: -2000 ... 2000, step: 10, onEditingChanged: { editing in
                if editing { edits.beginUndoTransaction() } else { edits.endUndoTransaction() }
            }).accessibilityLabel("Audio sync offset")
            Button("Reset Sync") {
                var next = settings
                next.syncOffsetMs = nil
                edits.send(.updateAudio(next))
            }
            Text("If audio is late, move left (negative). If audio is early, move right (positive). Applies to preview and export.")
                .font(.caption).foregroundStyle(.secondary)
        }
        InspectorGroup(title: "Tone", symbolName: "slider.horizontal.3") {
            control("Punch", key: \.punch, range: 0 ... 1, suffix: "", scale: 100)
            control("Bass", key: \.bassDB, range: -12 ... 12, suffix: " dB")
            control("Presence", key: \.presenceDB, range: -12 ... 12, suffix: " dB")
            control("Treble", key: \.trebleDB, range: -12 ... 12, suffix: " dB")
            Toggle("Reduce low rumble", isOn: binding(\.reduceRumble))
            Text("Applies to preview and export. Changes affect the recording’s combined audio.")
                .font(.caption).foregroundStyle(.secondary)
        }
        }
    }
    private func control(_ title: String, key: WritableKeyPath<AudioProcessingSettings, Double>,
                         range: ClosedRange<Double>, suffix: String, scale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.0f", settings[keyPath: key] * scale) + suffix).monospacedDigit()
            }.font(.caption)
            Slider(value: binding(key), in: range, onEditingChanged: { editing in
                if editing { edits.beginUndoTransaction() } else { edits.endUndoTransaction() }
            }).accessibilityLabel(title)
        }
    }
    private func enhanceControl(_ title: String, key: WritableKeyPath<AIAudioEnhanceSettings, Double>,
                                range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(enhanceSettings[keyPath: key] * 100))%").monospacedDigit()
            }.font(.caption)
            Slider(value: enhanceBinding(key), in: range, onEditingChanged: { editing in
                if editing { edits.beginUndoTransaction() } else { edits.endUndoTransaction() }
            }).accessibilityLabel(title)
        }
    }
}
