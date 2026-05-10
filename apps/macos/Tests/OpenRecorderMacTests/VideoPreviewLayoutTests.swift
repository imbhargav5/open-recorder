import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class VideoPreviewLayoutTests: XCTestCase {
    func testStageFitsWidePaneByHeight() {
        let size = PreviewStageLayout.fittedSize(
            forAspectRatio: PreviewStageLayout.videoAspectRatio,
            in: CGSize(width: 1200, height: 360)
        )

        XCTAssertEqual(size.width, 640, accuracy: 0.001)
        XCTAssertEqual(size.height, 360, accuracy: 0.001)
    }

    func testStageFitsTallPaneByWidth() {
        let size = PreviewStageLayout.fittedSize(
            forAspectRatio: PreviewStageLayout.videoAspectRatio,
            in: CGSize(width: 520, height: 700)
        )

        XCTAssertEqual(size.width, 520, accuracy: 0.001)
        XCTAssertEqual(size.height, 292.5, accuracy: 0.001)
    }

    func testStageReturnsZeroForInvalidInput() {
        XCTAssertEqual(
            PreviewStageLayout.fittedSize(forAspectRatio: 0, in: CGSize(width: 520, height: 700)),
            .zero
        )
        XCTAssertEqual(
            PreviewStageLayout.fittedSize(forAspectRatio: PreviewStageLayout.videoAspectRatio, in: .zero),
            .zero
        )
    }
}
