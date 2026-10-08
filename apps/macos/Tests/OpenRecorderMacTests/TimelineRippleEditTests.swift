import XCTest
@testable import OpenRecorderMac

@MainActor
final class TimelineRippleEditTests: XCTestCase {
    private func deletedMiddle() -> TimelineEditSnapshot {
        TimelineEditSnapshot(trimRegions: [TimelineTrimRegion(span: TimelineSpan(start: 3, end: 7))],
                             clipSplitTimes: [3, 7], clipSpeeds: [2: 1.5])
    }
    func testDeletedIntervalCollapsesAndSeekingChoosesIncomingClip() {
        let plan = TimelineExportEditPlan.build(duration: 10, edits: deletedMiddle())
        XCTAssertEqual(plan.outputDuration, 5)
        var viewport = TimelineViewport(duration: plan.outputDuration)
        viewport.editPlan = plan
        XCTAssertEqual(viewport.x(for: 3, width: 500), viewport.x(for: 7, width: 500))
        XCTAssertEqual(viewport.time(forX: 300, width: 500), 7)
        XCTAssertFalse(viewport.intersects(TimelineSpan(start: 3, end: 7)))
    }
    func testExtendLeftClipRestoresDeletedFootageAndPreservesSpeedAndUndo() {
        let original = deletedMiddle()
        let edits = TimelineEditDriver()
        edits.applySnapshot(original)
        edits.beginUndoTransaction()
        edits.send(.resizeRecordingClip(index: 0, edge: .trailing, time: 5, duration: 10, original: original))
        edits.send(.resizeRecordingClip(index: 0, edge: .trailing, time: 6, duration: 10, original: original))
        edits.endUndoTransaction()
        XCTAssertEqual(edits.trimRegions.map(\.span), [TimelineSpan(start: 6, end: 7)])
        XCTAssertEqual(edits.clipSplitTimes, [6, 7])
        XCTAssertEqual(edits.clipSpeeds[2], 1.5)
        edits.undo()
        XCTAssertEqual(edits.snapshot, original)
        XCTAssertFalse(edits.canUndo)
    }
    func testExtendRightClipCanRecoverEntireCut() {
        let original = deletedMiddle()
        let edits = TimelineEditDriver()
        edits.applySnapshot(original)
        edits.send(.resizeRecordingClip(index: 2, edge: .leading, time: 3, duration: 10, original: original))
        XCTAssertTrue(edits.trimRegions.isEmpty)
        XCTAssertEqual(edits.clipSplitTimes, [3])
        XCTAssertEqual(edits.clipSpeeds[1], 1.5)
    }
    func testTrimThenRestoreOuterEdge() {
        let edits = TimelineEditDriver()
        let original = TimelineEditSnapshot.empty
        edits.send(.resizeRecordingClip(index: 0, edge: .leading, time: 2, duration: 10, original: original))
        let trimmed = edits.snapshot
        XCTAssertEqual(edits.trimRegions.map(\.span), [TimelineSpan(start: 0, end: 2)])
        edits.send(.resizeRecordingClip(index: 1, edge: .leading, time: -100, duration: 10, original: trimmed))
        XCTAssertTrue(edits.trimRegions.isEmpty)
        XCTAssertTrue(edits.clipSplitTimes.isEmpty)
    }
}
