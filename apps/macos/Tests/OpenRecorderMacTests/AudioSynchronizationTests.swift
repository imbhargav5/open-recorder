@preconcurrency import AVFoundation
import XCTest
@testable import OpenRecorderMac

@MainActor
final class AudioSynchronizationTests: XCTestCase {
    func testCaptureOriginUsesMediaTimeDespiteLateCallback() {
        let now = Date(timeIntervalSince1970: 1000)
        let host = CMClockGetHostTimeClock()
        let date = CaptureMediaClock.date(for: CMTime(seconds: 80, preferredTimescale: 600), clock: host,
                                         now: now, hostNow: CMTime(seconds: 80.4, preferredTimescale: 600))
        XCTAssertEqual(date?.timeIntervalSince1970 ?? 0, 999.6, accuracy: 0.000001)
        XCTAssertNil(CaptureMediaClock.date(for: .invalid, clock: host))
    }

    func testOldAudioSettingsRemainDecodable() throws {
        let old = AudioProcessingSettings.default
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "syncOffsetMs")
        let decoded = try JSONDecoder().decode(AudioProcessingSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.syncOffset, 0)
    }

    func testProcessingAndSyncOffsetsPreserveCueTimingInMovieExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await Self.makeMovie(in: directory)
        for (offset, expected) in [(0.0, 0.7), (150.0, 0.85), (-300.0, 0.4)] {
            let shifted = try await ProjectAudioProcessor.synchronizedAsset(from: source, offsetMs: offset)
            var settings = AudioProcessingSettings.voice
            settings.routing = .left
            let analysis = try await ProjectAudioProcessor.analyze(asset: shifted, settings: settings)
            let mix = try await ProjectAudioProcessor.mix(for: shifted, settings: settings,
                normalizationGain: analysis.normalizationGain(target: settings.targetLUFS))
            let export = try XCTUnwrap(AVAssetExportSession(asset: shifted, presetName: AVAssetExportPresetHighestQuality))
            export.audioMix = mix
            let output = directory.appendingPathComponent("offset-\(offset).mp4")
            try await export.export(to: output, as: .mp4)
            let result = AVURLAsset(url: output)
            let duration = try await result.load(.duration)
            XCTAssertEqual(duration.seconds, 2, accuracy: 0.05)
            let cue = try await cueTime(in: result)
            XCTAssertEqual(cue, expected, accuracy: 0.025, "Offset \(offset) must preserve the existing source delay")
        }
    }

    static func makeMovie(in directory: URL) async throws -> AVAsset {
        let videoURL = directory.appendingPathComponent("video.mov")
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                          kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            var pixelBuffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 0, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 2, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let audioURL = directory.appendingPathComponent("cue.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        do {
            let audio = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 86_400))
            buffer.frameLength = 86_400
            for i in 0..<86_400 {
                let tone = (24_000..<28_800).contains(i) ? Float(0.4 * sin(Double(i) * 2 * .pi * 1000 / 48_000)) : 0
                buffer.floatChannelData![0][i] = tone
                buffer.floatChannelData![1][i] = 0
            }
            try audio.write(from: buffer)
        }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let targetVideo = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let videoRange = try await videoTrack.load(.timeRange)
        try targetVideo.insertTimeRange(videoRange, of: videoTrack, at: .zero)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        let targetAudio = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        let audioRange = try await audioTrack.load(.timeRange)
        try targetAudio.insertTimeRange(audioRange, of: audioTrack,
                                        at: CMTime(seconds: 0.2, preferredTimescale: 600))
        let sourceURL = directory.appendingPathComponent("source.mp4")
        let export = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        try await export.export(to: sourceURL, as: .mp4)
        return AVURLAsset(url: sourceURL)
    }

    private func cueTime(in asset: AVAsset) async throws -> Double {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        while let sample = output.copyNextSampleBuffer() {
            let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
            let size = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: size / 4)
            _ = values.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!) }
            if let index = values.firstIndex(where: { abs($0) > 0.1 }) {
                reader.cancelReading()
                return sample.presentationTimeStamp.seconds + Double(index / 2) / 48_000
            }
        }
        XCTFail("Missing audio cue")
        return -1
    }
}
