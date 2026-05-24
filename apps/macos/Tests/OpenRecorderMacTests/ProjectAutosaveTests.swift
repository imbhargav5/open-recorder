import CoreGraphics
import XCTest
@testable import OpenRecorderMac

@MainActor
final class ProjectAutosaveCoordinatorTests: XCTestCase {
    func testFlushSavesLatestScheduledSnapshot() async {
        var savedSnapshots: [ProjectAutosaveSnapshot] = []
        let coordinator = ProjectAutosaveCoordinator(
            debounceNanoseconds: 1_000_000_000,
            saveHandler: { snapshot in
                savedSnapshots.append(snapshot)
                return makeProjectSummary(for: snapshot)
            },
            statusHandler: { _ in }
        )
        let first = makeAutosaveSnapshot(title: "First", splitTime: 1)
        let second = makeAutosaveSnapshot(title: "Second", splitTime: 2)

        coordinator.schedule(first)
        coordinator.schedule(second)
        await coordinator.flush()

        XCTAssertEqual(savedSnapshots, [second])
    }

    func testUnchangedSnapshotIsNotSavedAgain() async {
        var saveCount = 0
        let snapshot = makeAutosaveSnapshot(title: "Already Saved", splitTime: 1)
        let coordinator = ProjectAutosaveCoordinator(
            debounceNanoseconds: 1,
            saveHandler: { snapshot in
                saveCount += 1
                return makeProjectSummary(for: snapshot)
            },
            statusHandler: { _ in }
        )

        coordinator.markSaved(snapshot)
        coordinator.schedule(snapshot)
        await coordinator.flush()

        XCTAssertEqual(saveCount, 0)
    }

    func testFlushWritesPendingSnapshotWithoutWaitingForDebounce() async {
        var savedSnapshots: [ProjectAutosaveSnapshot] = []
        let coordinator = ProjectAutosaveCoordinator(
            debounceNanoseconds: 1_000_000_000,
            saveHandler: { snapshot in
                savedSnapshots.append(snapshot)
                return makeProjectSummary(for: snapshot)
            },
            statusHandler: { _ in }
        )
        let snapshot = makeAutosaveSnapshot(title: "Flush Me", splitTime: 4)

        coordinator.schedule(snapshot)
        await coordinator.flush()

        XCTAssertEqual(savedSnapshots, [snapshot])
    }
}

final class ProjectEditorStateCodableTests: XCTestCase {
    func testOldProjectDocumentsDecodeWithoutVideoState() throws {
        let data = """
        {
          "schemaVersion": 2,
          "title": "Legacy",
          "recordingPath": "/tmp/legacy.mp4",
          "sourceName": "Display 1",
          "createdAt": "100",
          "updatedAt": "100",
          "editorState": {
            "timelineEdits": {
              "zoomRegions": [],
              "trimRegions": [],
              "annotationRegions": [],
              "clipSplitTimes": [1.5],
              "clipSpeeds": {}
            }
          }
        }
        """.data(using: .utf8)!

        let document = try JSONDecoder().decode(ProjectDocument.self, from: data)

        XCTAssertEqual(document.editorState?.timelineEdits.clipSplitTimes, [1.5])
        XCTAssertNil(document.editorState?.video)
    }

    func testProjectEditorStateRoundTripsVideoState() throws {
        var timeline = TimelineEditSnapshot.empty
        timeline.clipSplitTimes = [2.25]
        timeline.cameraClips = [
            TimelineCameraClip(
                span: TimelineSpan(start: 0, end: 2.25),
                settings: defaultFacecamSettings(enabled: false)
            )
        ]
        let video = ProjectVideoEditorState(
            background: .solid(SerializableColor(hex: "#112233")),
            padding: 24,
            borderRadius: 8,
            shadow: 0.6,
            backgroundBlur: 2,
            inset: 18,
            insetColor: SerializableColor(hex: "#445566"),
            insetOpacity: 0.75,
            insetBalance: VideoInsetBalance(left: 0.2, top: 0.8),
            cropSelection: VideoCropSelection(
                normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
                sizing: .custom(width: 1280, height: 720)
            ),
            cursorOverlay: CursorOverlaySettings(
                isVisible: true,
                loops: true,
                size: 1.5,
                smoothing: 0.8,
                styleID: "touch.dot",
                clickEffect: .ripple,
                idleBehavior: .fadeWhenIdle,
                motionEffect: .subtleLean
            ),
            facecamSettings: defaultFacecamSettings(enabled: true)
        )
        let state = ProjectEditorState(timelineEdits: timeline, video: video)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ProjectEditorState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.timelineEdits.cameraClips, timeline.cameraClips)
        XCTAssertEqual(decoded.video?.cursorOverlay.styleID, "touch.dot")
        XCTAssertEqual(decoded.video?.cursorOverlay.clickEffect, .ripple)
    }

    func testProjectEditorStateRoundTripsScreenshotState() throws {
        let screenshot = ScreenshotEditorState(
            background: .solid(SerializableColor(hex: "#112233")),
            padding: 72,
            backgroundRoundness: 32,
            backgroundShadow: 0.4,
            imageRoundness: 18,
            imageShadow: 0.2
        )
        let state = ProjectEditorState(screenshot: screenshot)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ProjectEditorState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.screenshot?.padding, 72)
    }
}

private func makeAutosaveSnapshot(title: String, splitTime: Double) -> ProjectAutosaveSnapshot {
    var timeline = TimelineEditSnapshot.empty
    timeline.clipSplitTimes = [splitTime]
    return ProjectAutosaveSnapshot(
        projectPath: "/tmp/\(title).openrecorder",
        title: title,
        recordingPath: "/tmp/\(title).mp4",
        screenshotPath: nil,
        sourceName: "Display 1",
        editorState: ProjectEditorState(timelineEdits: timeline, video: .default)
    )
}

private func makeProjectSummary(for snapshot: ProjectAutosaveSnapshot) -> ProjectSummary {
    ProjectSummary(
        id: "project-\(snapshot.title)",
        title: snapshot.title,
        path: snapshot.projectPath,
        recordingPath: snapshot.recordingPath,
        screenshotPath: snapshot.screenshotPath,
        sourceName: snapshot.sourceName,
        createdAt: "100",
        updatedAt: "200",
        lastOpenedAt: "200",
        missing: false
    )
}
