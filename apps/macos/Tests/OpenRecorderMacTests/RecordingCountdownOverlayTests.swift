import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class RecordingCountdownOverlayTests: XCTestCase {
    func testDisplaySourceUsesMatchingDisplayFrame() {
        let source = CaptureSource(
            id: "display:42",
            kind: .display,
            name: "Display",
            subtitle: "",
            displayIndex: 1,
            displayID: 42,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
        let screens: [RecordingOverlayScreen] = [
            RecordingOverlayScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), displayID: 1),
            RecordingOverlayScreen(frame: CGRect(x: 1000, y: 0, width: 800, height: 600), displayID: 42)
        ]

        let frame = RecordingCountdownTargetResolver.frame(
            for: source,
            screens: screens
        )

        XCTAssertEqual(frame, CGRect(x: 1000, y: 0, width: 800, height: 600))
    }

    func testDisplaySourceFallsBackToFirstScreenWhenDisplayIDIsUnknown() {
        let source = CaptureSource(
            id: "display:missing",
            kind: .display,
            name: "Display",
            subtitle: "",
            displayIndex: 1,
            displayID: 99,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
        let firstScreen = RecordingOverlayScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), displayID: 1)

        let frame = RecordingCountdownTargetResolver.frame(
            for: source,
            screens: [
                firstScreen,
                RecordingOverlayScreen(frame: CGRect(x: 1000, y: 0, width: 800, height: 600), displayID: 42)
            ]
        )

        XCTAssertEqual(frame, firstScreen.frame)
    }

    func testAreaSourceUsesAreaFrame() {
        let source = CaptureSource(
            id: "area:interactive",
            kind: .area,
            name: "Selected Area",
            subtitle: "",
            displayIndex: nil,
            displayID: nil,
            windowID: nil,
            area: CaptureArea(x: 40, y: 60, width: 320, height: 180),
            thumbnailData: nil
        )

        let frame = RecordingCountdownTargetResolver.frame(
            for: source,
            screens: [RecordingOverlayScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), displayID: 1)]
        )

        XCTAssertEqual(frame, CGRect(x: 40, y: 60, width: 320, height: 180))
    }

    func testAreaSourceClampsInvalidDimensions() {
        let source = CaptureSource(
            id: "area:invalid",
            kind: .area,
            name: "Selected Area",
            subtitle: "",
            displayIndex: nil,
            displayID: nil,
            windowID: nil,
            area: CaptureArea(x: 40, y: 60, width: 0, height: -10),
            thumbnailData: nil
        )

        let frame = RecordingCountdownTargetResolver.frame(
            for: source,
            screens: [RecordingOverlayScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), displayID: 1)]
        )

        XCTAssertEqual(frame, CGRect(x: 40, y: 60, width: 1, height: 1))
    }

    func testAreaSourceWithoutSelectionFallsBackToScreen() {
        let source = CaptureSource(
            id: "area:missing",
            kind: .area,
            name: "Selected Area",
            subtitle: "",
            displayIndex: nil,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
        let screen = RecordingOverlayScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), displayID: 1)

        let frame = RecordingCountdownTargetResolver.frame(for: source, screens: [screen])

        XCTAssertEqual(frame, screen.frame)
    }

    func testWindowSourceUsesResolvedWindowFrameAndFallsBackToScreen() {
        let source = CaptureSource(
            id: "window:7",
            kind: .window,
            name: "Window",
            subtitle: "",
            displayIndex: nil,
            displayID: nil,
            windowID: 7,
            area: nil,
            thumbnailData: nil
        )
        let screen = RecordingOverlayScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), displayID: 1)

        let resolvedFrame = RecordingCountdownTargetResolver.frame(
            for: source,
            screens: [screen],
            windowFrame: CGRect(x: 100, y: 120, width: 400, height: 260)
        )
        let fallbackFrame = RecordingCountdownTargetResolver.frame(for: source, screens: [screen])

        XCTAssertEqual(resolvedFrame, CGRect(x: 100, y: 120, width: 400, height: 260))
        XCTAssertEqual(fallbackFrame, screen.frame)
    }

    func testWindowSourceIgnoresInvalidResolvedWindowFrame() {
        let source = CaptureSource(
            id: "window:7",
            kind: .window,
            name: "Window",
            subtitle: "",
            displayIndex: nil,
            displayID: nil,
            windowID: 7,
            area: nil,
            thumbnailData: nil
        )
        let screen = RecordingOverlayScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), displayID: 1)

        let frame = RecordingCountdownTargetResolver.frame(
            for: source,
            screens: [screen],
            windowFrame: CGRect(x: 100, y: 120, width: 1, height: 260)
        )

        XCTAssertEqual(frame, screen.frame)
    }

    func testDisplaySourceUsesDefaultFrameWhenScreensAreUnavailable() {
        let source = CaptureSource(
            id: "display:missing",
            kind: .display,
            name: "Display",
            subtitle: "",
            displayIndex: nil,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )

        let frame = RecordingCountdownTargetResolver.frame(for: source, screens: [])

        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 900, height: 600))
    }
}
