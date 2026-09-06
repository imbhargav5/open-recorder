import AVFoundation
import AppKit
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OpenRecorderMac

/// Opt-in integration check: encodes real videos through both AVFoundation export paths.
/// OPEN_RECORDER_ZOOM_RENDER_CHECK=1 swift test --filter AdaptiveZoomRenderTests
final class AdaptiveZoomRenderTests: XCTestCase {
    @MainActor
    func testEightRepresentativeExports() async throws {
        guard ProcessInfo.processInfo.environment["OPEN_RECORDER_ZOOM_RENDER_CHECK"] == "1" else {
            throw XCTSkip("Opt-in video encoding and visual artifacts")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/auto-zoom-validation/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        print("AUTO_ZOOM_RENDER_ARTIFACTS \(root.path)")
        let source = root.appendingPathComponent("source.mov")
        try await writeSource(to: source)
        var plain = VideoExportOptions.default
        plain.resolution = .source
        plain.frameRate = .fps30
        var padded = plain
        padded.styling.background = .solid(SerializableColor(hex: "172033"))
        padded.styling.paddingRatio = 0.1
        var cropped = padded
        cropped.cropSelection = VideoCropSelection(normalizedRect: CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8))
        var portrait = cropped
        portrait.aspectPreset = .vertical
        var square = padded
        square.aspectPreset = .square
        var inset = padded
        inset.styling.inset = VideoInsetStyling(amountRatio: 0.15, color: SerializableColor(hex: "EFEFEF"), opacity: 1,
                                              balance: VideoInsetBalance(left: 0.2, top: 0.8))
        var camera = padded
        camera.facecamVideoURL = source
        camera.facecamFallbackSettings = defaultFacecamSettings(enabled: true)
        camera.facecamFallbackSettings?.fixedDuringZoom = true
        var movingCamera = camera
        movingCamera.facecamFallbackSettings?.fixedDuringZoom = false
        let scenarios: [(String, VideoExportOptions, [CursorTelemetryClick])] = [
            ("plain", plain, [click(220, 180, 1000)]),
            ("padded", padded, [click(220, 180, 1000)]),
            ("cropped", cropped, [click(320, 120, 1000)]),
            ("portrait", portrait, [click(320, 120, 1000)]),
            ("square", square, [click(320, 120, 1000)]),
            ("pan-inset", inset, [click(220, 180, 1000), click(340, 180, 2200), click(450, 180, 3300)]),
            ("camera-fixed", camera, [click(220, 180, 1000)]),
            ("camera-moving", movingCamera, [click(220, 180, 1000)])
        ]
        for (name, options, clicks) in scenarios {
            let telemetry = CursorTelemetryPayload(width: 640, height: 360, samples: [], clicks: clicks)
            let regions = AutoZoomGenerator.generate(from: telemetry, duration: 6, cameraSettings: options.facecamFallbackSettings)
            XCTAssertFalse(regions.isEmpty, name)
            let edits = TimelineEditSnapshot(zoomRegions: regions)
            if name == "pan-inset" {
                let telemetryURL = CursorTelemetryRecorder.telemetryURL(for: source)
                try JSONEncoder().encode(telemetry).write(to: telemetryURL)
                let project = ProjectDocument(schemaVersion: 2, title: "Adaptive Zoom Validation", recordingPath: source.path,
                    screenshotPath: nil, sourceName: "Synthetic validation", createdAt: "2026-09-07T00:00:00Z",
                    updatedAt: "2026-09-07T00:00:00Z", editorState: ProjectEditorState(timelineEdits: edits),
                    recordingSession: RecordingSession(screenVideoPath: source.path, facecamVideoPath: nil, facecamOffsetMs: nil,
                        facecamSettings: nil, sourceName: "Synthetic validation", showCursorOverlay: false,
                        cursorTelemetryPath: telemetryURL.path))
                try JSONEncoder().encode(project).write(to: root.appendingPathComponent("validation.openrecorder"))
            }
            let output = root.appendingPathComponent("\(name)-adaptive.mov")
            try await VideoExportRenderer.export(sourceURL: source, targetURL: output, options: options, edits: edits)
            let asset = AVURLAsset(url: output)
            let duration = try await asset.load(.duration).seconds
            XCTAssertEqual(duration, 6, accuracy: 0.1, name)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero
            for seconds in [0.0, 0.7, 1.2, 2.5, 4.0, 5.8] {
                let image = try await imageGenerator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
                try writePNG(image, to: root.appendingPathComponent("\(name)-\(seconds).png"))
                XCTAssertGreaterThan(image.width, 0)
                if !name.hasPrefix("camera") {
                    let size = CGSize(width: image.width, height: image.height)
                    let crop = options.cropSelection ?? VideoCropSelection()
                    let sourceSize = CGSize(width: 640, height: 360)
                    let frame = PreviewStageLayout.recordingFrameRect(forAspectRatio: crop.previewAspectRatio(in: sourceSize),
                        in: size, paddingValue: options.styling.paddingRatio * 500)
                    let effect = edits.activeZoomEffect(at: seconds)
                    let transform = PreviewStageLayout.previewFullStageZoomTransform(effect: effect, stageSize: size,
                        recordingFrame: frame, sourceSize: sourceSize, cropSelection: crop,
                        inset: options.styling.inset.amountRatio * 200,
                        insetBalance: options.styling.inset.balance)
                    let layout = VideoInsetGeometry.layout(in: frame, amountRatio: options.styling.inset.amountRatio,
                        balance: options.styling.inset.balance)
                    let cropRect = crop.pixelRect(in: sourceSize)
                    let geometry = AutoZoomGeometry.fitted(sourceSize: sourceSize, cropRect: cropRect,
                        container: layout.contentRect, canvasSize: size)
                    for (marker, point) in [("red", CGPoint(x: 220, y: 180)), ("green", CGPoint(x: 320, y: 120))] {
                        let placed = CGPoint(x: geometry.contentRect.minX + (point.x - cropRect.minX) / cropRect.width * geometry.contentRect.width,
                            y: geometry.contentRect.minY + (point.y - cropRect.minY) / cropRect.height * geometry.contentRect.height)
                        let expected = placed.applying(transform)
                        // Only compare markers fully inside the visible frame.
                        if CGRect(origin: .zero, size: size).insetBy(dx: 24, dy: 24).contains(expected) {
                            let actual = try XCTUnwrap(markerCenter(image, green: marker == "green"), "\(name) \(marker)")
                            XCTAssertEqual(actual.x, expected.x, accuracy: 3, "\(name) \(seconds) \(marker) x")
                            XCTAssertEqual(actual.y, expected.y, accuracy: 3, "\(name) \(seconds) \(marker) y")
                        }
                    }
                }
            }
            // A saved legacy zoom provides a before/after artifact without shipping a second generator.
            let legacy = regions.map { region in
                TimelineZoomRegion(span: region.span, depth: 1.75, focusX: Double(clicks[0].x) / 640,
                                   focusY: Double(clicks[0].y) / 360, mode: .auto)
            }
            try await VideoExportRenderer.export(sourceURL: source,
                targetURL: root.appendingPathComponent("\(name)-legacy.mov"), options: options,
                edits: TimelineEditSnapshot(zoomRegions: legacy))
        }
    }

    private func markerCenter(_ image: CGImage, green: Bool) -> CGPoint? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var xSum = 0.0, ySum = 0.0, count = 0.0
        for y in stride(from: 0, to: image.height, by: 2) {
            for x in stride(from: 0, to: image.width, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let matches = green
                    ? color.greenComponent > 0.6 && color.redComponent < 0.4 && color.blueComponent < 0.4
                    : color.redComponent > 0.7 && color.greenComponent < 0.55 && color.blueComponent < 0.5
                if matches { xSum += Double(x); ySum += Double(y); count += 1 }
            }
        }
        return count > 3 ? CGPoint(x: xSum / count, y: ySum / count) : nil
    }

    private func click(_ x: Int, _ y: Int, _ time: Int) -> CursorTelemetryClick {
        .init(x: x, y: y, timestamp: time, button: "left", clickCount: 1)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    @MainActor
    private func writeSource(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<180 {
            while !input.isReadyForMoreMediaData {
                if let error = writer.error { throw error }
                try await Task.sleep(for: .milliseconds(2))
            }
            var optionalBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &optionalBuffer)
            let buffer = try XCTUnwrap(optionalBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 640, height: 360,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
            context.translateBy(x: 0, y: 360)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(CGColor(gray: 0.94, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            context.setFillColor(CGColor(red: 0.12, green: 0.17, blue: 0.25, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 130, height: 360))
            for (row, title) in ["Dashboard", "Projects", "Settings"].enumerated() {
                draw(title, in: context, x: 15, y: Double(65 + row * 40), size: 14, white: true)
            }
            draw("Project settings", in: context, x: 165, y: 52, size: 25)
            draw("Share a clear product walkthrough", in: context, x: 165, y: 87, size: 15)
            for (x, label) in [(220, "Edit"), (340, "Preview"), (450, "Publish")] {
                context.setFillColor(CGColor(red: 0.15, green: 0.40, blue: 0.85, alpha: 1))
                context.fill(CGRect(x: x - 42, y: 165, width: 84, height: 30))
                draw(label, in: context, x: Double(x - 30), y: 186, size: 14, white: true)
            }
            context.setFillColor(CGColor(red: 0.90, green: 0.14, blue: 0.12, alpha: 1))
            context.fillEllipse(in: CGRect(x: 212, y: 172, width: 16, height: 16))
            context.setFillColor(CGColor(red: 0.1, green: 0.8, blue: 0.15, alpha: 1))
            context.fillEllipse(in: CGRect(x: 312, y: 112, width: 16, height: 16))
            draw("A steady view makes each action easier to follow.", in: context, x: 165, y: 270, size: 14)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    private func draw(_ text: String, in context: CGContext, x: Double, y: Double, size: Double, white: Bool = false) {
        context.saveGState()
        context.translateBy(x: x, y: y)
        context.scaleBy(x: 1, y: -1)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: white ? 1 : 0.15, alpha: 1)
        ]))
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
