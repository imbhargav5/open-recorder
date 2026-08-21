import AppKit
import XCTest
@testable import OpenRecorderMac

final class HUDWindowMetricsTests: XCTestCase {
    func testHUDWindowBehaviorFollowsActiveMacOSSpace() {
        let behavior = HUDWindowChrome.collectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.stationary))
        XCTAssertEqual(HUDWindowChrome.level, .screenSaver)
    }

    func testScreenSelectionOverlayChromeCanCoverFullscreenSpaces() {
        let behavior = ScreenSelectionOverlayChrome.collectionBehavior

        XCTAssertTrue(ScreenSelectionOverlayChrome.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.stationary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertGreaterThan(ScreenSelectionOverlayChrome.level.rawValue, NSWindow.Level.screenSaver.rawValue)
    }

    func testDefaultWidthMatchesCondensedHUDLayout() {
        XCTAssertEqual(HUDWindowMetrics.defaultSize.width, 760)
    }

    func testMeasuredWidthIsPreservedWhenItFitsVisibleFrame() {
        let size = HUDWindowMetrics.clampedSize(
            for: CGSize(width: 760, height: 64),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800)
        )

        XCTAssertEqual(size.width, 760)
        XCTAssertEqual(size.height, HUDWindowMetrics.height)
    }

    func testMeasuredWidthClampsToVisibleFrameMargin() {
        let visibleWidth: CGFloat = 800
        let visibleFrame: CGRect = CGRect(x: 0, y: 0, width: visibleWidth, height: 800)
        let size = HUDWindowMetrics.clampedSize(
            for: CGSize(width: 1200, height: 64),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(size.width, visibleWidth - HUDWindowMetrics.horizontalScreenMargin * 2)
        XCTAssertEqual(size.height, HUDWindowMetrics.height)
    }

    func testWidthNeverDropsBelowMinimum() {
        let size = HUDWindowMetrics.clampedSize(
            for: CGSize(width: 120, height: 64),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800)
        )

        XCTAssertEqual(size.width, HUDWindowMetrics.minWidth)
        XCTAssertEqual(size.height, HUDWindowMetrics.height)
    }

    func testInvalidMeasurementFallsBackToDefaultWidth() {
        let size = HUDWindowMetrics.clampedSize(
            for: .zero,
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800)
        )

        XCTAssertEqual(size.width, HUDWindowMetrics.defaultSize.width)
        XCTAssertEqual(size.height, HUDWindowMetrics.height)
    }

    func testHUDBottomCenterOrigin() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 760, height: 155)
        let origin = HUDWindowMetrics.bottomCenterOrigin(for: size, visibleFrame: visibleFrame, bottomMargin: 26)

        XCTAssertEqual(origin.x, (1440 - 760) / 2)
        XCTAssertEqual(origin.y, 26)
    }

    func testHUDClampedOriginStaysWithinVisibleBounds() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 760, height: 155)

        let offscreenRight = CGPoint(x: 2000, y: 100)
        let clampedRight = HUDWindowMetrics.clampedOrigin(
            for: size,
            currentOrigin: offscreenRight,
            visibleFrame: visibleFrame,
            bottomMargin: 26
        )
        XCTAssertEqual(clampedRight.x, 1440 - 760 - HUDWindowMetrics.horizontalScreenMargin)

        let offscreenLeft = CGPoint(x: -500, y: 100)
        let clampedLeft = HUDWindowMetrics.clampedOrigin(
            for: size,
            currentOrigin: offscreenLeft,
            visibleFrame: visibleFrame,
            bottomMargin: 26
        )
        XCTAssertEqual(clampedLeft.x, HUDWindowMetrics.horizontalScreenMargin)
    }
}
