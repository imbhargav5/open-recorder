#if DEBUG
@preconcurrency import AVFoundation
import XCTest
@testable import OpenRecorderMac

@MainActor
final class MicrophoneCaptureDiagnosticTests: XCTestCase {
    func testNativeIntegerMicrophoneBuffersAreEncodedWithoutReinterpretingBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostic = try MicrophoneCaptureDiagnostic(directory: directory, name: "integer-mic")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000,
                                               channels: 2, interleaved: true))
        let frameCount = 4_800
        var samples = [Int16](repeating: 0, count: frameCount * 2)
        for frame in 0..<frameCount {
            samples[frame * 2] = Int16(sin(Double(frame) * 2 * .pi * 440 / 48_000) * 8_000)
            // A silent second Scarlett input must remain silent.
        }
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: samples.count * 2, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: samples.count * 2, flags: 0, blockBufferOut: &block), noErr)
        let dataBlock = try XCTUnwrap(block)
        XCTAssertEqual(samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: dataBlock,
                                          offsetIntoDestination: 0, dataLength: $0.count)
        }, noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                       presentationTimeStamp: CMTime(seconds: 100, preferredTimescale: 48_000),
                                       decodeTimeStamp: .invalid)
        var bytesPerFrame = 4
        var buffer: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: dataBlock,
            formatDescription: format.formatDescription, sampleCount: frameCount, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &bytesPerFrame,
            sampleBufferOut: &buffer), noErr)
        let sampleBuffer = try XCTUnwrap(buffer)
        diagnostic.sampleQueue.sync { diagnostic.append(sampleBuffer) }
        await diagnostic.finish()
        let file = try AVAudioFile(forReading: diagnostic.audioURL)
        XCTAssertEqual(file.length, AVAudioFramePosition(frameCount))
        let decoded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(frameCount)))
        try file.read(into: decoded)
        let channels = try XCTUnwrap(decoded.floatChannelData)
        for frame in 0..<frameCount {
            XCTAssertEqual(channels[0][frame], Float(samples[frame * 2]) / 32768, accuracy: 0.0001)
            XCTAssertEqual(channels[1][frame], 0, accuracy: 0.0001)
        }
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            diagnostic.audioURL.deletingPathExtension().appendingPathExtension("json"))) as? [String: Any])
        XCTAssertEqual(report["error"] as? String, "")
        XCTAssertEqual(report["droppedBuffers"] as? Int, 0)
        XCTAssertEqual(report["timestampDuration"] as? Double ?? 0, 0.1, accuracy: 0.00001)
    }
}
#endif
