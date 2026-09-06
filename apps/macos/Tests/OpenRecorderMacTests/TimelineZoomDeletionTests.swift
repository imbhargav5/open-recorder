import XCTest
@testable import OpenRecorderMac

final class TimelineZoomDeletionTests: XCTestCase {
    private func fixture() -> TimelineEditSnapshot {
        TimelineEditSnapshot(
            zoomRegions: [
                TimelineZoomRegion(span: TimelineSpan(start: 1, end: 2), mode: .manual),
                TimelineZoomRegion(span: TimelineSpan(start: 3, end: 4), mode: .auto)
            ],
            trimRegions: [TimelineTrimRegion(span: TimelineSpan(start: 8, end: 9))],
            annotationRegions: [TimelineAnnotationRegion(span: TimelineSpan(start: 5, end: 6))],
            clipSplitTimes: [5],
            clipSpeeds: [0: 1.5],
            cameraClips: [TimelineCameraClip(span: TimelineSpan(start: 0, end: 10), settings: FacecamSettings(enabled: true, shape: "circle", size: 20, cornerRadius: 20, borderWidth: 0, borderColor: "#ffffff", margin: 4, anchor: "bottomRight"))]
        )
    }

    @MainActor
    func testDeleteAllZoomsIsOneUndoableEditAndPreservesOtherContent() throws {
        let edits = TimelineEditDriver()
        let original = fixture()
        edits.applySnapshot(original)
        let selectedID = original.zoomRegions[1].id
        edits.select(.zoom, id: selectedID)
        var expected = original
        expected.zoomRegions = []

        edits.deleteAllZooms()

        XCTAssertEqual(edits.snapshot, expected)
        XCTAssertFalse(edits.hasSelection)
        XCTAssertEqual(edits.statusMessage, "Deleted all zoom levels.")
        XCTAssertTrue(edits.canUndo)
        let saved = try JSONEncoder().encode(edits.snapshot)
        XCTAssertEqual(try JSONDecoder().decode(TimelineEditSnapshot.self, from: saved), expected)

        edits.undo()
        XCTAssertEqual(edits.snapshot, original)
        XCTAssertEqual(edits.selectedKind, .zoom)
        XCTAssertEqual(edits.selectedID, selectedID)
        XCTAssertFalse(edits.canUndo)

        edits.redo()
        XCTAssertEqual(edits.snapshot, expected)
        XCTAssertFalse(edits.hasSelection)
        XCTAssertFalse(edits.canRedo)
    }

    @MainActor
    func testDeleteAllZoomsPreservesUnrelatedSelections() {
        let original = fixture()
        for selection in 0..<4 {
            let edits = TimelineEditDriver()
            edits.applySnapshot(original)
            switch selection {
            case 0: edits.select(.trim, id: original.trimRegions[0].id)
            case 1: edits.select(.annotation, id: original.annotationRegions[0].id)
            case 2: edits.selectClip(index: 0)
            default: edits.selectCameraClip(id: original.cameraClips[0].id)
            }
            let before = edits.state
            edits.deleteAllZooms()
            XCTAssertTrue(edits.zoomRegions.isEmpty)
            XCTAssertEqual(edits.selectedKind, before.selectedKind)
            XCTAssertEqual(edits.selectedID, before.selectedID)
            XCTAssertEqual(edits.selectedClipIndex, before.selectedClipIndex)
            XCTAssertEqual(edits.selectedCameraClipID, before.selectedCameraClipID)
        }
    }

    @MainActor
    func testDeletingEmptyZoomListIsNoOpAndPreservesRedo() {
        let edits = TimelineEditDriver()
        edits.add(.zoom, at: 1, duration: 10)
        edits.undo()
        let before = edits.state
        edits.deleteAllZooms()
        XCTAssertEqual(edits.state, before)
        XCTAssertFalse(edits.canUndo)
        XCTAssertTrue(edits.canRedo)
    }

    @MainActor
    func testDefaultDeletionOnlyDeletesSelectedZoom() {
        let edits = TimelineEditDriver()
        let original = fixture()
        edits.applySnapshot(original)
        edits.select(.zoom, id: original.zoomRegions[0].id)
        edits.deleteSelection(duration: 10)
        var expected = original
        expected.zoomRegions.removeFirst()
        XCTAssertEqual(edits.snapshot, expected)
        XCTAssertFalse(edits.hasSelection)
    }
}
