import XCTest
@testable import OpenRecorderMac

final class RecordingSessionBuilderTests: XCTestCase {
    func testBuildRecordingSessionIncludesFacecamOffsetAndTelemetry() {
        let screenURL = URL(fileURLWithPath: "/tmp/screen.mp4")
        let facecamURL = URL(fileURLWithPath: "/tmp/facecam.mov")
        let cursorURL = URL(fileURLWithPath: "/tmp/cursor.json")
        let screenStartedAt = Date(timeIntervalSince1970: 10)
        let facecamStartedAt = Date(timeIntervalSince1970: 11.25)

        let session = RecordingSessionBuilder.build(
            screenVideoURL: screenURL,
            facecamURL: facecamURL,
            sourceName: "Display 1",
            showCursor: true,
            cursorTelemetryURL: cursorURL,
            screenStartedAt: screenStartedAt,
            facecamStartedAt: facecamStartedAt
        )

        XCTAssertEqual(session.screenVideoPath, screenURL.path)
        XCTAssertEqual(session.facecamVideoPath, facecamURL.path)
        XCTAssertEqual(session.facecamOffsetMs, 1250)
        XCTAssertEqual(session.sourceName, "Display 1")
        XCTAssertTrue(session.showCursorOverlay)
        XCTAssertEqual(session.cursorTelemetryPath, cursorURL.path)
        XCTAssertEqual(session.facecamSettings?.enabled, true)
    }
}
