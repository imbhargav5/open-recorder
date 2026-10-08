@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import XCTest
@testable import OpenRecorderMac

@MainActor
final class ScreenCaptureAudioTrackTests: XCTestCase {
    func testThreeMinuteIntegerMicrophoneCaptureKeepsEveryFrame() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = try ScreenCaptureAudioTrack(directory: directory, name: "three-minutes", outputType: .microphone)
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: true))
        for packet in 0..<1800 {
            let buffer = try sample(format: format, frameCount: 4410, start: 100 + Double(packet) / 10)
            recorder.sampleQueue.sync { recorder.append(buffer) }
            // Feed faster than real time without making disk throughput the test.
            try await Task.sleep(for: .milliseconds(2))
        }
        await recorder.finish()
        _ = try await recorder.result()
        let file = try AVAudioFile(forReading: recorder.audioURL)
        XCTAssertEqual(file.length, 7_938_000)
        try verifyTone(file: file, frame: 0)
        try verifyTone(file: file, frame: 44_100 * 60)
        try verifyTone(file: file, frame: 44_100 * 120)
        try verifyTone(file: file, frame: file.length - 4410)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: recorder.reportURL)) as? [String: Any])
        XCTAssertEqual(report["droppedBuffers"] as? Int, 0)
        XCTAssertEqual(report["timestampDuration"] as? Double ?? 0, 180, accuracy: 0.001)
    }

    func testNativePlanarFloatAndMonoIntegerFormats() async throws {
        for (common, rate, channels, interleaved) in [(AVAudioCommonFormat.pcmFormatFloat32, 48_000.0, AVAudioChannelCount(2), false),
                                                     (.pcmFormatInt32, 96_000.0, 1, true)] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let recorder = try ScreenCaptureAudioTrack(directory: directory, name: "native-format", outputType: .microphone)
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: common, sampleRate: rate, channels: channels, interleaved: interleaved))
            let buffer = try sample(format: format, frameCount: Int(rate / 10), start: 100)
            recorder.sampleQueue.sync { recorder.append(buffer) }
            await recorder.finish()
            _ = try await recorder.result()
            let file = try AVAudioFile(forReading: recorder.audioURL)
            XCTAssertEqual(file.length, AVAudioFramePosition(rate / 10))
            try verifyTone(file: file, frame: 0)
        }
    }

    func testScarlettStyleTwentyFourBitSamplesRemainIntact() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = try ScreenCaptureAudioTrack(directory: directory, name: "aligned-24-bit", outputType: .microphone)
        let frames = 48_000
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsAlignedHigh,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2,
            mBitsPerChannel: 24, mReserved: 0)
        var rawDescription: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &rawDescription), noErr)
        let description = try XCTUnwrap(rawDescription)
        var bytes = [Int32](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let quantized = Int32(sin(Double(frame) * 2 * .pi * 440 / 48_000) * 0.2 * 8_388_607)
            bytes[frame * 2] = quantized << 8
        }
        var rawBlock: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: bytes.count * MemoryLayout<Int32>.size, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes.count * MemoryLayout<Int32>.size,
            flags: 0, blockBufferOut: &rawBlock), noErr)
        let block = try XCTUnwrap(rawBlock)
        XCTAssertEqual(bytes.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                offsetIntoDestination: 0, dataLength: $0.count)
        }, noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: CMTime(seconds: 100, preferredTimescale: 48_000), decodeTimeStamp: .invalid)
        var sampleSize = 8
        var rawSample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: description, sampleCount: frames, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &rawSample), noErr)
        let sample = try XCTUnwrap(rawSample)
        recorder.sampleQueue.sync { recorder.append(sample) }
        await recorder.finish()
        _ = try await recorder.result()
        let file = try AVAudioFile(forReading: recorder.audioURL)
        XCTAssertEqual(file.length, AVAudioFramePosition(frames))
        let decoded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
        try file.read(into: decoded)
        let channels = try XCTUnwrap(decoded.floatChannelData)
        for frame in 0..<Int(decoded.frameLength) {
            let expected = Float(sin(Double(frame) * 2 * .pi * 440 / 48_000) * 0.2)
            XCTAssertEqual(channels[0][frame], expected, accuracy: 0.0002)
            XCTAssertEqual(channels[1][frame], 0, accuracy: 0.00001)
        }
    }

    private func sample(format: AVAudioFormat, frameCount: Int, start: Double) throws -> CMSampleBuffer {
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)))
        pcm.frameLength = AVAudioFrameCount(frameCount)
        let buffers = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        for frame in 0..<frameCount {
            for channel in 0..<Int(format.channelCount) {
                let tone = channel == 0 ? sin(Double(frame) * 2 * .pi * 440 / format.sampleRate) * 0.2 : 0
                let target = format.isInterleaved ? 0 : channel
                let index = format.isInterleaved ? frame * Int(format.channelCount) + channel : frame
                let data = try XCTUnwrap(buffers[target].mData)
                switch format.commonFormat {
                case .pcmFormatInt16: data.assumingMemoryBound(to: Int16.self)[index] = Int16(tone * 32768)
                case .pcmFormatInt32: data.assumingMemoryBound(to: Int32.self)[index] = Int32(tone * 2147483648)
                case .pcmFormatFloat32: data.assumingMemoryBound(to: Float.self)[index] = Float(tone)
                default: XCTFail("Unsupported fixture format")
                }
            }
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(format.sampleRate)),
            presentationTimeStamp: CMTime(seconds: start, preferredTimescale: Int32(format.sampleRate)), decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription,
            sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer), noErr)
        let result = try XCTUnwrap(buffer)
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: pcm.audioBufferList), noErr)
        XCTAssertEqual(CMSampleBufferSetDataReady(result), noErr)
        return result
    }

    private func verifyTone(file: AVAudioFile, frame: AVAudioFramePosition) throws {
        file.framePosition = frame
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
        try file.read(into: buffer)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for i in 0..<Int(buffer.frameLength) {
            let expected = Float(sin(Double(i) * 2 * .pi * 440 / file.processingFormat.sampleRate) * 0.2)
            XCTAssertEqual(channels[0][i], expected, accuracy: 0.0001)
            if file.processingFormat.channelCount == 2 { XCTAssertEqual(channels[1][i], 0, accuracy: 0.00001) }
        }
    }
}
