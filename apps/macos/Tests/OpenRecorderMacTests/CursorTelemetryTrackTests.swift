import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class CursorTelemetryTrackTests: XCTestCase {
    func testPayloadOffsetTimestampsShiftsSamplesAndClicks() {
        let payload = CursorTelemetryPayload(
            width: 100,
            height: 80,
            samples: [
                CursorTelemetrySample(x: 10, y: 20, timestamp: 100, cursorType: "arrow"),
                CursorTelemetrySample(x: 20, y: 30, timestamp: 300, cursorType: "beam")
            ],
            clicks: [
                CursorTelemetryClick(x: 10, y: 20, timestamp: 150, button: "left", clickCount: 1)
            ]
        )

        let shifted = payload.offsetTimestamps(byMilliseconds: 250)

        XCTAssertEqual(shifted.samples.map(\.timestamp), [350, 550])
        XCTAssertEqual(shifted.samples.map(\.cursorType), ["arrow", "beam"])
        XCTAssertEqual(shifted.clicks.map(\.timestamp), [400])
    }

    func testCursorTrackInterpolatesBetweenSamples() {
        let track = CursorTelemetryTrack(payload: CursorTelemetryPayload(
            width: 100,
            height: 80,
            samples: [
                CursorTelemetrySample(x: 10, y: 20, timestamp: 0, cursorType: "arrow"),
                CursorTelemetrySample(x: 50, y: 60, timestamp: 1_000, cursorType: "arrow")
            ],
            clicks: []
        ))

        let point = track.point(at: 0.5, loops: false, smoothing: 0)

        XCTAssertEqual(point?.x ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(point?.y ?? -1, 40, accuracy: 0.001)
    }

    func testHiddenCursorSettingsSuppressPoint() {
        let track = CursorTelemetryTrack(payload: CursorTelemetryPayload(
            width: 100,
            height: 80,
            samples: [
                CursorTelemetrySample(x: 10, y: 20, timestamp: 0, cursorType: "arrow")
            ],
            clicks: []
        ))

        XCTAssertNil(track.point(at: 0, settings: .hidden))
    }

    func testCursorTrackCanLoopPastTelemetryDuration() {
        let track = CursorTelemetryTrack(payload: CursorTelemetryPayload(
            width: 100,
            height: 80,
            samples: [
                CursorTelemetrySample(x: 0, y: 0, timestamp: 0, cursorType: "arrow"),
                CursorTelemetrySample(x: 100, y: 80, timestamp: 1_000, cursorType: "arrow")
            ],
            clicks: []
        ))

        let point = track.point(at: 1.25, loops: true, smoothing: 0)

        XCTAssertEqual(point?.x ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(point?.y ?? -1, 20, accuracy: 0.001)
    }
}
