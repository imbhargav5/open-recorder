import AppKit
import XCTest
@testable import OpenRecorderMac

final class HUDWindowMetricsTests: XCTestCase {
    func testHUDWindowBehaviorFollowsActiveMacOSSpace() {
        let behavior = HUDWindowChrome.collectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.primary))
        XCTAssertFalse(behavior.contains(.auxiliary))
        XCTAssertFalse(behavior.contains(.stationary))
        XCTAssertEqual(HUDWindowChrome.level, .screenSaver)
        XCTAssertEqual(behavior, CaptureOverlayWindowChrome.collectionBehavior)
    }

    @MainActor
    func testHUDPanelFloatsAndRemainsVisibleWhenApplicationIsInactive() {
        let panel = HUDOverlayPanel(
            contentRect: .zero,
            styleMask: HUDWindowChrome.styleMask,
            backing: .buffered,
            defer: false
        )

        HUDWindowChrome.apply(to: panel)

        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(HUDWindowChrome.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.level, HUDWindowChrome.level)
        XCTAssertEqual(panel.collectionBehavior, HUDWindowChrome.collectionBehavior)
    }

    @MainActor
    func testHUDHostWindowIsMadeInvisibleBeforeItIsOrderedOut() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hider = HUDHostWindowHidingView()
        window.contentView = hider

        hider.hideHostWindow()

        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
    }

    @MainActor
    func testHUDIsReorderedWhenItIsNotVisibleAfterActiveSpaceChanges() {
        let configurator = WindowConfigurationView()
        configurator.role = .hud
        let window = HUDOrderTrackingWindow(
            contentRect: NSRect(origin: .zero, size: HUDWindowMetrics.defaultSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        XCTAssertFalse(window.isVisible)

        configurator.syncHUDToActiveSpace(window)

        XCTAssertEqual(window.orderingActions, [.out, .frontRegardless])
    }

    @MainActor
    func testRecordingCountdownUsesNonactivatingFullscreenOverlayPanel() {
        let behavior = RecordingCountdownOverlayChrome.collectionBehavior
        let panel = RecordingCountdownOverlayPanel(
            contentRect: .zero,
            styleMask: RecordingCountdownOverlayChrome.styleMask,
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(RecordingCountdownOverlayChrome.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.primary))
        XCTAssertFalse(behavior.contains(.auxiliary))
        XCTAssertFalse(behavior.contains(.stationary))
        XCTAssertEqual(RecordingCountdownOverlayChrome.level, .screenSaver)
        XCTAssertEqual(behavior, CaptureOverlayWindowChrome.collectionBehavior)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }

    func testScreenSelectionOverlayChromeCanCoverFullscreenSpaces() {
        let behavior = ScreenSelectionOverlayChrome.collectionBehavior

        XCTAssertTrue(ScreenSelectionOverlayChrome.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.stationary))
        XCTAssertGreaterThan(ScreenSelectionOverlayChrome.level.rawValue, NSWindow.Level.screenSaver.rawValue)
    }

    func testAreaSelectionOverlayChromeCanCoverFullscreenSpaces() {
        let behavior = AreaSelectionOverlayChrome.collectionBehavior

        XCTAssertTrue(AreaSelectionOverlayChrome.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.stationary))
        XCTAssertGreaterThan(AreaSelectionOverlayChrome.level.rawValue, NSWindow.Level.screenSaver.rawValue)
    }

    func testRecordingCountdownOverlayChromeCanCoverFullscreenSpaces() {
        let behavior = RecordingCountdownOverlayChrome.collectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertFalse(behavior.contains(.primary))
        XCTAssertFalse(behavior.contains(.auxiliary))
        XCTAssertFalse(behavior.contains(.stationary))
        XCTAssertEqual(RecordingCountdownOverlayChrome.level, .screenSaver)
        XCTAssertEqual(behavior, CaptureOverlayWindowChrome.collectionBehavior)
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

private final class HUDOrderTrackingWindow: NSWindow {
    enum OrderingAction: Equatable {
        case out
        case frontRegardless
    }

    private(set) var orderingActions: [OrderingAction] = []

    override func orderOut(_ sender: Any?) {
        orderingActions.append(.out)
    }

    override func orderFrontRegardless() {
        orderingActions.append(.frontRegardless)
    }
}
