import SwiftUI

struct AudioInspector: View {
    var edits: TimelineEditDriver
    var playback: VideoPlaybackDriver
    private var settings: AudioProcessingSettings { edits.snapshot.audio }
    private func binding<T>(_ key: WritableKeyPath<AudioProcessingSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: key] }, set: { value in
            var next = settings
            next[keyPath: key] = value
            edits.send(.updateAudio(next))
        })
    }
    var body: some View {
        InspectorGroup(title: "Voice", symbolName: "waveform", showsTopDivider: false) {
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
}
