import AVFoundation
import Foundation
import OSLog
import Observation

struct VoiceGenerationConfig: Codable, Equatable, Hashable, Sendable {
    enum Voice: String, CaseIterable, Codable, Identifiable, Sendable {
        case vivian, serena, ryan, aiden
        var id: String { rawValue }
        var speaker: String {
            switch self {
            case .vivian: "Vivian"
            case .serena: "Serena"
            case .ryan: "Ryan"
            case .aiden: "Aiden"
            }
        }
        var title: String {
            switch self {
            case .vivian: "Vivian · Female · Bright"
            case .serena: "Serena · Female · Warm"
            case .ryan: "Ryan · Male · US"
            case .aiden: "Aiden · Male · US"
            }
        }
        var language: String {
            switch self {
            default: "English"
            }
        }
    }

    var speed: Double = 1.0
    var pitch: Double = 1.0
    var voice: Voice = .vivian
    var model: String = "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"

    static let `default` = VoiceGenerationConfig()

    var clamped: VoiceGenerationConfig {
        VoiceGenerationConfig(
            speed: max(0.5, min(2.0, speed)),
            pitch: max(0.5, min(2.0, pitch)),
            voice: voice,
            model: model
        )
    }
}

@MainActor
@Observable
final class VoiceGeneratorController {
    enum Phase: String {
        case idle
        case checking = "Checking server"
        case generating = "Generating voice"
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double?
    private(set) var serverReady = false
    private(set) var error: String?
    private(set) var generatedAudioPath: String?
    private(set) var generatedAudioDuration = 0.0
    private(set) var generatedAudioName = ""
    private(set) var referenceAudioPath: String?
    private(set) var isRecordingReference = false
    private(set) var referenceRecordingSeconds = 0.0
    private(set) var isRecordingVoiceover = false
    private(set) var voiceoverRecordingSeconds = 0.0
    private(set) var isTranscribingReference = false
    private(set) var referenceTranscriptProgress: Double?
    var referenceTranscript = ""
    var config = VoiceGenerationConfig.default

    @ObservationIgnored private var referenceRecorder: AVAudioRecorder?
    @ObservationIgnored private var referenceTimer: Timer?
    @ObservationIgnored private var referenceStartedAt: Date?
    @ObservationIgnored private var referenceRequestID = UUID()
    @ObservationIgnored private var voiceoverRecorder: AVAudioRecorder?
    @ObservationIgnored private var voiceoverTimer: Timer?
    @ObservationIgnored private var voiceoverStartedAt: Date?

    private static let logger = Logger(subsystem: "dev.openrecorder.app", category: "VoiceGenerator")
    private static let ttsServerURL = URL(string: "http://localhost:8880")!

    var isBusy: Bool { phase != .idle }
    var canGenerate: Bool { !isBusy && serverReady }

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
        Task { await publishGeneratedAudio(at: recorder.url, name: "Recorded voiceover") }
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
        referenceTranscriptProgress = nil
        isTranscribingReference = false
    }

    private func transcribeReference(url: URL, requestID: UUID) {
        isTranscribingReference = true
        referenceTranscriptProgress = 0
        error = nil
        Task {
            do {
                guard await LocalCaptionSpeechService.modelReady() else {
                    throw CaptionFailure.message("The local speech model is unavailable. Download it from Captions first.")
                }
                let segments = try await LocalCaptionSpeechService().transcribe(audio: url, language: "en") { [weak self] progress in
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

    func generate(text: String, outputDir: URL) {
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
                let url = Self.ttsServerURL.appendingPathComponent("v1/audio/speech")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120

                let body: [String: Any] = [
                    "model": cfg.model,
                    "input": text,
                    "voice": cfg.voice.speaker,
                    "language": cfg.voice.language,
                    "speed": cfg.speed,
                    "response_format": "wav"
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw VoiceGenError.serverError(message: Self.serverMessage(from: data, response: response))
                }

                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                let outputPath = outputDir.appendingPathComponent("generated-voice-\(UUID().uuidString.prefix(8)).wav")
                try data.write(to: outputPath)

                await publishGeneratedAudio(at: outputPath, name: cfg.voice.title)
                Self.logger.info("Voice generated: \(outputPath.lastPathComponent)")
                progress = 1
                phase = .idle
            } catch {
                self.error = error.localizedDescription
                phase = .idle
                progress = nil
            }
        }
    }

    func generateFromSegments(_ segments: [CaptionSegment], outputDir: URL) {
        let fullText = segments.sorted(by: { $0.start < $1.start }).map(\.text).joined(separator: " ")
        generate(text: fullText, outputDir: outputDir)
    }

    func generateCustomVoice(text: String, referenceAudio: URL, referenceTranscript: String, outputDir: URL) {
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
                let audio = try Data(contentsOf: referenceAudio)
                guard !audio.isEmpty else { throw VoiceGenError.invalidReference }
                let url = Self.ttsServerURL.appendingPathComponent("v1/audio/speech")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 600
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": cfg.model, "input": text, "voice": "custom", "language": "English",
                    "reference_audio_b64": audio.base64EncodedString(),
                    "reference_text": referenceTranscript, "response_format": "wav"
                ])
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw VoiceGenError.serverError(message: Self.serverMessage(from: data, response: response))
                }
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                let outputPath = outputDir.appendingPathComponent("generated-custom-voice-\(UUID().uuidString.prefix(8)).wav")
                try data.write(to: outputPath)
                await publishGeneratedAudio(at: outputPath, name: "Custom voice")
                progress = 1; phase = .idle
            } catch {
                self.error = error.localizedDescription; self.phase = .idle; self.progress = nil
            }
        }
    }

    private func publishGeneratedAudio(at url: URL, name: String) async {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        generatedAudioDuration = duration.isFinite && duration > 0 ? duration : 0
        generatedAudioName = name
        generatedAudioPath = url.path
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
        case referenceRecordingFailed
        case voiceoverRecordingFailed
        var errorDescription: String? {
            switch self {
            case .serverError(let message): message
            case .noText: "No text to generate voice from."
            case .invalidReference: "Choose a readable voice reference recording."
            case .referenceRecordingFailed: "Could not start the reference recording."
            case .voiceoverRecordingFailed: "Could not start the voiceover recording."
            }
        }
    }
}
