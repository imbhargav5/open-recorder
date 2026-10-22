import AVFoundation
import Foundation
import OSLog
import Observation

struct VoiceGenerationConfig: Codable, Equatable, Hashable, Sendable {
    enum Voice: String, CaseIterable, Codable, Identifiable, Sendable {
        case vivian, serena, ryan, aiden
        var id: String { rawValue }
        var speaker: String { rawValue.capitalized }
        var isFemale: Bool { self == .vivian || self == .serena }
        var gender: String { isFemale ? "Female" : "Male" }
        var title: String {
            switch self {
            case .vivian: "Vivian · Bright"
            case .serena: "Serena · Warm"
            case .ryan: "Ryan · US"
            case .aiden: "Aiden · US"
            }
        }
    }

    /// How the built-in voices should sound. Sent to the TTS model as a style
    /// instruction; cloned voices follow their reference sample instead.
    enum Tone: String, CaseIterable, Codable, Identifiable, Sendable {
        case neutral, warm, upbeat, energetic, calm, serious
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var instruction: String? {
            switch self {
            case .neutral: nil
            case .warm: "Speak in a warm, friendly, welcoming tone with a gentle smile in the voice."
            case .upbeat: "Speak in a cheerful, upbeat, positive tone with lively intonation."
            case .energetic: "Speak with high energy and enthusiasm, expressive and dynamic, with plenty of pitch variation."
            case .calm: "Speak in a calm, soothing, relaxed tone at an unhurried pace."
            case .serious: "Speak in a confident, authoritative, professional tone."
            }
        }
    }

    var speed: Double = 1.0
    var pitch: Double = 1.0
    var tone: Tone = .neutral
    var voice: Voice = .vivian
    var model: String = "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"

    static let `default` = VoiceGenerationConfig()

    var clamped: VoiceGenerationConfig {
        VoiceGenerationConfig(
            speed: max(0.5, min(2.0, speed)),
            pitch: max(0.5, min(2.0, pitch)),
            tone: tone,
            voice: voice,
            model: model
        )
    }
}

@MainActor
@Observable
final class VoiceGeneratorController {
    enum PipelineStage: Equatable {
        case transcribing
        case correctTranscript
        case readyForScript
        case generating
        case generated

        var title: String {
            switch self {
            case .transcribing: "Transcribing sample"
            case .correctTranscript: "Confirm sample words"
            case .readyForScript: "Write narration"
            case .generating: "Generating voice"
            case .generated: "Voice ready"
            }
        }
    }
    enum Phase: String {
        case idle
        case checking = "Checking server"
        case generating = "Generating voice"
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double?
    private(set) var serverReady = false
    var error: String?
    private(set) var generatedAudioPath: String?
    private(set) var generatedAudioDuration = 0.0
    private(set) var generatedAudioName = ""
    private(set) var previewAudioPath: String?
    private(set) var isPreviewing = false
    private(set) var referenceAudioPath: String?
    private(set) var isRecordingReference = false
    private(set) var referenceRecordingSeconds = 0.0
    private(set) var isRecordingVoiceover = false
    private(set) var voiceoverRecordingSeconds = 0.0
    private(set) var isTranscribingReference = false
    private(set) var referenceTranscriptProgress: Double?
    var referenceTranscript = ""
    /// Kept by the editor-owned controller so navigating away from the Audio
    /// sidebar does not discard an in-progress narration draft.
    var script = NSAttributedString(string: "")
    var config = VoiceGenerationConfig.default
    /// Which workflow the sidebar shows. Kept on the controller so it survives
    /// navigating away from the Audio panel.
    var mode: Mode = .aiVoice
    enum Mode: String, CaseIterable, Identifiable {
        case aiVoice = "AI voices"
        case myVoice = "My voice"
        var id: String { rawValue }
    }

    /// One-line description of the selected voice for the sidebar summary row.
    var voiceSummary: String {
        switch mode {
        case .aiVoice: "\(config.voice.title) · \(config.voice.gender)"
        case .myVoice:
            if hasReadyVoiceProfile { "My voice · Ready" }
            else if referenceAudioPath != nil { "My voice · Setting up…" }
            else { "My voice · No sample yet" }
        }
    }

    @ObservationIgnored private var referenceRecorder: AVAudioRecorder?
    @ObservationIgnored private var referenceTimer: Timer?
    @ObservationIgnored private var referenceStartedAt: Date?
    @ObservationIgnored private var referenceRequestID = UUID()
    @ObservationIgnored private var voiceoverRecorder: AVAudioRecorder?
    @ObservationIgnored private var voiceoverTimer: Timer?
    @ObservationIgnored private var voiceoverStartedAt: Date?
    @ObservationIgnored private var previewPlayer: AVAudioPlayer?

    private static let logger = Logger(subsystem: "dev.openrecorder.app", category: "VoiceGenerator")
    private static let ttsServerURL = URL(string: "http://localhost:8880")!

    var isBusy: Bool { phase != .idle }
    var canGenerate: Bool { !isBusy && serverReady }
    var hasReadyVoiceProfile: Bool {
        referenceAudioPath != nil
            && !isTranscribingReference
            && !referenceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var pipelineStage: PipelineStage {
        if phase == .generating { return .generating }
        if generatedAudioPath != nil { return .generated }
        guard referenceAudioPath != nil else { return .readyForScript }
        if isTranscribingReference { return .transcribing }
        if referenceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .correctTranscript }
        return .readyForScript
    }

    /// Records the narrator after capture. This deliberately does not depend on
    /// the local TTS service: the typed script is a reading aid for a human take.
    func startVoiceoverRecording(outputDir: URL, onStarted: @escaping @MainActor () -> Void = {}) {
        guard !isRecordingVoiceover else { return }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                error = "Microphone access is required to record a voiceover."
                return
            }
            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                let url = outputDir.appendingPathComponent("recorded-voiceover-\(UUID().uuidString.prefix(8)).wav")
                let recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false
                ])
                recorder.prepareToRecord()
                guard recorder.record() else { throw VoiceGenError.voiceoverRecordingFailed }
                voiceoverRecorder = recorder
                voiceoverStartedAt = Date()
                voiceoverRecordingSeconds = 0
                isRecordingVoiceover = true
                error = nil
                onStarted()
                voiceoverTimer?.invalidate()
                voiceoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let start = self.voiceoverStartedAt else { return }
                        self.voiceoverRecordingSeconds = Date().timeIntervalSince(start)
                    }
                }
            } catch {
                self.error = "Could not start the voiceover recording: \(error.localizedDescription)"
            }
        }
    }

    func stopVoiceoverRecording() {
        guard let recorder = voiceoverRecorder else { return }
        recorder.stop()
        voiceoverRecorder = nil
        voiceoverTimer?.invalidate(); voiceoverTimer = nil
        voiceoverStartedAt = nil
        isRecordingVoiceover = false
        Task {
            do { try await publishGeneratedAudio(at: recorder.url, name: "Recorded voiceover") }
            catch { self.error = error.localizedDescription }
        }
    }

    func startReferenceRecording() {
        guard !isRecordingReference else { return }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                error = "Microphone access is required to record a custom voice reference."
                return
            }
            do {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("OpenRecorder/voice-references", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("reference-\(UUID().uuidString.prefix(8)).wav")
                let recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 24_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false
                ])
                recorder.prepareToRecord()
                guard recorder.record(forDuration: 30) else { throw VoiceGenError.referenceRecordingFailed }
                referenceRecorder = recorder
                referenceAudioPath = nil
                referenceStartedAt = Date()
                referenceRecordingSeconds = 0
                isRecordingReference = true
                referenceTimer?.invalidate()
                referenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let start = self.referenceStartedAt else { return }
                        self.referenceRecordingSeconds = min(30, Date().timeIntervalSince(start))
                        if self.referenceRecordingSeconds >= 30 { self.stopReferenceRecording() }
                    }
                }
            } catch {
                self.error = "Could not start the reference recording: \(error.localizedDescription)"
            }
        }
    }

    func stopReferenceRecording() {
        guard let recorder = referenceRecorder else { return }
        recorder.stop()
        referenceRecorder = nil
        referenceTimer?.invalidate(); referenceTimer = nil
        referenceStartedAt = nil
        isRecordingReference = false
        selectReferenceAudio(recorder.url)
    }

    func selectReferenceAudio(_ url: URL) {
        let requestID = UUID()
        referenceRequestID = requestID
        referenceTranscript = ""
        generatedAudioPath = nil
        generatedAudioDuration = 0
        generatedAudioName = ""
        error = nil
        Task {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            guard referenceRequestID == requestID else { return }
            guard duration.isFinite, duration >= 3, duration <= 30.5 else {
                error = "Use 3–30 seconds of clear, single-speaker audio for a custom voice reference."
                referenceAudioPath = nil
                return
            }
            referenceAudioPath = url.path
            transcribeReference(url: url, requestID: requestID)
        }
    }

    func clearReferenceAudio() {
        referenceRequestID = UUID()
        referenceAudioPath = nil
        referenceTranscript = ""
        generatedAudioPath = nil
        generatedAudioDuration = 0
        generatedAudioName = ""
        referenceTranscriptProgress = nil
        isTranscribingReference = false
    }

    private func transcribeReference(url: URL, requestID: UUID) {
        isTranscribingReference = true
        referenceTranscriptProgress = 0
        error = nil
        Task {
            do {
                // Prefer the accurate model; fetch it once (verified by SHA-256).
                // Fall back to the captions model if the download is unavailable.
                var service = LocalCaptionSpeechService()
                if await LocalCaptionSpeechService.accurateModelReady() {
                    service.modelFileURL = LocalCaptionSpeechService.accurateModelFile
                } else {
                    do {
                        try await LocalCaptionSpeechService.downloadAccurateModel { [weak self] fraction in
                            Task { @MainActor in
                                guard self?.referenceRequestID == requestID else { return }
                                self?.referenceTranscriptProgress = fraction * 0.5
                            }
                        }
                        service.modelFileURL = LocalCaptionSpeechService.accurateModelFile
                    } catch {
                        Self.logger.error("Accurate model unavailable: \(error.localizedDescription)")
                        guard await LocalCaptionSpeechService.modelReady() else {
                            throw CaptionFailure.message("The local speech model is unavailable. Download it from Captions first.")
                        }
                    }
                }
                let segments = try await service.transcribe(audio: url, language: "en") { [weak self] progress in
                    Task { @MainActor in
                        guard self?.referenceRequestID == requestID else { return }
                        self?.referenceTranscriptProgress = progress
                    }
                }
                guard referenceRequestID == requestID else { return }
                referenceTranscript = segments.sorted { $0.start < $1.start }.map(\.text).joined(separator: " ")
                guard !referenceTranscript.isEmpty else {
                    throw CaptionFailure.message("No speech was detected in the reference recording.")
                }
            } catch {
                guard referenceRequestID == requestID else { return }
                self.error = "Reference transcription failed: \(error.localizedDescription)"
            }
            guard referenceRequestID == requestID else { return }
            isTranscribingReference = false
            referenceTranscriptProgress = nil
        }
    }

    func checkServer() {
        guard phase == .idle else { return }
        phase = .checking
        error = nil
        Task {
            do {
                let url = Self.ttsServerURL.appendingPathComponent("v1/models")
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    serverReady = true
                } else {
                    serverReady = false
                    error = "TTS server not responding correctly."
                }
            } catch {
                serverReady = false
                self.error = "TTS server not found at localhost:8880. Start the Qwen TTS server first."
            }
            phase = .idle
        }
    }

    // MARK: - Chunked synthesis

    /// The local model runs on CPU at roughly 2x real time, so a whole script in
    /// one request can outlast any sane timeout. Sentence-sized requests each get
    /// their own timeout and report progress.
    nonisolated static func splitScript(_ text: String, maxLength: Int = 140) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        if sentences.isEmpty { sentences = [text.trimmingCharacters(in: .whitespacesAndNewlines)] }
        var chunks: [String] = []
        var current = ""
        for sentence in sentences {
            for piece in splitLongSentence(sentence, maxLength: maxLength) {
                if current.isEmpty { current = piece }
                else if current.count + piece.count + 1 <= maxLength { current += " " + piece }
                else { chunks.append(current); current = piece }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.filter { !$0.isEmpty }
    }

    private nonisolated static func splitLongSentence(_ sentence: String, maxLength: Int) -> [String] {
        guard sentence.count > maxLength else { return [sentence] }
        var pieces: [String] = []
        var current = ""
        for word in sentence.split(separator: " ", omittingEmptySubsequences: true) {
            if !current.isEmpty, current.count + word.count + 1 > maxLength {
                pieces.append(current); current = String(word)
            } else {
                current += (current.isEmpty ? "" : " ") + word
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    private func synthesize(
        chunks: [String],
        outputDir: URL,
        prefix: String,
        body: (String) -> [String: Any]
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let url = Self.ttsServerURL.appendingPathComponent("v1/audio/speech")
        var partURLs: [URL] = []
        defer { partURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        for (index, chunk) in chunks.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 300
            var payload = body(chunk)
            payload["input"] = chunk
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw VoiceGenError.serverError(message: Self.serverMessage(from: data, response: response))
            }
            let part = outputDir.appendingPathComponent("part-\(UUID().uuidString.prefix(8)).wav")
            try data.write(to: part)
            partURLs.append(part)
            progress = Double(index + 1) / Double(chunks.count)
            Self.logger.info("Voice chunk \(index + 1)/\(chunks.count) generated")
        }
        let output = outputDir.appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8)).wav")
        try Self.concatenateWAVs(partURLs, to: output)
        return output
    }

    private nonisolated static func concatenateWAVs(_ parts: [URL], to output: URL, gap: Double = 0.15) throws {
        guard let first = parts.first else { throw VoiceGenError.emptyOutput }
        if parts.count == 1 { try FileManager.default.copyItem(at: first, to: output); return }
        let head = try AVAudioFile(forReading: first)
        let format = head.processingFormat
        let out = try AVAudioFile(forWriting: output, settings: head.fileFormat.settings,
                                  commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        let gapFrames = AVAudioFrameCount(format.sampleRate * gap)
        for (index, part) in parts.enumerated() {
            let file = try AVAudioFile(forReading: part)
            guard file.processingFormat.sampleRate == format.sampleRate,
                  file.processingFormat.channelCount == format.channelCount,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw VoiceGenError.emptyOutput
            }
            try file.read(into: buffer)
            try out.write(from: buffer)
            if index < parts.count - 1, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: gapFrames) {
                silence.frameLength = gapFrames
                try out.write(from: silence)
            }
        }
    }

    /// Generates narration with one of the built-in AI voices. No sample involved.
    func generatePresetVoice(text: String, outputDir: URL) {
        guard canGenerate else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = VoiceGenError.noText.localizedDescription
            return
        }
        phase = .generating
        progress = 0
        error = nil
        let cfg = config.clamped
        Task {
            do {
                let outputPath = try await synthesize(chunks: Self.splitScript(text), outputDir: outputDir, prefix: "generated-voice") { _ in
                    var body: [String: Any] = [
                        "model": cfg.model, "voice": cfg.voice.speaker, "language": "English",
                        "speed": cfg.speed, "pitch": cfg.pitch, "response_format": "wav"
                    ]
                    if let instruction = cfg.tone.instruction { body["instruct"] = instruction }
                    return body
                }
                try await publishGeneratedAudio(at: outputPath, name: cfg.voice.title)
                progress = 1
                phase = .idle
            } catch {
                self.error = error.localizedDescription
                phase = .idle
                progress = nil
            }
        }
    }

    func generateCustomVoice(
        text: String,
        referenceAudio: URL,
        referenceTranscript: String,
        outputDir: URL,
        replaceTimeline: Bool = true
    ) {
        guard canGenerate else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = VoiceGenError.noText.localizedDescription
            return
        }
        guard !referenceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = VoiceGenError.referenceTranscriptRequired.localizedDescription
            return
        }
        phase = .generating
        progress = 0
        error = nil
        let cfg = config.clamped
        Task {
            do {
                let audio = try Data(contentsOf: referenceAudio)
                guard !audio.isEmpty else { throw VoiceGenError.invalidReference }
                let referenceB64 = audio.base64EncodedString()
                let chunks = Self.splitScript(text)
                let outputPath = try await synthesize(chunks: chunks, outputDir: outputDir, prefix: "generated-custom-voice") { _ in
                    [
                        "model": cfg.model, "voice": "custom", "language": "English",
                        "reference_audio_b64": referenceB64,
                        "reference_text": referenceTranscript,
                        "speed": cfg.speed,
                        "pitch": cfg.pitch,
                        "response_format": "wav"
                    ]
                }
                if replaceTimeline {
                    try await publishGeneratedAudio(at: outputPath, name: "Custom voice")
                } else {
                    try publishPreviewAudio(at: outputPath)
                }
                progress = 1; phase = .idle
            } catch {
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    self.error = "The voice server took too long on one sentence. Restart the Qwen TTS server (scripts/setup-qwen-tts.zsh) and try again."
                } else {
                    self.error = error.localizedDescription
                }
                self.phase = .idle
                self.progress = nil
            }
        }
    }

    /// Generates a short private preview of the sampled voice without changing
    /// the project's timeline voiceover.
    func generateVoiceProfilePreview(referenceAudio: URL, referenceTranscript: String, outputDir: URL) {
        generateCustomVoice(
            text: referenceTranscript,
            referenceAudio: referenceAudio,
            referenceTranscript: referenceTranscript,
            outputDir: outputDir,
            replaceTimeline: false
        )
    }

    func togglePreviewPlayback() {
        guard let path = previewAudioPath else { return }
        if let player = previewPlayer, player.isPlaying {
            player.stop()
            player.currentTime = 0
            isPreviewing = false
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.prepareToPlay()
            guard player.play() else { throw VoiceGenError.previewPlaybackFailed }
            previewPlayer = player
            isPreviewing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration) { [weak self, weak player] in
                guard let self, self.previewPlayer === player, !(player?.isPlaying ?? false) else { return }
                self.isPreviewing = false
            }
        } catch {
            self.error = "Could not play the voice preview: \(error.localizedDescription)"
            isPreviewing = false
        }
    }

    private func publishGeneratedAudio(at url: URL, name: String) async throws {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        guard duration.isFinite, duration > 0.1 else {
            throw VoiceGenError.emptyOutput
        }
        generatedAudioDuration = duration
        generatedAudioName = name
        generatedAudioPath = url.path
    }

    private func publishPreviewAudio(at url: URL) throws {
        let player = try AVAudioPlayer(contentsOf: url)
        guard player.duration.isFinite, player.duration > 0.1 else { throw VoiceGenError.emptyOutput }
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewing = false
        previewAudioPath = url.path
    }

    private static func serverMessage(from data: Data, response: URLResponse) -> String {
        struct ErrorResponse: Decodable { let detail: String? }
        let detail = try? JSONDecoder().decode(ErrorResponse.self, from: data).detail
        let status = (response as? HTTPURLResponse)?.statusCode
        let message = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message, !message.isEmpty { return "TTS server error: \(message)" }
        if let status { return "TTS server returned HTTP \(status)." }
        return "TTS server returned an invalid response."
    }

    enum VoiceGenError: LocalizedError {
        case serverError(message: String)
        case noText
        case invalidReference
        case referenceTranscriptRequired
        case emptyOutput
        case previewPlaybackFailed
        case referenceRecordingFailed
        case voiceoverRecordingFailed
        var errorDescription: String? {
            switch self {
            case .serverError(let message): message
            case .noText: "Write what the voice should say in the Teleprompter box, then generate."
            case .invalidReference: "Choose a readable voice reference recording."
            case .referenceTranscriptRequired: "Wait for the voice sample transcript, then confirm it matches the recording."
            case .emptyOutput: "Voice generation returned an empty audio file. Try a clearer voice sample."
            case .previewPlaybackFailed: "Could not start voice preview playback."
            case .referenceRecordingFailed: "Could not start the reference recording."
            case .voiceoverRecordingFailed: "Could not start the voiceover recording."
            }
        }
    }
}
