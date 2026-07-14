import CoreGraphics
import SwiftUI
import XCTest
@testable import OpenRecorderMac

final class StudioKeyEventScopeTests: XCTestCase {
    func testHandlesOnlyEnabledEventsFromOwningKeyWindow() {
        XCTAssertTrue(StudioKeyEventScope.shouldHandle(
            isEnabled: true,
            ownerWindowNumber: 42,
            eventWindowNumber: 42,
            ownerWindowIsKey: true
        ))

        XCTAssertFalse(StudioKeyEventScope.shouldHandle(
            isEnabled: false,
            ownerWindowNumber: 42,
            eventWindowNumber: 42,
            ownerWindowIsKey: true
        ))
        XCTAssertFalse(StudioKeyEventScope.shouldHandle(
            isEnabled: true,
            ownerWindowNumber: 42,
            eventWindowNumber: 7,
            ownerWindowIsKey: true
        ))
        XCTAssertFalse(StudioKeyEventScope.shouldHandle(
            isEnabled: true,
            ownerWindowNumber: 42,
            eventWindowNumber: 42,
            ownerWindowIsKey: false
        ))
    }

    func testRejectsEventsWithoutAResolvedWindow() {
        XCTAssertFalse(StudioKeyEventScope.shouldHandle(
            isEnabled: true,
            ownerWindowNumber: nil,
            eventWindowNumber: 42,
            ownerWindowIsKey: true
        ))
        XCTAssertFalse(StudioKeyEventScope.shouldHandle(
            isEnabled: true,
            ownerWindowNumber: 42,
            eventWindowNumber: nil,
            ownerWindowIsKey: true
        ))
    }

    func testWindowScopeCacheUpdatesAndClearsAtomically() {
        let cache = StudioKeyWindowScopeCache()
        XCTAssertNil(cache.snapshot())

        cache.update(windowNumber: 9, isKey: false)
        XCTAssertEqual(cache.snapshot()?.windowNumber, 9)
        XCTAssertEqual(cache.snapshot()?.isKey, false)

        cache.updateIsKey(true)
        XCTAssertEqual(cache.snapshot()?.isKey, true)

        cache.update(windowNumber: nil, isKey: false)
        XCTAssertNil(cache.snapshot())
    }
}

final class StudioSplitPaneSizingTests: XCTestCase {
    func testClampsStoredWidthToConfiguredBounds() {
        XCTAssertEqual(
            StudioSplitPaneSizing.normalizedSecondarySize(200, minimum: 280, maximum: 440),
            280
        )
        XCTAssertEqual(
            StudioSplitPaneSizing.normalizedSecondarySize(320, minimum: 280, maximum: 440),
            320
        )
        XCTAssertEqual(
            StudioSplitPaneSizing.normalizedSecondarySize(500, minimum: 280, maximum: 440),
            440
        )
    }

    func testSanitizesInvalidBoundsAndWidths() {
        XCTAssertEqual(
            StudioSplitPaneSizing.normalizedSecondarySize(.nan, minimum: 280, maximum: 440),
            280
        )
        XCTAssertEqual(
            StudioSplitPaneSizing.normalizedSecondarySize(100, minimum: -20, maximum: .infinity),
            0
        )
        XCTAssertEqual(
            StudioSplitPaneSizing.normalizedSecondarySize(300, minimum: 440, maximum: 280),
            440
        )
    }
}

final class TimelineHoverPreviewTests: XCTestCase {
    private let viewport = TimelineViewport(duration: 100, visibleStart: 20, visibleDuration: 10)

    func testMapsHoverToPreviewTimeWithoutPlaybackState() {
        XCTAssertEqual(
            TimelineHoverPreview.time(
                videoIsAvailable: true,
                playbackIsActive: false,
                x: 50,
                viewport: viewport,
                width: 100
            ) ?? -1,
            25,
            accuracy: 0.001
        )
    }

    func testSuppressesHoverPreviewWithoutVideoOrDuringPlayback() {
        XCTAssertNil(TimelineHoverPreview.time(
            videoIsAvailable: false,
            playbackIsActive: false,
            x: 50,
            viewport: viewport,
            width: 100
        ))
        XCTAssertNil(TimelineHoverPreview.time(
            videoIsAvailable: true,
            playbackIsActive: true,
            x: 50,
            viewport: viewport,
            width: 100
        ))
    }

    func testRejectsInvalidTimelineGeometry() {
        XCTAssertNil(TimelineHoverPreview.time(
            videoIsAvailable: true,
            playbackIsActive: false,
            x: .nan,
            viewport: viewport,
            width: 100
        ))
        XCTAssertNil(TimelineHoverPreview.time(
            videoIsAvailable: true,
            playbackIsActive: false,
            x: 50,
            viewport: viewport,
            width: 0
        ))
    }
}

final class TimelineFrameStepperTests: XCTestCase {
    func testUsesSourceFrameRate() {
        XCTAssertEqual(
            TimelineFrameStepper.targetTime(
                currentTime: 1,
                frameCount: 10,
                framesPerSecond: 60,
                duration: 10
            ),
            1 + 10.0 / 60.0,
            accuracy: 0.000_001
        )
    }

    func testClampsFrameStepsToMediaBounds() {
        XCTAssertEqual(
            TimelineFrameStepper.targetTime(
                currentTime: 0.1,
                frameCount: -10,
                framesPerSecond: 30,
                duration: 10
            ),
            0
        )
        XCTAssertEqual(
            TimelineFrameStepper.targetTime(
                currentTime: 9.9,
                frameCount: 10,
                framesPerSecond: 30,
                duration: 10
            ),
            10
        )
    }

    func testFallsBackForInvalidFrameRateAndTimes() {
        XCTAssertEqual(TimelineSourceFrameRate.normalized(.nan), 30)
        XCTAssertEqual(TimelineSourceFrameRate.normalized(0), 30)
        XCTAssertEqual(TimelineSourceFrameRate.normalized(241), 30)
        XCTAssertEqual(TimelineSourceFrameRate.normalized(59.94), 59.94, accuracy: 0.001)

        XCTAssertEqual(
            TimelineFrameStepper.targetTime(
                currentTime: .nan,
                frameCount: 10,
                framesPerSecond: .infinity,
                duration: .infinity
            ),
            0
        )
    }
}

final class PreviewPlaybackSpeedSelectionTests: XCTestCase {
    func testCalculatesForwardCycleCountForExplicitSelection() {
        let speeds = [1.0, 2.0, 4.0, 8.0]
        XCTAssertEqual(PreviewPlaybackSpeedSelection.cycleCount(from: 1, to: 4, availableSpeeds: speeds), 2)
        XCTAssertEqual(PreviewPlaybackSpeedSelection.cycleCount(from: 8, to: 2, availableSpeeds: speeds), 2)
        XCTAssertEqual(PreviewPlaybackSpeedSelection.cycleCount(from: 2, to: 2, availableSpeeds: speeds), 0)
    }

    func testRejectsUnsupportedSelectionAndFormatsLabels() {
        XCTAssertEqual(PreviewPlaybackSpeedSelection.cycleCount(from: 1, to: 3, availableSpeeds: [1, 2, 4]), 0)
        XCTAssertEqual(PreviewPlaybackSpeedSelection.label(for: 2), "2x")
        XCTAssertEqual(PreviewPlaybackSpeedSelection.label(for: 1.25), "1.25x")
        XCTAssertEqual(PreviewPlaybackSpeedSelection.label(for: .infinity), "1x")
        XCTAssertEqual(PreviewPlaybackSpeedSelection.label(for: .nan), "1x")
    }
}

final class InspectorAvailabilityTests: XCTestCase {
    func testHidesInertAudioTabWithoutRemovingCompatibilityCase() {
        XCTAssertFalse(InspectorTab.availableCases.contains(.audio))
        XCTAssertEqual(InspectorTab.availableCases, [.appearance, .cursor, .camera])
        XCTAssertTrue(InspectorTab.allCases.contains(.audio))
    }
}

final class EditorControlCompatibilityTests: XCTestCase {
    @MainActor
    func testResizableSplitPaneLegacyInitializerRemainsAvailable() {
        let split = ResizableStudioSplitPane(
            secondarySize: .constant(320),
            minPrimarySize: 520,
            minSecondarySize: 280,
            maxSecondarySize: 440,
            spacing: 12
        ) {
            EmptyView()
        } secondary: {
            EmptyView()
        }

        _ = split.body
    }

    @MainActor
    func testScreenshotSettingsLegacyExportInitializerRemainsAvailable() {
        let panel = ScreenshotSettingsPanel(
            background: .constant(.transparent),
            padding: .constant(18),
            backgroundRoundness: .constant(12),
            backgroundShadow: .constant(0.35),
            imageRoundness: .constant(0),
            imageShadow: .constant(0),
            onExport: {}
        )

        _ = panel.body
    }
}
