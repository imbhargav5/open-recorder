import XCTest
@testable import OpenRecorderMac

final class EditorHistoryTests: XCTestCase {
    func testCancelTransactionLeavesRedoStackAvailable() {
        var history = EditorHistory<Int>()

        history.recordChange(from: 0, to: 1)
        XCTAssertEqual(history.undo(current: 1), 0)
        XCTAssertTrue(history.canRedo)

        history.beginTransaction(current: 0)
        history.cancelTransaction()

        XCTAssertFalse(history.isInTransaction)
        XCTAssertEqual(history.redo(current: 0), 1)
    }
}
