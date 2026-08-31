import AppKit
import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class RecordingCountdownOverlayTests: XCTestCase {
    @MainActor
    func testLocalEscapeCancelsCountdownOnceAndConsumesEvent() throws {
        var localHandler: ((NSEvent) -> NSEvent?)?
        var globalHandler: ((NSEvent) -> Void)?
        var removedMonitorCount = 0
        var cancelCount = 0
        let monitor = RecordingCountdownEscapeMonitor(
            eventMonitorClient: RecordingCountdownEventMonitorClient(
                addLocalKeyDownMonitor: { handler in
                    localHandler = handler
                    return NSObject()
                },
                addGlobalKeyDownMonitor: { handler in
                    globalHandler = handler
                    return NSObject()
                },
                removeMonitor: { _ in
                    removedMonitorCount += 1
                }
            )
        )
        monitor.install {
            cancelCount += 1
        }
        let escapeEvent = try makeKeyEvent(keyCode: 53, characters: "\u{1B}")
        let handler = try XCTUnwrap(localHandler)

        XCTAssertNil(handler(escapeEvent))
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(removedMonitorCount, 2)

        globalHandler?(escapeEvent)
        XCTAssertEqual(cancelCount, 1)
    }

    @MainActor
    func testNonEscapeKeyPassesThroughWithoutCancelingCountdown() throws {
        var localHandler: ((NSEvent) -> NSEvent?)?
        var cancelCount = 0
        let monitor = RecordingCountdownEscapeMonitor(
            eventMonitorClient: RecordingCountdownEventMonitorClient(
                addLocalKeyDownMonitor: { handler in
                    localHandler = handler
                    return NSObject()
                },
                addGlobalKeyDownMonitor: { _ in NSObject() },
                removeMonitor: { _ in }
            )
        )
        monitor.install {
            cancelCount += 1
        }
        defer { monitor.remove() }
        let letterEvent = try makeKeyEvent(keyCode: 0, characters: "a")
        let handler = try XCTUnwrap(localHandler)

        XCTAssertTrue(handler(letterEvent) === letterEvent)
        XCTAssertEqual(cancelCount, 0)
    }

    @MainActor
    func testGlobalEscapeCancelsCountdownWhenAnotherAppIsActive() async throws {
        var globalHandler: ((NSEvent) -> Void)?
        var removedMonitorCount = 0
        var cancelCount = 0
        let canceled = expectation(description: "Countdown canceled")
        let monitor = RecordingCountdownEscapeMonitor(
            eventMonitorClient: RecordingCountdownEventMonitorClient(
                addLocalKeyDownMonitor: { _ in NSObject() },
                addGlobalKeyDownMonitor: { handler in
                    globalHandler = handler
                    return NSObject()
                },
                removeMonitor: { _ in
                    removedMonitorCount += 1
                }
            )
        )
        monitor.install {
            cancelCount += 1
            canceled.fulfill()
        }
        let escapeEvent = try makeKeyEvent(keyCode: 53, characters: "\u{1B}")

        globalHandler?(escapeEvent)
        await fulfillment(of: [canceled], timeout: 1)

        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(removedMonitorCount, 2)
    }

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

    private func makeKeyEvent(keyCode: UInt16, characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
