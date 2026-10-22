import AVFoundation
import Foundation
import OSLog
import Observation

struct AIAudioEnhanceSettings: Codable, Equatable, Hashable, Sendable {
    var enabled = false
    var intensity: Double = 0.7
    var denoiseStrength: Double = 0.8
    var compressorAmount: Double = 0.5
    var deeser: Double = 0.3

    static let `default` = AIAudioEnhanceSettings()
    static let podcastReady = AIAudioEnhanceSettings(enabled: true, intensity: 0.85, denoiseStrength: 0.9, compressorAmount: 0.65, deeser: 0.4)

    var clamped: AIAudioEnhanceSettings {
        AIAudioEnhanceSettings(
            enabled: enabled,
            intensity: max(0, min(1, intensity)),
            denoiseStrength: max(0, min(1, denoiseStrength)),
            compressorAmount: max(0, min(1, compressorAmount)),
            deeser: max(0, min(1, deeser))
        )
    }
}

@MainActor
@Observable
final class AIAudioEnhanceController {
    enum Phase: String { case idle, downloading = "Downloading model", enhancing = "Enhancing audio" }
    private(set) var phase: Phase = .idle
    private(set) var progress: Double?
    private(set) var modelReady = false
    private(set) var error: String?
    private static let logger = Logger(subsystem: "dev.openrecorder.app", category: "AIAudioEnhance")

    private static let modelURL = URL(string: "https://github.com/niclas-niclas/rnnoise-models/raw/main/rnnoise-model.bin")!
    private static var modelDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenRecorder/ai-audio-models", isDirectory: true)
    }
    private static var modelPath: URL { modelDir.appendingPathComponent("denoise-model.bin") }

    init() {
        modelReady = FileManager.default.fileExists(atPath: Self.modelPath.path)
    }

    func downloadModel() {
        guard phase == .idle else { return }
        phase = .downloading
        progress = 0
        error = nil
        Task {
            do {
                let dir = Self.modelDir
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let (tempURL, response) = try await URLSession.shared.download(from: Self.modelURL) { [weak self] written, total in
                    Task { @MainActor in
                        self?.progress = total > 0 ? Double(written) / Double(total) : nil
                    }
                }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw EnhanceError.downloadFailed
                }
                let destination = Self.modelPath
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                modelReady = true
                phase = .idle
                progress = nil
                Self.logger.info("AI audio model downloaded successfully")
            } catch {
                self.error = error.localizedDescription
                phase = .idle
                progress = nil
            }
        }
    }

    enum EnhanceError: LocalizedError {
        case downloadFailed
        case noAudioTrack
        case processingFailed
        var errorDescription: String? {
            switch self {
            case .downloadFailed: "Failed to download the AI audio model."
            case .noAudioTrack: "No audio track found in the recording."
            case .processingFailed: "Audio processing failed."
            }
        }
    }
}

extension URLSession {
    func download(from url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> (URL, URLResponse) {
        try await download(from: url)
    }
}

final class AIAudioDSP {
    let settings: AIAudioEnhanceSettings
    private var highPassL: AudioBiquad
    private var highPassR: AudioBiquad
    private var presenceL: AudioBiquad
    private var presenceR: AudioBiquad
    private var deeserL: AudioBiquad
    private var deeserR: AudioBiquad
    private var compEnvelope = 0.0
    private var gateGain = 1.0
    private let attack: Double
    private let release: Double
    private let gateRelease: Double
    private let makeupGain: Double

    init(settings: AIAudioEnhanceSettings, sampleRate: Double) {
        self.settings = settings.clamped
        let intensity = settings.intensity

        highPassL = .filter(frequency: 75 + 65 * intensity, sampleRate: sampleRate, highPass: true)
        highPassR = .filter(frequency: 75 + 65 * intensity, sampleRate: sampleRate, highPass: true)
        presenceL = .filter(frequency: 3200, sampleRate: sampleRate, gain: 4.5 * intensity)
        presenceR = .filter(frequency: 3200, sampleRate: sampleRate, gain: 4.5 * intensity)
        deeserL = .filter(frequency: 6500, sampleRate: sampleRate, gain: -6 * settings.deeser)
        deeserR = .filter(frequency: 6500, sampleRate: sampleRate, gain: -6 * settings.deeser)
        attack = exp(-1 / (0.003 * sampleRate))
        release = exp(-1 / (0.15 * sampleRate))
        gateRelease = exp(-1 / (0.075 * sampleRate))
        makeupGain = pow(10, (3.5 * intensity) / 20)
    }

    func process(_ left: Float, _ right: Float) -> (Float, Float) {
        var l = Double(left.isFinite ? left : 0)
        var r = Double(right.isFinite ? right : 0)

        l = highPassL.process(l)
        r = highPassR.process(r)

        l = presenceL.process(l)
        r = presenceR.process(r)

        l = deeserL.process(l)
        r = deeserR.process(r)

        let peak = max(abs(l), abs(r))
        // A gentle downward expander removes room/computer noise between words.
        // It deliberately never closes fully, preventing clipped speech tails.
        let gateThreshold = pow(10, (-52 + 22 * settings.denoiseStrength) / 20)
        let targetGate = peak < gateThreshold
            ? max(0.12, peak / max(gateThreshold, 1e-9))
            : 1.0
        let gateCoefficient = targetGate < gateGain ? attack : gateRelease
        gateGain = gateCoefficient * gateGain + (1 - gateCoefficient) * targetGate
        let denoiseMix = settings.denoiseStrength * settings.intensity
        let noiseReduction = 1 - denoiseMix * (1 - gateGain)
        l *= noiseReduction
        r *= noiseReduction

        let coeff = peak > compEnvelope ? attack : release
        compEnvelope = coeff * compEnvelope + (1 - coeff) * peak

        let threshold = 0.12 * (1 - settings.compressorAmount * 0.45)
        let ratio = 1 + 5 * settings.compressorAmount
        let aboveDB = max(0, 20 * log10(max(compEnvelope, 1e-12)) - 20 * log10(max(threshold, 1e-12)))
        let reduction = aboveDB * (1 - 1 / ratio)
        let compression = pow(10, -reduction / 20) * makeupGain

        l *= compression
        r *= compression

        let ceiling = pow(10, -1.0 / 20)
        let limitAtten = min(1, ceiling / max(max(abs(l), abs(r)), 1e-12))
        l *= limitAtten
        r *= limitAtten

        return (Float(l), Float(r))
    }
}
