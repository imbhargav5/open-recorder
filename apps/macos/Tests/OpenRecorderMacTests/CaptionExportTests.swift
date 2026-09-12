import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OpenRecorderMac

final class CaptionExportTests: XCTestCase {
    @MainActor func testExportBurnsCaptionsAtSourceTimesAndMatchesSharedRaster() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caption-render-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mov")
        try await writeSource(source)
        var edits = TimelineEditSnapshot(clipSplitTimes: [1], clipSpeeds: [1: 2])
        edits.trimRegions = [.init(span: .init(start: 0, end: 0.25))]
        edits.captions = CaptionTrack(segments: [.init(start: 1, end: 1.8, text: "Hello, caption world!")])
        for resolution in [VideoExportResolution.source, .p720] {
            edits.zoomRegions = resolution == .p720 ? [.init(span: .init(start: 0.5, end: 1.9), depth: 2)] : []
            var options = VideoExportOptions.default
            options.resolution = resolution
            options.frameRate = .fps30
            options.format = .mov
            let output = directory.appendingPathComponent("output-\(resolution).mov")
            try await VideoExportRenderer.export(sourceURL: source, targetURL: output, options: options, edits: edits)
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let blank = try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
            let caption = try await generator.image(at: CMTime(seconds: 0.9, preferredTimescale: 600)).image
            let after = try await generator.image(at: CMTime(seconds: 1.2, preferredTimescale: 600)).image
            let canvas = CGSize(width: caption.width, height: caption.height)
            let expected = try XCTUnwrap(CaptionRenderer.render(text: "Hello, caption world!", style: .init(), canvas: canvas))
            // Compare the actual encoded movie with the identical bitmap used in the preview.
            let expectedContext = try XCTUnwrap(CGContext(data: nil, width: caption.width, height: caption.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            expectedContext.setFillColor(CGColor(gray: 0, alpha: 1))
            expectedContext.fill(CGRect(origin: .zero, size: canvas))
            expectedContext.draw(expected.image, in: expected.frame)
            let reference = try XCTUnwrap(expectedContext.makeImage())
            XCTAssertLessThan(meanDifference(caption, reference), 3, "Encoded export must match the preview raster")
            XCTAssertGreaterThan(meanBrightness(caption), meanBrightness(blank) + 0.05)
            XCTAssertLessThan(meanBrightness(after), 1, "Captions must disappear after their mapped end time")
            if let path = ProcessInfo.processInfo.environment["OPEN_RECORDER_CAPTION_ARTIFACTS"] {
                let root = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(root.appendingPathComponent("caption-\(resolution).png") as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, caption, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
            }
        }
        do {
            try await LocalCaptionSpeechService.prepareAudio(video: source, destination: directory.appendingPathComponent("audio.wav"))
            XCTFail("Video without an audio track must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("no audio")) }
    }

    @MainActor func testLocalSpeechAndOllamaIntegration() async throws {
        guard let path = ProcessInfo.processInfo.environment["OPEN_RECORDER_CAPTION_AUDIO"] else {
            throw XCTSkip("Set OPEN_RECORDER_CAPTION_AUDIO for installed-model integration; this test never downloads models")
        }
        let modelFile = ProcessInfo.processInfo.environment["OPEN_RECORDER_CAPTION_MODEL"].map { URL(fileURLWithPath: $0) } ?? LocalCaptionSpeechService.modelFile
        let ready = await LocalCaptionSpeechService.modelReady(at: modelFile)
        XCTAssertTrue(ready)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caption-speech-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("speech.wav")
        try await LocalCaptionSpeechService.prepareAudio(video: URL(fileURLWithPath: path), destination: audio)
        let segments = try await LocalCaptionSpeechService(modelFileURL: modelFile).transcribe(audio: audio, language: "en")
        XCTAssertFalse(segments.isEmpty)
        let models = try await OllamaCaptionService().models()
        let model = try XCTUnwrap(models.first(where: { $0 == "llama3:latest" }) ?? models.first)
        let cleaned = try await OllamaCaptionService().clean(segments, model: model)
        XCTAssertEqual(cleaned.map(\.id), segments.map(\.id))
        XCTAssertEqual(cleaned.map(\.start), segments.map(\.start))
        XCTAssertEqual(cleaned.map(\.end), segments.map(\.end))
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    private func meanBrightness(_ image: CGImage) -> Double {
        let values = rgba(image)
        return stride(from: 0, to: values.count, by: 4).reduce(0.0) { $0 + Double(values[$1]) } / Double(image.width * image.height)
    }
    private func meanDifference(_ a: CGImage, _ b: CGImage) -> Double {
        let first = rgba(a), second = rgba(b)
        guard first.count == second.count else { return .infinity }
        return zip(first, second).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(first.count)
    }

    @MainActor private func writeSource(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var optional: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &optional)
            let buffer = try XCTUnwrap(optional)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer)!, 0, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
