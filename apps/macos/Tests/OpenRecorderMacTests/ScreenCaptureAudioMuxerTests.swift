@preconcurrency import AVFoundation
import XCTest
@testable import OpenRecorderMac

@MainActor
final class ScreenCaptureAudioMuxerTests: XCTestCase {
    func testFinalMovieReplacesOldAudioPreservesVideoAndAlignsNativeSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await AudioSynchronizationTests.makeMovie(in: directory)
        let videoURL = directory.appendingPathComponent("captured.mp4")
        let initial = try XCTUnwrap(AVAssetExportSession(asset: source, presetName: AVAssetExportPresetPassthrough))
        try await initial.export(to: videoURL, as: .mp4)
        let mic = directory.appendingPathComponent("microphone.caf")
        let system = directory.appendingPathComponent("system.caf")
        try writeSource(mic, rate: 44_100, frequency: 440, amplitude: 0.2, pulse: true)
        try writeSource(system, rate: 48_000, frequency: 880, amplitude: 0.1, pulse: false)
        let origin = Date(timeIntervalSince1970: 100)
        try await ScreenCaptureAudioMuxer.replaceAudio(in: videoURL, sources: [
            .init(url: mic, startedAt: origin.addingTimeInterval(0.2)),
            .init(url: system, startedAt: origin)
        ], videoStartedAt: origin)
        let result = AVURLAsset(url: videoURL)
        let duration = try await result.load(.duration)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.025)
        let audioTracks = try await result.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1, "Players must hear the same single mixed audio track")
        let videoTracks = try await result.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first)
        let videoRange = try await video.load(.timeRange)
        XCTAssertEqual(videoRange.duration.seconds, 2, accuracy: 0.025)
        let file = try AVAudioFile(forReading: videoURL)
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: pcm)
        let left = try XCTUnwrap(pcm.floatChannelData)[0]
        let rate = file.processingFormat.sampleRate
        func magnitude(_ frequency: Double, start: Double, duration: Double = 0.06) -> Double {
            var real = 0.0, imag = 0.0
            let first = Int(start * rate), count = Int(duration * rate)
            for i in 0..<count {
                let angle = Double(i) * 2 * .pi * frequency / rate
                real += Double(left[first+i]) * cos(angle)
                imag += Double(left[first+i]) * sin(angle)
            }
            return 2 * hypot(real, imag) / Double(count)
        }
        XCTAssertLessThan(magnitude(440, start: 0.2), 0.01)
        XCTAssertGreaterThan(magnitude(440, start: 0.32), 0.15, "The mic cue starts at .1 + .2 seconds")
        XCTAssertGreaterThan(magnitude(880, start: 0.32), 0.07, "System audio at a different sample rate must remain audible")
        XCTAssertLessThan(magnitude(1000, start: 0.72), 0.01, "Original SCRecordingOutput audio must be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mic.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: system.path))
    }

    private func writeSource(_ url: URL, rate: Double, frequency: Double, amplitude: Double, pulse: Bool) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * 1.8)))
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) {
            let time = Double(i) / rate
            let tone = !pulse || (0.1..<0.2).contains(time) ? Float(sin(time * 2 * .pi * frequency) * amplitude) : 0
            buffer.floatChannelData![0][i] = tone
            buffer.floatChannelData![1][i] = 0
        }
        try file.write(from: buffer)
    }
}
