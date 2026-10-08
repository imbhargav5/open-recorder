@preconcurrency import AVFoundation
import XCTest
@testable import OpenRecorderMac

@MainActor
final class AudioProcessingTests: XCTestCase {
    func testMonoRoutingPreservesActiveInputWithoutAveraging() {
        var settings = AudioProcessingSettings.default
        settings.routing = .left
        let left = VoiceAudioDSP(settings: settings, sampleRate: 48_000)
        let result = left.process(0.4, 0)
        XCTAssertEqual(result.0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(result.1, 0.4, accuracy: 0.0001)
        settings.routing = .right
        let right = VoiceAudioDSP(settings: settings, sampleRate: 48_000).process(0, 0.3)
        XCTAssertEqual(right.0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(right.1, 0.3, accuracy: 0.0001)
    }

    func testLoudnessGateAndGainRespectPeakHeadroom() {
        var meter = IntegratedLoudnessMeter()
        for i in 0..<144_000 {
            let sample = Float(0.1 * sin(Double(i) * 2 * .pi * 1000 / 48_000))
            meter.add(sample, sample)
        }
        XCTAssertEqual(meter.loudness ?? 0, -20, accuracy: 0.15)
        XCTAssertNil(IntegratedLoudnessMeter().loudness)
        XCTAssertEqual(AudioLoudnessAnalysis(lufs: -25, peakDB: -4).normalizationGain(target: -14), 3)
    }

    func testAudioSettingsRoundTripAndUndo() throws {
        let edits = TimelineEditDriver()
        edits.send(.updateAudio(.voice))
        let restored = try JSONDecoder().decode(TimelineEditSnapshot.self, from: JSONEncoder().encode(edits.snapshot))
        XCTAssertEqual(restored.audio, .voice)
        edits.undo()
        XCTAssertEqual(edits.snapshot.audio, .default)
        let legacy = try JSONDecoder().decode(TimelineEditSnapshot.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.audio, .default)
    }

    func testNativeExportActuallyAppliesMonoTap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("left.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
            buffer.frameLength = 48_000
            for i in 0..<48_000 {
                buffer.floatChannelData![0][i] = Float(0.2 * sin(Double(i) * 2 * .pi * 440 / 48_000))
                buffer.floatChannelData![1][i] = 0
            }
            try file.write(from: buffer)
        }
        let asset = AVURLAsset(url: source)
        var settings = AudioProcessingSettings.default
        settings.routing = .left
        let analysis = try await ProjectAudioProcessor.analyze(asset: asset, settings: settings)
        XCTAssertNotNil(analysis.lufs)
        let mix = try await ProjectAudioProcessor.mix(for: asset, settings: settings,
            normalizationGain: analysis.normalizationGain(target: -18))
        let export = try XCTUnwrap(AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A))
        export.audioMix = mix
        let destination = directory.appendingPathComponent("mono.m4a")
        try await export.export(to: destination, as: .m4a)
        let normalized = try await ProjectAudioProcessor.analyze(asset: AVURLAsset(url: destination), settings: .default)
        XCTAssertEqual(normalized.lufs ?? 0, -18, accuracy: 0.5)
        let output = try AVAudioFile(forReading: destination)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: AVAudioFrameCount(output.length)))
        try output.read(into: buffer)
        XCTAssertEqual(buffer.format.channelCount, 2)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        var difference = 0.0, energy = 0.0
        for i in 0..<Int(buffer.frameLength) {
            difference += pow(Double(channels[0][i] - channels[1][i]), 2)
            energy += pow(Double(channels[1][i]), 2)
        }
        XCTAssertGreaterThan(energy, 100)
        XCTAssertLessThan(difference / max(energy, 1), 0.001)
    }
}
