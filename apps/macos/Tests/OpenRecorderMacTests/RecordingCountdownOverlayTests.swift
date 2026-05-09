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

        let frame = RecordingCountdownTargetResolver.frame(
            for: source,
            screens: [
                RecordingOverlayScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), displayID: 1),
                RecordingOverlayScreen(frame: CGRect(x: 1000, y: 0, width: 800, height: 600), displayID: 42)
            ]
        )

        XCTAssertEqual(frame, CGRect(x: 1000, y: 0, width: 800, height: 600))
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
}
