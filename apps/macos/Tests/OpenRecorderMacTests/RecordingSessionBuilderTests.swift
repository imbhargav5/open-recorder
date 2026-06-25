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

    func testBuildRecordingSessionEnablesFacecamWithoutTimingMetadata() {
        let screenURL = URL(fileURLWithPath: "/tmp/screen.mp4")
        let facecamURL = URL(fileURLWithPath: "/tmp/facecam.mov")
        let screenStartedAt = Date(timeIntervalSince1970: 10)

        let session = RecordingSessionBuilder.build(
            screenVideoURL: screenURL,
            facecamURL: facecamURL,
            sourceName: "Display 1",
            showCursor: false,
            cursorTelemetryURL: nil,
            screenStartedAt: screenStartedAt,
            facecamStartedAt: nil
        )

        XCTAssertEqual(session.screenVideoPath, screenURL.path)
        XCTAssertEqual(session.facecamVideoPath, facecamURL.path)
        XCTAssertNil(session.facecamOffsetMs)
        XCTAssertEqual(session.sourceName, "Display 1")
        XCTAssertFalse(session.showCursorOverlay)
        XCTAssertNil(session.cursorTelemetryPath)
        XCTAssertEqual(session.facecamSettings?.enabled, true)
        XCTAssertTrue(session.hasRecordedCamera)
    }

    func testBuildRecordingSessionPreservesEarlyFacecamOffset() {
        let screenURL = URL(fileURLWithPath: "/tmp/screen.mp4")
        let facecamURL = URL(fileURLWithPath: "/tmp/facecam.mov")
        let screenStartedAt = Date(timeIntervalSince1970: 10)
        let facecamStartedAt = Date(timeIntervalSince1970: 9.75)

        let session = RecordingSessionBuilder.build(
            screenVideoURL: screenURL,
            facecamURL: facecamURL,
            sourceName: nil,
            showCursor: true,
            cursorTelemetryURL: nil,
            screenStartedAt: screenStartedAt,
            facecamStartedAt: facecamStartedAt
        )

        XCTAssertEqual(session.facecamOffsetMs, -250)
        XCTAssertEqual(session.facecamVideoPath, facecamURL.path)
    }

    func testBuildRecordingSessionWithoutFacecamDisablesFacecamDefaults() {
        let screenURL = URL(fileURLWithPath: "/tmp/screen.mp4")

        let session = RecordingSessionBuilder.build(
            screenVideoURL: screenURL,
            facecamURL: nil,
            sourceName: nil,
            showCursor: false,
            cursorTelemetryURL: nil,
            screenStartedAt: Date(timeIntervalSince1970: 10),
            facecamStartedAt: nil
        )

        XCTAssertEqual(session.screenVideoPath, screenURL.path)
        XCTAssertNil(session.facecamVideoPath)
        XCTAssertNil(session.facecamOffsetMs)
        XCTAssertEqual(session.facecamSettings?.enabled, false)
        XCTAssertFalse(session.showCursorOverlay)
        XCTAssertFalse(session.hasRecordedCamera)
    }

    func testBuildRecordingSessionWithoutFacecamIgnoresFacecamTimingMetadata() {
        let screenURL = URL(fileURLWithPath: "/tmp/screen.mp4")

        let session = RecordingSessionBuilder.build(
            screenVideoURL: screenURL,
            facecamURL: nil,
            sourceName: nil,
            showCursor: false,
            cursorTelemetryURL: nil,
            screenStartedAt: Date(timeIntervalSince1970: 10),
            facecamStartedAt: Date(timeIntervalSince1970: 11.25)
        )

        XCTAssertNil(session.facecamVideoPath)
        XCTAssertNil(session.facecamOffsetMs)
        XCTAssertFalse(session.hasRecordedCamera)
    }

    func testRecordingSessionHasRecordedCameraRequiresFacecamPath() {
        var session = RecordingSession(
            screenVideoPath: "/tmp/screen.mp4",
            facecamVideoPath: nil,
            facecamOffsetMs: nil,
            facecamSettings: defaultFacecamSettings(enabled: false),
            sourceName: "Display 1",
            showCursorOverlay: true,
            cursorTelemetryPath: nil
        )

        XCTAssertFalse(session.hasRecordedCamera)

        session.facecamVideoPath = ""
        XCTAssertFalse(session.hasRecordedCamera)

        session.facecamVideoPath = "   "
        XCTAssertFalse(session.hasRecordedCamera)

        session.facecamVideoPath = "/tmp/facecam.mov"
        XCTAssertTrue(session.hasRecordedCamera)
    }
}
