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

    func testDefaultWidthMatchesCondensedHUDLayout() {
        XCTAssertEqual(HUDWindowMetrics.defaultSize.width, 620)
    }

    func testMeasuredWidthIsPreservedWhenItFitsVisibleFrame() {
        let size = HUDWindowMetrics.clampedSize(
            for: CGSize(width: 720, height: 64),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800)
        )

        XCTAssertEqual(size.width, 720)
        XCTAssertEqual(size.height, HUDWindowMetrics.height)
    }

    func testMeasuredWidthClampsToVisibleFrameMargin() {
        let visibleWidth: CGFloat = 800
        let size = HUDWindowMetrics.clampedSize(
            for: CGSize(width: 1200, height: 64),
            visibleFrame: CGRect(x: 0, y: 0, width: visibleWidth, height: 800)
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
}
