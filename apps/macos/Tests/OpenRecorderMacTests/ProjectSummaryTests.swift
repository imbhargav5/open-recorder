import XCTest
@testable import OpenRecorderMac

final class ProjectSummaryTests: XCTestCase {
    func testMediaPathUsesScreenshotPathWhenAvailable() {
        let summary = makeProjectSummary(recordingPath: "/tmp/recording.mp4", screenshotPath: "/tmp/screenshot.png")

        XCTAssertEqual(summary.mediaKind, .screenshot)
        XCTAssertEqual(summary.mediaPath, "/tmp/screenshot.png")
    }

    func testMediaPathFallsBackToRecordingPath() {
        let summary = makeProjectSummary(recordingPath: "/tmp/recording.mp4", screenshotPath: nil)

        XCTAssertEqual(summary.mediaKind, .video)
        XCTAssertEqual(summary.mediaPath, "/tmp/recording.mp4")
    }

    func testMediaPathIsNilWhenNoMediaPathExists() {
        let summary = makeProjectSummary(recordingPath: nil, screenshotPath: nil)

        XCTAssertEqual(summary.mediaKind, .video)
        XCTAssertNil(summary.mediaPath)
    }

    func testDecodingSummaryWithoutScreenshotPathKeepsVideoMediaKind() throws {
        let json = """
        {
            "id": "project-1",
            "title": "Project",
            "path": "/tmp/project.openrecorder",
            "recordingPath": "/tmp/recording.mp4",
            "sourceName": "Display 1",
            "createdAt": "2026-06-26T00:00:00Z",
            "updatedAt": "2026-06-26T00:00:00Z",
            "lastOpenedAt": "2026-06-26T00:00:00Z",
            "missing": false
        }
        """

        let summary = try JSONDecoder().decode(ProjectSummary.self, from: Data(json.utf8))

        XCTAssertNil(summary.screenshotPath)
        XCTAssertEqual(summary.mediaKind, .video)
        XCTAssertEqual(summary.mediaPath, "/tmp/recording.mp4")
    }
}

final class ProjectDocumentMediaKindTests: XCTestCase {
    func testMediaKindPrefersScreenshotWhenBothMediaPathsExist() {
        let document = makeProjectDocument(recordingPath: "/tmp/recording.mp4", screenshotPath: "/tmp/screenshot.png")

        XCTAssertEqual(document.mediaKind, .screenshot)
    }

    func testMediaKindFallsBackToVideoWhenOnlyRecordingPathExists() {
        let document = makeProjectDocument(recordingPath: "/tmp/recording.mp4", screenshotPath: nil)

        XCTAssertEqual(document.mediaKind, .video)
    }

    func testMediaKindIsNilWhenNoMediaPathExists() {
        let document = makeProjectDocument(recordingPath: nil, screenshotPath: nil)

        XCTAssertNil(document.mediaKind)
    }
}

private func makeProjectSummary(recordingPath: String?, screenshotPath: String?) -> ProjectSummary {
    ProjectSummary(
        id: "project-1",
        title: "Project",
        path: "/tmp/project.openrecorder",
        recordingPath: recordingPath,
        screenshotPath: screenshotPath,
        sourceName: "Display 1",
        createdAt: "2026-06-26T00:00:00Z",
        updatedAt: "2026-06-26T00:00:00Z",
        lastOpenedAt: "2026-06-26T00:00:00Z",
        missing: false
    )
}

private func makeProjectDocument(recordingPath: String?, screenshotPath: String?) -> ProjectDocument {
    ProjectDocument(
        schemaVersion: 1,
        title: "Project",
        recordingPath: recordingPath,
        screenshotPath: screenshotPath,
        sourceName: "Display 1",
        createdAt: "2026-06-26T00:00:00Z",
        updatedAt: "2026-06-26T00:00:00Z",
        editorState: nil,
        recordingSession: nil
    )
}
