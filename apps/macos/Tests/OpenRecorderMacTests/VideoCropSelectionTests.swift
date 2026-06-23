import AppKit
import CoreGraphics
import XCTest
@testable import OpenRecorderMac

@MainActor
final class VideoCropSelectionTests: XCTestCase {
    func testPixelRectRoundTripsThroughNormalizedSelection() {
        let sourceSize = CGSize(width: 1920, height: 1080)
        let pixelRect = CGRect(x: 195, y: 115, width: 1725, height: 965)

        let selection = VideoCropSelection().withPixelRect(pixelRect, in: sourceSize)
        let roundTrip = selection.pixelRect(in: sourceSize)

        XCTAssertEqual(roundTrip.minX, 195, accuracy: 0.001)
        XCTAssertEqual(roundTrip.minY, 115, accuracy: 0.001)
        XCTAssertEqual(roundTrip.width, 1725, accuracy: 0.001)
        XCTAssertEqual(roundTrip.height, 965, accuracy: 0.001)
    }

    func testClampsTinyAndOutOfBoundsPixelRects() {
        let sourceSize = CGSize(width: 100, height: 80)

        let rect = VideoCropSelection.clampedPixelRect(
            CGRect(x: -20, y: 90, width: 3, height: 2),
            in: sourceSize
        )

        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 72, accuracy: 0.001)
        XCTAssertEqual(rect.width, 8, accuracy: 0.001)
        XCTAssertEqual(rect.height, 8, accuracy: 0.001)
    }

    func testNonFiniteNormalizedCropFallsBackToFullFrame() {
        let selection = VideoCropSelection(
            normalizedRect: CGRect(x: .nan, y: 0.2, width: 0.5, height: 0.5)
        )

        XCTAssertEqual(selection.normalizedRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertTrue(selection.isFullFrame)
    }

    func testDisplayAndPixelCropMappingUseFittedVideoFrame() {
        let sourceSize = CGSize(width: 1920, height: 1080)
        let availableSize = CGSize(width: 960, height: 720)
        let videoFrame = VideoCropGeometry.fittedVideoFrame(sourceSize: sourceSize, in: availableSize)
        let pixelRect = CGRect(x: 192, y: 108, width: 960, height: 540)

        let displayRect = VideoCropGeometry.displayRect(for: pixelRect, sourceSize: sourceSize, videoFrame: videoFrame)
        let roundTrip = VideoCropGeometry.pixelRect(for: displayRect, sourceSize: sourceSize, videoFrame: videoFrame)

        XCTAssertEqual(videoFrame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(videoFrame.minY, 90, accuracy: 0.001)
        XCTAssertEqual(displayRect.minX, 96, accuracy: 0.001)
        XCTAssertEqual(displayRect.minY, 144, accuracy: 0.001)
        XCTAssertEqual(displayRect.width, 480, accuracy: 0.001)
        XCTAssertEqual(displayRect.height, 270, accuracy: 0.001)
        XCTAssertEqual(roundTrip.minX, pixelRect.minX, accuracy: 0.001)
        XCTAssertEqual(roundTrip.minY, pixelRect.minY, accuracy: 0.001)
        XCTAssertEqual(roundTrip.width, pixelRect.width, accuracy: 0.001)
        XCTAssertEqual(roundTrip.height, pixelRect.height, accuracy: 0.001)
    }

    func testSourceExportOutputSizeUsesCropSourceDimensions() {
        let cropSize = CGSize(width: 1725, height: 965)
        let options = VideoExportOptions(
            resolution: .source,
            format: .mov,
            frameRate: .fps30,
            styling: .none,
            cropSelection: nil,
            customOutputSize: nil
        )

        let outputSize = VideoExportRenderer.resolvedOutputSize(
            for: cropSize,
            options: options
        )

        XCTAssertEqual(outputSize.width, 1724, accuracy: 0.001)
        XCTAssertEqual(outputSize.height, 964, accuracy: 0.001)
    }

    func testExportOutputSizeScalesPResolutionsByShortEdge() {
        let cropSize = CGSize(width: 1920, height: 1080)
        let options = VideoExportOptions(
            resolution: .p720,
            format: .mov,
            frameRate: .fps30,
            styling: .none,
            cropSelection: nil,
            customOutputSize: nil
        )

        let outputSize = VideoExportRenderer.resolvedOutputSize(for: cropSize, options: options)

        XCTAssertEqual(outputSize.width, 1280, accuracy: 0.001)
        XCTAssertEqual(outputSize.height, 720, accuracy: 0.001)
    }

    func testExportOutputSizeUsesSelectedAspectPreset() {
        let cropSize = CGSize(width: 1920, height: 1080)
        let baseOptions = VideoExportOptions(
            resolution: .p1080,
            format: .mov,
            frameRate: .fps30,
            styling: .none,
            cropSelection: nil,
            customOutputSize: nil
        )

        let tallSize = VideoExportRenderer.resolvedOutputSize(
            for: cropSize,
            options: baseOptions.withAspectPreset(.tall)
        )
        let squareSize = VideoExportRenderer.resolvedOutputSize(
            for: cropSize,
            options: baseOptions.withAspectPreset(.square)
        )
        let verticalSize = VideoExportRenderer.resolvedOutputSize(
            for: cropSize,
            options: baseOptions.withAspectPreset(.vertical)
        )

        XCTAssertEqual(tallSize.width, 1080, accuracy: 0.001)
        XCTAssertEqual(tallSize.height, 1440, accuracy: 0.001)
        XCTAssertEqual(squareSize.width, 1080, accuracy: 0.001)
        XCTAssertEqual(squareSize.height, 1080, accuracy: 0.001)
        XCTAssertEqual(verticalSize.width, 1080, accuracy: 0.001)
        XCTAssertEqual(verticalSize.height, 1920, accuracy: 0.001)
    }

    func testSourceExportOutputSizeExpandsCanvasForSelectedAspectPreset() {
        let cropSize = CGSize(width: 1920, height: 1080)
        let options = VideoExportOptions(
            resolution: .source,
            format: .mov,
            frameRate: .fps30,
            styling: .none,
            cropSelection: nil,
            customOutputSize: nil
        )
        .withAspectPreset(.tall)

        let outputSize = VideoExportRenderer.resolvedOutputSize(
            for: cropSize,
            options: options
        )

        XCTAssertEqual(outputSize.width, 1920, accuracy: 0.001)
        XCTAssertEqual(outputSize.height, 2560, accuracy: 0.001)
    }

    func testExportOutputSizeHonorsCustomEvenDimensions() {
        let options = VideoExportOptions(
            resolution: .custom,
            format: .mov,
            frameRate: .fps30,
            styling: .none,
            cropSelection: nil,
            customOutputSize: CGSize(width: 1001, height: 777)
        )

        let outputSize = VideoExportRenderer.resolvedOutputSize(
            for: CGSize(width: 1920, height: 1080),
            options: options
        )

        XCTAssertEqual(outputSize.width, 1000, accuracy: 0.001)
        XCTAssertEqual(outputSize.height, 776, accuracy: 0.001)
    }

    func testExportOptionModelsExposeRequestedPresets() {
        XCTAssertEqual(VideoExportResolution.exportOptions.map(\.title), ["480p", "720p", "1080p", "4K"])
        XCTAssertEqual(VideoExportFrameRate.exportOptions.map(\.title), ["15 FPS", "24 FPS", "30 FPS", "60 FPS"])
        XCTAssertEqual(VideoExportFrameRate.gifExportOptions.map(\.title), ["15 FPS", "20 FPS", "25 FPS", "30 FPS"])
        XCTAssertEqual(VideoExportFormat.allCases.map(\.title), ["MOV", "MP4", "GIF"])
        XCTAssertEqual(VideoExportQuality.allCases.map(\.title), ["Low", "Medium", "High"])
        XCTAssertEqual(VideoExportGIFSize.allCases.map(\.title), ["Medium", "Large", "Original"])
        XCTAssertFalse(VideoExportResolution.exportOptions.contains(.source))
        XCTAssertFalse(VideoExportFrameRate.exportOptions.contains(.source))
    }

    func testGIFSizeControlsRenderedOutputSize() {
        let sourceSize = CGSize(width: 1920, height: 1080)
        var options = VideoExportOptions.default
        options.format = .gif

        options.gifSize = .medium
        var outputSize = VideoExportRenderer.resolvedOutputSize(for: sourceSize, options: options)
        XCTAssertEqual(outputSize.width, 852, accuracy: 0.001)
        XCTAssertEqual(outputSize.height, 480, accuracy: 0.001)

        options.gifSize = .large
        outputSize = VideoExportRenderer.resolvedOutputSize(for: sourceSize, options: options)
        XCTAssertEqual(outputSize.width, 1280, accuracy: 0.001)
        XCTAssertEqual(outputSize.height, 720, accuracy: 0.001)

        options.gifSize = .original
        outputSize = VideoExportRenderer.resolvedOutputSize(for: sourceSize, options: options)
        XCTAssertEqual(outputSize.width, 1920, accuracy: 0.001)
        XCTAssertEqual(outputSize.height, 1080, accuracy: 0.001)
    }

    func testExportOptionsDescribeFormatSpecificSummariesAndFileSuffixes() {
        var mp4Options = VideoExportOptions.default
        mp4Options.format = .mp4
        mp4Options.quality = .medium
        XCTAssertEqual(mp4Options.summaryTitle, "1080p Medium MP4 at 30 FPS")
        XCTAssertEqual(mp4Options.fileNameSuffix, "1080p-medium-30fps")

        var gifOptions = VideoExportOptions.default
        gifOptions.format = .gif
        gifOptions.gifSize = .large
        gifOptions.frameRate = .fps20
        gifOptions.gifLoops = false
        XCTAssertEqual(gifOptions.summaryTitle, "Large GIF at 20 FPS")
        XCTAssertEqual(gifOptions.fileNameSuffix, "large-20fps")
    }

    func testRendererUsesNormalizedCropRectInSourcePixels() {
        let selection = VideoCropSelection(
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25),
            sizing: .preset(.source)
        )

        let rect = VideoExportRenderer.normalizedCropRect(
            for: selection,
            sourceSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(rect.minX, 192, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 216, accuracy: 0.001)
        XCTAssertEqual(rect.width, 960, accuracy: 0.001)
        XCTAssertEqual(rect.height, 270, accuracy: 0.001)
    }

    func testCropKeyboardArrowShortcutsMoveByOneOrTenPixels() {
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 123, modifierFlags: []), .move(dx: -1, dy: 0))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 124, modifierFlags: []), .move(dx: 1, dy: 0))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 126, modifierFlags: []), .move(dx: 0, dy: -1))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 125, modifierFlags: []), .move(dx: 0, dy: 1))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 123, modifierFlags: [.shift]), .move(dx: -10, dy: 0))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 125, modifierFlags: [.shift]), .move(dx: 0, dy: 10))
    }

    func testCropKeyboardCommandArrowShortcutsResizeByOneOrTenPixels() {
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 123, modifierFlags: [.command]), .resize(widthDelta: -1, heightDelta: 0))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 124, modifierFlags: [.command]), .resize(widthDelta: 1, heightDelta: 0))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 126, modifierFlags: [.command]), .resize(widthDelta: 0, heightDelta: 1))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 125, modifierFlags: [.command]), .resize(widthDelta: 0, heightDelta: -1))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 123, modifierFlags: [.command, .shift]), .resize(widthDelta: -10, heightDelta: 0))
        XCTAssertEqual(VideoCropKeyboardAdjustment.make(keyCode: 126, modifierFlags: [.command, .shift]), .resize(widthDelta: 0, heightDelta: 10))
    }

    func testCropKeyboardShortcutsIgnoreUnsupportedKeysAndModifiers() {
        XCTAssertNil(VideoCropKeyboardAdjustment.make(keyCode: 0, modifierFlags: []))
        XCTAssertNil(VideoCropKeyboardAdjustment.make(keyCode: 123, modifierFlags: [.option]))
        XCTAssertNil(VideoCropKeyboardAdjustment.make(keyCode: 123, modifierFlags: [.control]))
    }
}
