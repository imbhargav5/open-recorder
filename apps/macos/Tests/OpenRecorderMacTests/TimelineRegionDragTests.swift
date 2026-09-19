import XCTest
@testable import OpenRecorderMac

final class TimelineRegionDragTests: XCTestCase {
    func testBothEdgesFollowPointerWithoutCumulativeDrift() {
        let original = TimelineSpan(start: 2, end: 5)
        for operation in [TimelineRegionDrag.Operation.leading, .trailing] {
            let drag = TimelineRegionDrag(span: original, operation: operation, secondsPerPoint: 0.01)
            for pixels in [1.0, 2, 10, 30, 20, 10, 0, -20, 0] {
                let result = drag.span(at: pixels, duration: 10)
                XCTAssertEqual(result.start, operation == .leading ? 2 + pixels * 0.01 : 2, accuracy: 0.000001)
                XCTAssertEqual(result.end, operation == .trailing ? 5 + pixels * 0.01 : 5, accuracy: 0.000001)
            }
        }
    }

    func testResizingClampsDraggedEdgeWithoutMovingOppositeEdge() {
        let span = TimelineSpan(start: 2, end: 5)
        let leading = TimelineRegionDrag(span: span, operation: .leading, secondsPerPoint: 0.1)
        let trailing = TimelineRegionDrag(span: span, operation: .trailing, secondsPerPoint: 0.1)
        XCTAssertEqual(leading.span(at: -1000, duration: 10), .init(start: 0, end: 5))
        XCTAssertEqual(leading.span(at: 1000, duration: 10), .init(start: 4.9, end: 5))
        XCTAssertEqual(trailing.span(at: 1000, duration: 10), .init(start: 2, end: 10))
        XCTAssertEqual(trailing.span(at: -1000, duration: 10), .init(start: 2, end: 2.1))
        XCTAssertEqual(leading.span(at: 0, duration: 10), span)
        XCTAssertEqual(trailing.span(at: 0, duration: 10), span)
    }

    @MainActor
    func testZoomResizePreservesTransitionAndUndoRestoresWholeGesture() {
        let driver = TimelineEditDriver()
        driver.add(.zoom, at: 2, duration: 10)
        let original = driver.zoomRegions[0]
        let drag = TimelineRegionDrag(span: original.span, operation: .trailing, secondsPerPoint: 0.01)
        driver.beginUndoTransaction()
        for pixels in [10.0, 20, 50, 100, 80] {
            driver.updateSpan(kind: .zoom, id: original.id, span: drag.span(at: pixels, duration: 10), duration: 10)
        }
        driver.endUndoTransaction()
        XCTAssertEqual(driver.zoomRegions[0].span, drag.span(at: 80, duration: 10))
        XCTAssertEqual(driver.zoomRegions[0].transition, original.transition)
        driver.undo()
        XCTAssertEqual(driver.zoomRegions[0], original)
        driver.redo()
        XCTAssertEqual(driver.zoomRegions[0].span, drag.span(at: 80, duration: 10))
    }

    func testMovingKeepsLengthAndInvalidInputKeepsOriginalSpan() {
        let drag = TimelineRegionDrag(span: .init(start: 2, end: 5), operation: .move, secondsPerPoint: 0.01)
        XCTAssertEqual(drag.span(at: 100, duration: 10), .init(start: 3, end: 6))
        XCTAssertEqual(drag.span(at: -1000, duration: 10), .init(start: 0, end: 3))
        XCTAssertEqual(drag.span(at: 1000, duration: 10), .init(start: 7, end: 10))
        XCTAssertEqual(drag.span(at: .nan, duration: 10), drag.span)
    }
}
