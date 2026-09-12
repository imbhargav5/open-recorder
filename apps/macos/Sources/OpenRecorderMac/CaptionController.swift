import AVFoundation
import Foundation
import Observation

struct CaptionEnvironment: Sendable {
    var modelReady: @Sendable () async -> Bool = { await LocalCaptionSpeechService.modelReady() }
    var helperReady: @Sendable () -> Bool = { LocalCaptionSpeechService.helper != nil }
    var hasAudio: @Sendable (URL) async throws -> Bool = { try await !AVURLAsset(url: $0).loadTracks(withMediaType: .audio).isEmpty }
    var prepare: @Sendable (URL, URL) async throws -> Void = { try await LocalCaptionSpeechService.prepareAudio(video: $0, destination: $1) }
    var download: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void = { try await LocalCaptionSpeechService.downloadModel(progress: $0) }
}

@MainActor
@Observable
final class CaptionController {
    enum Phase: String { case idle, downloading = "Downloading speech model", preparing = "Preparing audio", transcribing = "Transcribing", cleaning = "Cleaning up" }
    private(set) var phase: Phase = .idle
    private(set) var progress: Double?
    private(set) var models: [String] = []
    private(set) var speechReady = false
    private(set) var helperReady = false
    private(set) var hasAudio: Bool?
    private(set) var isChecking = false
    private(set) var ollamaStatus = "Not checked"
    private(set) var error: String?
    private(set) var pendingTranscript: [CaptionSegment]?
    var language = "auto"
    var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: "captions.ollamaModel") }
    }
    @ObservationIgnored private let environment: CaptionEnvironment
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let speech: any CaptionTranscribing
    @ObservationIgnored private let ollama: any CaptionCleaning
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var source: URL?
    @ObservationIgnored private var pendingLanguage = "auto"

    init(speech: any CaptionTranscribing = LocalCaptionSpeechService(), ollama: any CaptionCleaning = OllamaCaptionService(), defaults: UserDefaults = .standard, environment: CaptionEnvironment = CaptionEnvironment()) {
        self.speech = speech
        self.ollama = ollama
        self.environment = environment
        self.defaults = defaults
        selectedModel = defaults.string(forKey: "captions.ollamaModel") ?? ""
    }

    var isBusy: Bool { phase != .idle }
    var canGenerate: Bool { !isBusy && !isChecking && speechReady && helperReady && hasAudio == true && models.contains(selectedModel) }
    var canRetryCleanup: Bool { !isBusy && pendingTranscript != nil && models.contains(selectedModel) }

    func attach(_ url: URL?) {
        guard source != url else { check(); return }
        cancel()
        checkTask?.cancel()
        source = url
        hasAudio = nil
        pendingTranscript = nil
        error = nil
        check()
    }

    func check() {
        guard !isBusy else { return }
        checkTask?.cancel()
        isChecking = true
        let source = source
        checkTask = Task { [weak self] in
            guard let self else { return }
            let ready = await environment.modelReady()
            guard !Task.isCancelled else { return }
            speechReady = ready
            helperReady = environment.helperReady()
            if let source {
                do {
                    let available = try await environment.hasAudio(source)
                    guard !Task.isCancelled else { return }
                    hasAudio = available
                } catch {
                    guard !Task.isCancelled else { return }
                    hasAudio = nil; self.error = "Could not read this recording’s audio."
                }
            }
            do {
                let available = try await ollama.models()
                guard !Task.isCancelled else { return }
                models = available
                // Only choose a default on first use. Never replace a missing saved selection.
                if selectedModel.isEmpty { selectedModel = available.contains("llama3:latest") ? "llama3:latest" : (available.first ?? "") }
                ollamaStatus = available.isEmpty ? "No local text models installed" : "Connected locally"
            } catch {
                guard !Task.isCancelled else { return }
                models = []
                ollamaStatus = "Unavailable — open Ollama and check again"
            }
            guard !Task.isCancelled else { return }
            isChecking = false
        }
    }

    func downloadSpeechModel() {
        guard !isBusy else { return }
        error = nil
        progress = 0
        phase = .downloading
        let token = UUID(); generation = token
        task = Task { [weak self] in
            do {
                let download = self?.environment.download
                try await download? { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.phase == .downloading else { return }
                        self.progress = value
                    }
                }
                guard let self, !Task.isCancelled, generation == token else { return }
                speechReady = true
                phase = .idle
            } catch {
                guard let self, !Task.isCancelled, generation == token else { return }
                self.error = error.localizedDescription
                phase = .idle
            }
        }
    }

    func generate(existing: CaptionTrack?, isCurrent: @escaping @MainActor () -> Bool = { true }, apply: @escaping @MainActor (CaptionTrack) -> Void) {
        guard canGenerate, let source else { return }
        pendingTranscript = nil
        pendingLanguage = language
        start(source: source, existing: existing, retry: false, isCurrent: isCurrent, apply: apply)
    }

    func retryCleanup(existing: CaptionTrack?, isCurrent: @escaping @MainActor () -> Bool = { true }, apply: @escaping @MainActor (CaptionTrack) -> Void) {
        guard canRetryCleanup, let source else { return }
        start(source: source, existing: existing, retry: true, isCurrent: isCurrent, apply: apply)
    }

    private func start(source: URL, existing: CaptionTrack?, retry: Bool, isCurrent: @escaping @MainActor () -> Bool, apply: @escaping @MainActor (CaptionTrack) -> Void) {
        error = nil
        progress = nil
        phase = retry ? .cleaning : .preparing
        let token = UUID(); generation = token
        let selected = selectedModel
        let language = pendingLanguage
        task = Task { [weak self] in
            guard let self else { return }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("open-recorder-captions-\(token)")
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                if !retry {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let audio = directory.appendingPathComponent("audio.wav")
                    // Audio decoding and file IO must never run on the UI actor.
                    let prepare = environment.prepare
                    let preparation = Task.detached(priority: .userInitiated) {
                        try await prepare(source, audio)
                    }
                    try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    phase = .transcribing
                    progress = 0
                    let transcript = try await speech.transcribe(audio: audio, language: language) { [weak self] value in
                        Task { @MainActor in
                            guard let self, self.generation == token, self.phase == .transcribing else { return }
                            self.progress = value
                        }
                    }
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    guard !transcript.isEmpty else { throw CaptionFailure.message("No speech was detected. Existing captions have been kept.") }
                    pendingTranscript = transcript
                }
                guard let pendingTranscript else { return }
                progress = nil
                phase = .cleaning
                let cleaned = try await ollama.clean(pendingTranscript, model: selected)
                try Task.checkCancellation()
                guard generation == token else { return }
                guard isCurrent() else { throw CaptionFailure.message("Captions changed while generation was running. Retry cleanup to replace the current track.") }
                apply(CaptionTrack(segments: cleaned, style: existing?.style ?? CaptionStyle(), language: language, model: selected))
                self.pendingTranscript = nil
                phase = .idle
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                self.error = error.localizedDescription
                phase = .idle
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        phase = .idle
    }

    func close() {
        cancel()
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
        pendingTranscript = nil
    }
}
