import AppKit
import SwiftUI

struct CaptionInspector: View {
    @Bindable var controller: CaptionController
    var edits: TimelineEditDriver
    var playback: VideoPlaybackController
    @State private var setupExpanded = true
    @State private var confirmsRegeneration = false
    @State private var retrying = false
    private var track: CaptionTrack? { edits.snapshot.captions }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Text("Captions").font(.headline)
                Text("ALPHA")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.fgMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.fgMuted.opacity(0.10), in: Capsule())
                    .accessibilityLabel("Alpha")
            }
            DisclosureGroup("Local AI setup", isExpanded: $setupExpanded) {
                setup.padding(.top, 10)
            }
            Text("Processed on this Mac").font(.footnote).foregroundStyle(.secondary)
            Picker("Language", selection: $controller.language) {
                Text("Auto detect").tag("auto")
                ForEach([("en", "English"), ("hi", "Hindi"), ("te", "Telugu"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("ja", "Japanese"), ("zh", "Chinese"), ("pt", "Portuguese"), ("ko", "Korean"), ("ar", "Arabic")], id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }.disabled(controller.isBusy)
            if controller.hasAudio == false {
                Label("This recording has no audio.", systemImage: "speaker.slash").font(.footnote)
            }
            if controller.isBusy {
                HStack {
                    ProgressView(value: controller.progress).frame(maxWidth: 60).controlSize(.small)
                    Text(controller.phase.rawValue).font(.footnote)
                    Spacer()
                    Button("Cancel") { controller.cancel() }
                }
            } else {
                Button(track == nil ? "Generate captions" : "Regenerate captions") {
                    if track?.isEdited == true { retrying = false; confirmsRegeneration = true }
                    else { generate() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!controller.canGenerate)
                if controller.pendingTranscript != nil {
                    Button("Retry cleanup") {
                        if track?.isEdited == true { retrying = true; confirmsRegeneration = true }
                        else { retryCleanup() }
                    }.disabled(!controller.canRetryCleanup)
                }
            }
            if let error = controller.error {
                Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
            }
            if let track {
                styleControls(track)
                HStack {
                    Text("\(track.segments.count) captions").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { edits.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!edits.canUndo || controller.isBusy).help("Undo").accessibilityLabel("Undo caption or timeline edit")
                    Button { edits.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!edits.canRedo || controller.isBusy).help("Redo").accessibilityLabel("Redo caption or timeline edit")
                }
                LazyVStack(spacing: 10) {
                    ForEach(track.segments) { segment in
                        CaptionEditorRow(segment: segment, otherSegments: track.segments.filter { $0.id != segment.id }, active: segment.contains(playback.currentTime), duration: playback.duration,
                            seek: { playback.seek(to: segment.start) },
                            save: { replacement in updateSegment(replacement) },
                            delete: { deleteSegment(segment.id) })
                    }
                }.disabled(controller.isBusy)
            }
        }
        .controlSize(.small)
        .confirmationDialog("Replace edited captions?", isPresented: $confirmsRegeneration, titleVisibility: .visible) {
            Button("Replace captions", role: .destructive) { if retrying { retryCleanup() } else { generate() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your current captions stay in place until generation succeeds. You can undo the replacement.") }
        .onAppear { if controller.canGenerate { setupExpanded = false } }
        .onChange(of: controller.canGenerate) { _, ready in
            if ready { setupExpanded = false }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Speech model: \(controller.speechReady ? "Ready" : "Download needed")", systemImage: controller.speechReady ? "checkmark.circle.fill" : "arrow.down.circle")
            if !controller.speechReady {
                Button("Download speech model (148 MB)") { controller.downloadSpeechModel() }
                    .disabled(controller.isBusy)
            }
            if !controller.helperReady {
                Text("Speech helper missing. Reinstall Open Recorder to enable generation.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Label("Ollama: \(controller.ollamaStatus)", systemImage: controller.models.isEmpty ? "circle" : "checkmark.circle.fill")
            Picker("Text model", selection: $controller.selectedModel) {
                if !controller.models.contains(controller.selectedModel) {
                    Text(controller.selectedModel.isEmpty ? "Select a model" : "\(controller.selectedModel) (missing)").tag(controller.selectedModel)
                }
                ForEach(controller.models, id: \.self) { Text($0).tag($0) }
            }.disabled(controller.isBusy)
            HStack {
                Button("Open Ollama") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    } else { NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!) }
                }
                Button("Check again") { controller.check() }.disabled(controller.isBusy || controller.isChecking)
                if controller.isChecking { ProgressView().controlSize(.small) }
            }
            if controller.models.isEmpty {
                Text("Install and open Ollama, then download a text model in Ollama. Open Recorder uses only models stored locally.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.font(.footnote)
    }

    private func styleControls(_ track: CaptionTrack) -> some View {
        InspectorGroup(title: "Style", symbolName: "textformat") {
            Toggle("Show captions", isOn: styleBinding(\.isVisible, fallback: true))
            HStack {
                Text("Font size")
                Slider(value: styleBinding(\.fontSize, fallback: 36), in: 20...64, step: 1)
                Text("\(Int(track.style.fontSize))").monospacedDigit()
            }
            ColorPicker("Text color", selection: colorBinding(\.textHex), supportsOpacity: false)
            ColorPicker("Background", selection: colorBinding(\.backgroundHex), supportsOpacity: false)
            HStack {
                Text("Opacity")
                Slider(value: styleBinding(\.backgroundOpacity, fallback: 0.65), in: 0...1)
            }
            Picker("Position", selection: styleBinding(\.position, fallback: .bottom)) {
                Text("Top").tag(CaptionStyle.Position.top)
                Text("Bottom").tag(CaptionStyle.Position.bottom)
            }
        }.disabled(controller.isBusy)
    }

    private func styleBinding<T>(_ path: WritableKeyPath<CaptionStyle, T>, fallback: T) -> Binding<T> {
        Binding(get: { track?.style[keyPath: path] ?? fallback }, set: { value in
            guard var track else { return }
            track.style[keyPath: path] = value
            track.isEdited = true
            apply(track)
        })
    }

    private func colorBinding(_ path: WritableKeyPath<CaptionStyle, String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: SerializableColor(hex: track?.style[keyPath: path] ?? "#FFFFFF").nsColor) }, set: { value in
            guard var track, let color = NSColor(value).usingColorSpace(.sRGB) else { return }
            track.style[keyPath: path] = String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
            track.isEdited = true
            apply(track)
        })
    }

    private func retryCleanup() {
        let existing = track
        controller.retryCleanup(existing: existing, isCurrent: { edits.snapshot.captions == existing }, apply: apply)
    }
    private func generate() {
        let existing = track
        controller.generate(existing: existing, isCurrent: { edits.snapshot.captions == existing }, apply: apply)
    }
    private func apply(_ value: CaptionTrack) { edits.send(.replaceCaptions(value)) }
    private func updateSegment(_ segment: CaptionSegment) {
        guard var track, let index = track.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        track.segments[index] = segment
        track.segments.sort { $0.start < $1.start }
        track.isEdited = true
        apply(track)
    }
    private func deleteSegment(_ id: UUID) {
        guard var track else { return }
        track.segments.removeAll { $0.id == id }
        track.isEdited = true
        apply(track)
    }
}

private struct CaptionEditorRow: View {
    var segment: CaptionSegment
    var otherSegments: [CaptionSegment]
    var active: Bool
    var duration: Double
    var seek: () -> Void
    var save: (CaptionSegment) -> Void
    var delete: () -> Void
    @State private var text = ""
    @State private var start = ""
    @State private var end = ""
    @State private var validation: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(String(format: "%02d:%05.2f", Int(segment.start) / 60, segment.start.truncatingRemainder(dividingBy: 60)), action: seek)
                    .monospacedDigit().help("Seek to caption")
                Spacer()
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .accessibilityLabel("Delete caption")
            }
            TextField("Caption text", text: $text, axis: .vertical)
                .lineLimit(2...5).focused($focused)
                .onSubmit(commit)
            HStack {
                TextField("Start (s)", text: $start).accessibilityLabel("Caption start in seconds")
                Text("–")
                TextField("End (s)", text: $end).accessibilityLabel("Caption end in seconds")
                Button("Apply", action: commit)
            }.onSubmit(commit)
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
        }
        .padding(9)
        .background(active ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: sync)
        .onChange(of: segment) { _, _ in sync() }
        .onChange(of: focused) { _, value in if !value { commit() } }
    }

    private func sync() {
        text = segment.text
        start = String(format: "%.3f", segment.start)
        end = String(format: "%.3f", segment.end)
        validation = nil
    }
    private func commit() {
        guard let from = Double(start), let to = Double(end), from.isFinite, to.isFinite,
              from >= 0, to > from, to <= duration,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2000 else {
            validation = "Enter text and a valid time range within the recording."
            return
        }
        guard !otherSegments.contains(where: { from < $0.end && to > $0.start }) else {
            validation = "Caption times must not overlap another caption."
            return
        }
        var replacement = segment
        replacement.start = from; replacement.end = to
        replacement.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        validation = nil
        if replacement != segment { save(replacement) }
    }
}
