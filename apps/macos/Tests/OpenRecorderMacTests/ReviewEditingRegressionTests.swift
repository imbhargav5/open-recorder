import AppKit
import Foundation
import XCTest
@testable import OpenRecorderMac

@MainActor
final class ReviewEditingRegressionTests: XCTestCase {
    func testLateRecordingCompletionPreservesNewEditorAndStillSavesRecording() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordingURL = directory.appendingPathComponent("recording.mp4")
        try Data("fixture".utf8).write(to: recordingURL)
        var stopContinuation: CheckedContinuation<URL, Never>?
        let model = AppModel(stopRecording: {
            await withCheckedContinuation { stopContinuation = $0 }
        }, registerCapturedMedia: { _, _ in
            throw NSError(domain: "OfflineFixture", code: 1)
        })
        model.paths = AppPaths(recordingsDir: directory.path, screenshotsDir: directory.path,
            projectsDir: directory.path, supportDir: directory.path)
        let source = CaptureSource(id: "display:1", kind: .display, name: "Display", subtitle: "",
            displayIndex: 1, displayID: nil, windowID: nil, area: nil, thumbnailData: nil)
        model.setCaptureStateForTesting(.recording(source))
        model.stopRecording()
        await waitUntil { stopContinuation != nil }
        let other = EditorSession(kind: .video, url: directory.appendingPathComponent("other.mp4"))
        model.showEditor(for: other)
        stopContinuation?.resume(returning: recordingURL)
        await waitUntil { !model.appShell.state.projects.isEmpty }
        XCTAssertEqual(model.appShell.state.lastEditorSession?.id, other.id)
        XCTAssertEqual(model.currentVideoURL, other.url)
        let saved = try XCTUnwrap(model.appShell.state.projects.first)
        let document = try JSONDecoder().decode(ProjectDocument.self,
            from: Data(contentsOf: URL(fileURLWithPath: saved.path)))
        XCTAssertEqual(document.recordingPath, recordingURL.path)
    }

    func testExactCutUsesIncomingSourceAndCameraPath() throws {
        let path = AutoZoomCameraPath(keyframes: [
            .init(time: 4, centerX: 0.7, centerY: 0.5, depth: 2),
            .init(time: 6, centerX: 0.7, centerY: 0.5, depth: 2)
        ])
        let edits = TimelineEditSnapshot(zoomRegions: [
            .init(span: .init(start: 4, end: 6), depth: 2, cameraPath: path)
        ])
        let plan = TimelineExportEditPlan(segments: [
            .init(sourceStart: 0, sourceEnd: 2, outputStart: 0, outputEnd: 2, speed: 1),
            .init(sourceStart: 4, sourceEnd: 6, outputStart: 2, outputEnd: 3, speed: 2)
        ], outputDuration: 3)
        XCTAssertEqual(plan.sourceTime(forOutputTime: 2), 4)
        XCTAssertEqual(plan.sourceTime(forOutputTime: 3), 6)
        XCTAssertNil(plan.sourceTime(forOutputTime: 3.01))
        XCTAssertEqual(TimelineZoomCanvasTransform.activeEffect(edits: edits, editPlan: plan, outputTime: 2),
            edits.activeZoomEffect(at: 4))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}
