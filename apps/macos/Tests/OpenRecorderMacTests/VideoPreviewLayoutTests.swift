import CoreGraphics
import CoreImage
import SwiftUI
import XCTest
@testable import OpenRecorderMac

final class VideoPreviewLayoutTests: XCTestCase {
    func testFormatPlaybackTimeHandlesInvalidAndNegativeValues() {
        XCTAssertEqual(formatPlaybackTime(.nan), "0:00")
        XCTAssertEqual(formatPlaybackTime(.infinity), "0:00")
        XCTAssertEqual(formatPlaybackTime(-1), "0:00")
    }

    func testFormatPlaybackTimeUsesWholeSecondsAndMinutes() {
        XCTAssertEqual(formatPlaybackTime(9.9), "0:09")
        XCTAssertEqual(formatPlaybackTime(60), "1:00")
        XCTAssertEqual(formatPlaybackTime(125.8), "2:05")
    }

    func testVideoCompositorDoesNotCacheStreamingIntermediates() {
        let options = VideoBackgroundCompositor.ciContextOptions()

        XCTAssertEqual(options[.cacheIntermediates] as? Bool, false)
    }

    func testAutoPreviewAspectUsesCropSelectionAspect() {
        let selection = VideoCropSelection(
            normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1),
            sizing: .preset(.source)
        )

        let ratio = VideoPreviewAspectPreset.auto.aspectRatio(
            for: selection,
            sourceSize: CGSize(width: 1200, height: 800)
        )

        XCTAssertEqual(ratio, 0.75, accuracy: 0.001)
    }

    func testAutoExportAspectUsesRenderedCropSize() {
        let ratio = VideoPreviewAspectPreset.auto.aspectRatio(
            forExportSourceSize: CGSize(width: 1200, height: 800)
        )

        XCTAssertEqual(ratio, 1.5, accuracy: 0.001)
    }

    func testFixedPreviewAspectPresetsResolveExpectedRatios() {
        let cases: [(preset: VideoPreviewAspectPreset, ratio: CGFloat)] = [
            (.wide, 16.0 / 9.0),
            (.square, 1),
            (.classic, 4.0 / 3.0),
            (.vertical, 9.0 / 16.0),
            (.tall, 3.0 / 4.0),
            (.portrait, 4.0 / 5.0)
        ]

        for testCase in cases {
            XCTAssertEqual(
                testCase.preset.aspectRatio(for: .fullFrame, sourceSize: CGSize(width: 1920, height: 1080)),
                testCase.ratio,
                accuracy: 0.001
            )
        }
    }

    func testStageFitsWidePaneByHeight() {
        let size = PreviewStageLayout.fittedSize(
            forAspectRatio: PreviewStageLayout.videoAspectRatio,
            in: CGSize(width: 1200, height: 360)
        )

        XCTAssertEqual(size.width, 640, accuracy: 0.001)
        XCTAssertEqual(size.height, 360, accuracy: 0.001)
    }

    func testStageFitsTallPaneByWidth() {
        let size = PreviewStageLayout.fittedSize(
            forAspectRatio: PreviewStageLayout.videoAspectRatio,
            in: CGSize(width: 520, height: 700)
        )

        XCTAssertEqual(size.width, 520, accuracy: 0.001)
        XCTAssertEqual(size.height, 292.5, accuracy: 0.001)
    }

    func testStageReturnsZeroForInvalidInput() {
        XCTAssertEqual(
            PreviewStageLayout.fittedSize(forAspectRatio: 0, in: CGSize(width: 520, height: 700)),
            .zero
        )
        XCTAssertEqual(
            PreviewStageLayout.fittedSize(forAspectRatio: PreviewStageLayout.videoAspectRatio, in: .zero),
            .zero
        )
    }

    func testRecordingFrameKeepsSourceAspectInsidePaddedStage() {
        let rect = PreviewStageLayout.recordingFrameRect(
            forAspectRatio: PreviewStageLayout.videoAspectRatio,
            in: CGSize(width: 1200, height: 675),
            paddingValue: 50
        )

        XCTAssertEqual(rect.minX, 120, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 67.5, accuracy: 0.001)
        XCTAssertEqual(rect.width, 960, accuracy: 0.001)
        XCTAssertEqual(rect.height, 540, accuracy: 0.001)
        XCTAssertEqual(rect.width / rect.height, PreviewStageLayout.videoAspectRatio, accuracy: 0.001)
    }

    func testRecordingFrameUsesFullStageWithoutPadding() {
        let rect = PreviewStageLayout.recordingFrameRect(
            forAspectRatio: PreviewStageLayout.videoAspectRatio,
            in: CGSize(width: 1200, height: 675),
            paddingValue: 0
        )

        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1200, accuracy: 0.001)
        XCTAssertEqual(rect.height, 675, accuracy: 0.001)
    }

    func testPlainPreviewUsesBlackLetterboxFill() {
        let fill = PreviewStageLayout.letterboxFill(
            background: .transparent,
            inset: 0,
            insetOpacity: 1
        )

        XCTAssertEqual(fill, .black)
    }

    func testStyledPreviewUsesClearLetterboxFill() {
        let backgroundFill = PreviewStageLayout.letterboxFill(
            background: .solid(SerializableColor(hex: "#FF0000")),
            inset: 0,
            insetOpacity: 1
        )
        let insetFill = PreviewStageLayout.letterboxFill(
            background: .transparent,
            inset: 30,
            insetOpacity: 1
        )

        XCTAssertEqual(backgroundFill, .clear)
        XCTAssertEqual(insetFill, .clear)
    }

    func testFullStageZoomAnchorMapsSourceFocusThroughInset() {
        let anchor = PreviewStageLayout.fullStageZoomAnchor(
            effect: TimelineZoomEffect(depth: 2, focusX: 0.25, focusY: 0.75),
            stageSize: CGSize(width: 1000, height: 500),
            recordingFrame: CGRect(x: 100, y: 50, width: 800, height: 400),
            sourceSize: CGSize(width: 1600, height: 800),
            cropSelection: .fullFrame,
            inset: 50,
            insetBalance: .centered
        )

        XCTAssertEqual(anchor.x, 0.35, accuracy: 0.001)
        XCTAssertEqual(anchor.y, 0.65, accuracy: 0.001)
    }

    func testPreviewSourceZoomTransformMatchesFinalCanvasTransform() {
        let effect = TimelineZoomEffect(depth: 1.75, focusX: 0.35, focusY: 0.6)
        let rect = CGRect(x: 0, y: 0, width: 960, height: 540)

        let transform = PreviewStageLayout.previewSourceZoomTransform(
            effect: effect,
            sourceDisplaySize: rect.size
        )

        XCTAssertEqual(
            transform,
            TimelineZoomCanvasTransform.transform(for: effect, in: rect)
        )
    }

    func testPreviewViewportZoomTransformKeepsCroppedFocusFixed() {
        let viewportSize = CGSize(width: 1000, height: 500)
        let sourceSize = CGSize(width: 1600, height: 800)
        let cropSelection = VideoCropSelection(
            normalizedRect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
            sizing: .preset(.source)
        )
        let effect = TimelineZoomEffect(depth: 1.75, focusX: 0.5, focusY: 0.25)
        let focus = CGPoint(x: 500, y: 125)

        let transform = PreviewStageLayout.previewViewportZoomTransform(
            effect: effect,
            viewportSize: viewportSize,
            sourceSize: sourceSize,
            cropSelection: cropSelection
        )

        let transformedFocus = focus.applying(transform)
        XCTAssertEqual(transformedFocus.x, focus.x, accuracy: 0.001)
        XCTAssertEqual(transformedFocus.y, focus.y, accuracy: 0.001)
    }

    func testInsetGeometryUsesBalanceToDistributeFreeSpace() {
        let rect = VideoInsetGeometry.contentRect(
            in: CGRect(x: 10, y: 20, width: 200, height: 100),
            amountRatio: 0.25,
            balance: VideoInsetBalance(left: 0.38, top: 0.44)
        )

        XCTAssertEqual(rect.minX, 29, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 31, accuracy: 0.001)
        XCTAssertEqual(rect.width, 150, accuracy: 0.001)
        XCTAssertEqual(rect.height, 75, accuracy: 0.001)
    }

    func testInsetLayoutKeepsInsetFrameAtRecordingFrame() {
        let frameRect = CGRect(x: 8, y: 12, width: 200, height: 100)
        let layout = VideoInsetGeometry.layout(
            in: frameRect,
            amountRatio: 0.25,
            balance: .centered
        )

        XCTAssertEqual(layout.frameRect, frameRect)
    }

    func testInsetLayoutUsesAspectAwareCenteredInsets() {
        let layout = VideoInsetGeometry.layout(
            in: CGRect(x: 0, y: 0, width: 200, height: 100),
            amountRatio: 0.25,
            balance: .centered
        )

        XCTAssertEqual(layout.contentRect.width, 150, accuracy: 0.001)
        XCTAssertEqual(layout.contentRect.height, 75, accuracy: 0.001)
        XCTAssertEqual(layout.contentRect.minX - layout.frameRect.minX, 25, accuracy: 0.001)
        XCTAssertEqual(layout.frameRect.maxX - layout.contentRect.maxX, 25, accuracy: 0.001)
        XCTAssertEqual(layout.contentRect.minY - layout.frameRect.minY, 12.5, accuracy: 0.001)
        XCTAssertEqual(layout.frameRect.maxY - layout.contentRect.maxY, 12.5, accuracy: 0.001)
    }

    func testCenteredInsetBalancesOpposingEdgesForTallFrame() {
        let layout = VideoInsetGeometry.layout(
            in: CGRect(x: 0, y: 0, width: 100, height: 200),
            amountRatio: 0.25,
            balance: .centered
        )

        XCTAssertEqual(layout.contentRect.minX - layout.frameRect.minX, layout.frameRect.maxX - layout.contentRect.maxX, accuracy: 0.001)
        XCTAssertEqual(layout.contentRect.minY - layout.frameRect.minY, layout.frameRect.maxY - layout.contentRect.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.contentRect.midX, layout.frameRect.midX, accuracy: 0.001)
        XCTAssertEqual(layout.contentRect.midY, layout.frameRect.midY, accuracy: 0.001)
    }

    func testInsetGeometryClampsOutOfRangeBalance() {
        let rect = VideoInsetGeometry.contentRect(
            in: CGRect(x: 0, y: 0, width: 100, height: 80),
            amountRatio: 0.5,
            balance: VideoInsetBalance(left: 2, top: -1)
        )

        XCTAssertEqual(rect.minX, 50, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 50, accuracy: 0.001)
        XCTAssertEqual(rect.height, 40, accuracy: 0.001)
    }

    func testPreviewFullStageZoomTransformKeepsMappedSourceFocusFixed() {
        let stageSize = CGSize(width: 1000, height: 500)
        let recordingFrame = CGRect(x: 100, y: 50, width: 800, height: 400)
        let effect = TimelineZoomEffect(depth: 2, focusX: 0.25, focusY: 0.75)
        let anchor = PreviewStageLayout.fullStageZoomAnchor(
            effect: effect,
            stageSize: stageSize,
            recordingFrame: recordingFrame,
            sourceSize: CGSize(width: 1600, height: 800),
            cropSelection: .fullFrame,
            inset: 50,
            insetBalance: .centered
        )
        let focus = CGPoint(x: anchor.x * stageSize.width, y: anchor.y * stageSize.height)

        let transform = PreviewStageLayout.previewFullStageZoomTransform(
            effect: effect,
            stageSize: stageSize,
            recordingFrame: recordingFrame,
            sourceSize: CGSize(width: 1600, height: 800),
            cropSelection: .fullFrame,
            inset: 50,
            insetBalance: .centered
        )
        let transformedFocus = focus.applying(transform)

        XCTAssertEqual(transformedFocus.x, focus.x, accuracy: 0.001)
        XCTAssertEqual(transformedFocus.y, focus.y, accuracy: 0.001)
    }

    func testFacecamOverlayLayoutAnchorsInFullVideoCanvas() {
        let settings = FacecamSettings(
            enabled: true,
            shape: "circle",
            size: 20,
            cornerRadius: 24,
            borderWidth: 4,
            borderColor: "#FFFFFF",
            margin: 5,
            anchor: FacecamAnchor.bottomRight.rawValue
        )

        let rect = FacecamOverlayLayout.frame(
            in: CGSize(width: 1000, height: 500),
            settings: settings
        )

        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.height, 100, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 875, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 375, accuracy: 0.001)
    }

    func testFacecamOverlayLayoutCanOccupyBackgroundPadding() {
        let stageSize = CGSize(width: 1000, height: 600)
        let recordingFrame = PreviewStageLayout.recordingFrameRect(
            forAspectRatio: PreviewStageLayout.videoAspectRatio,
            in: stageSize,
            paddingValue: 50
        )
        let settings = FacecamSettings(
            enabled: true,
            shape: "circle",
            size: 20,
            cornerRadius: 24,
            borderWidth: 4,
            borderColor: "#FFFFFF",
            margin: 5,
            anchor: FacecamAnchor.bottomRight.rawValue
        )

        let rect = FacecamOverlayLayout.frame(in: stageSize, settings: settings)

        XCTAssertEqual(rect.width, 120, accuracy: 0.001)
        XCTAssertEqual(rect.height, 120, accuracy: 0.001)
        XCTAssertGreaterThan(rect.maxX, recordingFrame.maxX)
        XCTAssertGreaterThan(rect.maxY, recordingFrame.maxY)
    }

    func testFacecamOverlayLayoutAllowsZeroMarginAtCanvasEdge() {
        let stageSize = CGSize(width: 1000, height: 600)
        let settings = FacecamSettings(
            enabled: true,
            shape: "circle",
            size: 20,
            cornerRadius: 24,
            borderWidth: 4,
            borderColor: "#FFFFFF",
            margin: 0,
            anchor: FacecamAnchor.bottomRight.rawValue
        )

        let rect = FacecamOverlayLayout.frame(in: stageSize, settings: settings)

        XCTAssertEqual(rect.maxX, stageSize.width, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, stageSize.height, accuracy: 0.001)
    }

    func testFacecamSettingsClampAndResolveAnchor() {
        let settings = FacecamSettings(
            enabled: true,
            shape: "   ",
            size: 99,
            cornerRadius: 120,
            borderWidth: -4,
            borderColor: " ",
            margin: 50,
            anchor: "somewhere"
        )
        .clamped

        XCTAssertEqual(settings.shape, "circle")
        XCTAssertEqual(settings.size, 40)
        XCTAssertEqual(settings.cornerRadius, 100)
        XCTAssertEqual(settings.borderWidth, 0)
        XCTAssertEqual(settings.borderColor, "#FFFFFF")
        XCTAssertEqual(settings.margin, 12)
        XCTAssertEqual(settings.resolvedAnchor, .bottomRight)
    }

    func testTimelineCameraSettingsResolveByActiveClipAndVisibility() {
        var visible = defaultFacecamSettings(enabled: true)
        visible.anchor = FacecamAnchor.topLeft.rawValue
        var hidden = visible
        hidden.enabled = false
        let edits = TimelineEditSnapshot(cameraClips: [
            TimelineCameraClip(span: TimelineSpan(start: 0, end: 2), settings: visible),
            TimelineCameraClip(span: TimelineSpan(start: 2, end: 5), settings: hidden)
        ])

        XCTAssertEqual(edits.activeCameraSettings(at: 1, duration: 5, fallback: nil)?.anchor, FacecamAnchor.topLeft.rawValue)
        XCTAssertNil(edits.activeCameraSettings(at: 3, duration: 5, fallback: nil))
    }

    func testTimelineCameraSettingsFallbackCoversFullClip() {
        let fallback = defaultFacecamSettings(enabled: true)
        let edits = TimelineEditSnapshot.empty

        XCTAssertEqual(edits.resolvedCameraClips(duration: 5, fallback: fallback).count, 1)
        XCTAssertEqual(edits.activeCameraSettings(at: 4.99, duration: 5, fallback: fallback), fallback.clamped)
    }

    func testFinalCanvasZoomTransformIsIdentityAtOneX() {
        let transform = TimelineZoomCanvasTransform.transform(
            for: TimelineZoomEffect(depth: 1, focusX: 0.25, focusY: 0.75),
            in: CGRect(x: 0, y: 0, width: 400, height: 300)
        )

        XCTAssertEqual(transform, .identity)
    }

    func testFinalCanvasZoomTransformKeepsFocusFixed() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let focus = CGPoint(x: 100, y: 225)

        let transform = TimelineZoomCanvasTransform.transform(
            for: TimelineZoomEffect(depth: 2, focusX: 0.25, focusY: 0.75),
            in: rect
        )

        let transformedFocus = focus.applying(transform)
        XCTAssertEqual(transformedFocus.x, focus.x, accuracy: 0.001)
        XCTAssertEqual(transformedFocus.y, focus.y, accuracy: 0.001)
    }

    func testFinalCanvasZoomTransformDoublesDistanceFromFocus() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let point = CGPoint(x: 130, y: 205)

        let transform = TimelineZoomCanvasTransform.transform(
            for: TimelineZoomEffect(depth: 2, focusX: 0.25, focusY: 0.75),
            in: rect
        )

        let transformedPoint = point.applying(transform)
        XCTAssertEqual(transformedPoint.x, 160, accuracy: 0.001)
        XCTAssertEqual(transformedPoint.y, 185, accuracy: 0.001)
    }

    func testZoomOnlyExportRequiresFinalCanvasOverlayTool() {
        let edits = TimelineEditSnapshot(zoomRegions: [
            TimelineZoomRegion(span: TimelineSpan(start: 1, end: 2), depth: 2)
        ])

        XCTAssertTrue(VideoExportRenderer.needsFinalCanvasOverlayTool(
            edits: edits,
            cursorTrack: nil,
            cursorSettings: .hidden
        ))
    }

    func testCameraClipExportRequiresFinalCanvasOverlayTool() {
        let edits = TimelineEditSnapshot(cameraClips: [
            TimelineCameraClip(
                span: TimelineSpan(start: 0, end: 3),
                settings: defaultFacecamSettings(enabled: true)
            )
        ])

        XCTAssertTrue(VideoExportRenderer.needsFinalCanvasOverlayTool(
            edits: edits,
            cursorTrack: nil,
            cursorSettings: .hidden
        ))
    }

    func testPlainExportWithoutOverlayContentDoesNotRequireFinalCanvasOverlayTool() {
        XCTAssertFalse(VideoExportRenderer.needsFinalCanvasOverlayTool(
            edits: .empty,
            cursorTrack: nil,
            cursorSettings: .hidden
        ))
    }
}
