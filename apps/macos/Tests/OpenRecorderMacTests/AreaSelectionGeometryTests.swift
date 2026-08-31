import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class AreaSelectionGeometryTests: XCTestCase {
    func testAlignsEachSelectionEdgeToTheCaptureGrid() {
        let rect = AreaSelectionGeometry.alignedSelectionRect(
            between: CGPoint(x: 300.4, y: 350.4),
            and: CGPoint(x: 100.6, y: 200.6)
        )

        XCTAssertEqual(rect, CGRect(x: 101, y: 201, width: 199, height: 149))
    }

    func testRoundsOpposingSelectionEdgesBeforeDerivingSize() {
        let area = AreaSelectionGeometry.captureArea(
            for: CGRect(x: 100.6, y: 200.6, width: 199.8, height: 149.8),
            on: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            displayID: 7
        )

        XCTAssertEqual(
            area,
            CaptureArea(x: 101, y: 767, width: 199, height: 149, displayID: 7)
        )
        XCTAssertEqual(area.x + area.width, 300)
        XCTAssertEqual(area.y + area.height, 916)
    }

    func testPreservesIntegralSelectionEdges() {
        let area = AreaSelectionGeometry.captureArea(
            for: CGRect(x: 120, y: 230, width: 640, height: 360),
            on: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            displayID: 11
        )

        XCTAssertEqual(
            area,
            CaptureArea(x: 120, y: 527, width: 640, height: 360, displayID: 11)
        )
    }

    func testMapsSelectionOnOffsetDisplay() {
        let area = AreaSelectionGeometry.captureArea(
            for: CGRect(x: 20.4, y: 30.4, width: 300.2, height: 200.2),
            on: CGRect(x: -1512, y: -85, width: 1512, height: 982),
            displayID: 19
        )

        XCTAssertEqual(
            area,
            CaptureArea(x: -1492, y: 666, width: 301, height: 201, displayID: 19)
        )
    }
}
