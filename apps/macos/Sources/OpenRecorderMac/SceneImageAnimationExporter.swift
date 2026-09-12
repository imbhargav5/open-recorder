import AVFoundation
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum SceneImageAnimationExporter {
    static func export(sourceURL: URL, targetURL: URL, state: ScreenshotEditorState,
                       options: VideoExportOptions, cancellationToken: VideoExportCancellationToken?,
                       progressHandler: @escaping @MainActor (Double) -> Void) async throws {
        guard !ExportFileSafety.sameFile(sourceURL, targetURL) else { throw ExportFileSafety.Failure.originalFile }
        guard let image = NSImage(contentsOf: sourceURL) else { throw VideoExportRendererError.exportFailed }
        var configuration = ScreenshotExportConfiguration(screenshotState: state)
        configuration.scene = state.scene.clamped(to: state.scene.imageDuration)
        let renderer = SceneRenderer()
        let context = SceneImageContext.shared
        guard let first = ScreenshotExportRenderer(configuration: configuration).renderImage(from: image, renderer: renderer) else {
            throw VideoExportRendererError.exportFailed
        }
        let size = VideoExportRenderer.resolvedOutputSize(for: CGSize(width: first.width, height: first.height), options: options)
        let fps: Int = Int(options.frameRate.rawValue.replacingOccurrences(of: "fps", with: "")) ?? 30
        let duration = sceneClamp(state.scene.imageDuration, 0.25...60, fallback: 3)
        let count = max(1, Int(ceil(duration * Double(fps))))
        if FileManager.default.fileExists(atPath: targetURL.path) { try FileManager.default.removeItem(at: targetURL) }
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: targetURL) } }

        func checkCancellation() throws {
            if Task.isCancelled || cancellationToken?.isCancelled == true { throw CancellationError() }
        }
        func frame(at index: Int) throws -> CGImage {
            configuration.sceneTime = count > 1 ? Double(index) / Double(count - 1) * duration : 0
            guard let cg = ScreenshotExportRenderer(configuration: configuration).renderImage(from: image, renderer: renderer) else {
                throw VideoExportRendererError.exportFailed
            }
            let transform = CGAffineTransform(scaleX: size.width / CGFloat(cg.width), y: size.height / CGFloat(cg.height))
            guard let output = context.createCGImage(CIImage(cgImage: cg).transformed(by: transform), from: CGRect(origin: .zero, size: size)) else {
                throw VideoExportRendererError.exportFailed
            }
            return output
        }

        if options.format == .gif {
            guard let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, UTType.gif.identifier as CFString, count, nil) else {
                throw VideoExportRendererError.gifDestinationUnavailable
            }
            if options.gifLoops {
                CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            }
            for index in 0..<count {
                try checkCancellation()
                try autoreleasepool {
                    CGImageDestinationAddImage(destination, try frame(at: index), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / Double(fps)]] as CFDictionary)
                }
                progressHandler(Double(index + 1) / Double(count))
                await Task.yield()
            }
            try checkCancellation()
            guard CGImageDestinationFinalize(destination) else { throw VideoExportRendererError.gifDestinationUnavailable }
        } else {
            guard let fileType = options.format.avFileType else { throw VideoExportRendererError.unsupportedFormat }
            let writer = try AVAssetWriter(outputURL: targetURL, fileType: fileType)
            let bitsPerPixel: Double = options.quality == .low ? 0.04 : (options.quality == .medium ? 0.08 : 0.16)
            let bitRate = max(250_000, Int(size.width * size.height * Double(fps) * bitsPerPixel))
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate]
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ])
            guard writer.canAdd(input) else { throw VideoExportRendererError.exportFailed }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? VideoExportRendererError.exportFailed }
            writer.startSession(atSourceTime: .zero)
            do {
                for index in 0..<count {
                    try checkCancellation()
                    while !input.isReadyForMoreMediaData {
                        try checkCancellation()
                        guard writer.status == .writing else { throw writer.error ?? VideoExportRendererError.exportFailed }
                        try await Task.sleep(for: .milliseconds(2))
                    }
                    try autoreleasepool {
                        guard let pool = adaptor.pixelBufferPool else { throw VideoExportRendererError.exportFailed }
                        var pixelBuffer: CVPixelBuffer?
                        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else {
                            throw VideoExportRendererError.exportFailed
                        }
                        let rendered = CIImage(cgImage: try frame(at: index))
                        let opaque = rendered.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size)))
                        context.render(opaque, to: pixelBuffer, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                        guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(fps))) else {
                            throw writer.error ?? VideoExportRendererError.exportFailed
                        }
                    }
                    progressHandler(Double(index + 1) / Double(count))
                    await Task.yield()
                }
                input.markAsFinished()
                writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
                await writer.finishWriting()
                try checkCancellation()
                guard writer.status == .completed else { throw writer.error ?? VideoExportRendererError.exportFailed }
            } catch { writer.cancelWriting(); throw error }
        }
        completed = true
        progressHandler(1)
    }
}
