import AVFoundation
import XCTest
@testable import OpenRecorderMac

final class VideoExportRendererTests: XCTestCase {
    func testMediaInsertionPreservesDelayedSourceTrackStart() {
        let segment = TimelineExportEditPlan.Segment(
            sourceStart: 0,
            sourceEnd: 10,
            outputStart: 0,
            outputEnd: 10,
            speed: 1
        )
        let availableRange = CMTimeRange(
            start: CMTime(seconds: 0.35, preferredTimescale: 600),
            end: CMTime(seconds: 10, preferredTimescale: 600)
        )

        let insertion = VideoExportRenderer.mediaInsertion(
            for: segment,
            availableSourceRange: availableRange
        )

        XCTAssertEqual(insertion?.sourceRange.start.seconds ?? -1, 0.35, accuracy: 0.001)
        XCTAssertEqual(insertion?.sourceRange.end.seconds ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(insertion?.outputStart.seconds ?? -1, 0.35, accuracy: 0.001)
        XCTAssertEqual(insertion?.scaledDuration.seconds ?? -1, 9.65, accuracy: 0.001)
    }

    func testMediaInsertionAppliesFacecamOffsetAndSpeed() {
        let segment = TimelineExportEditPlan.Segment(
            sourceStart: 4,
            sourceEnd: 8,
            outputStart: 2,
            outputEnd: 4,
            speed: 2
        )
        let availableRange = CMTimeRange(
            start: .zero,
            end: CMTime(seconds: 6, preferredTimescale: 600)
        )

        let insertion = VideoExportRenderer.mediaInsertion(
            for: segment,
            availableSourceRange: availableRange,
            sourceOffsetSeconds: 1.5
        )

        XCTAssertEqual(insertion?.sourceRange.start.seconds ?? -1, 2.5, accuracy: 0.001)
        XCTAssertEqual(insertion?.sourceRange.end.seconds ?? -1, 6, accuracy: 0.001)
        XCTAssertEqual(insertion?.outputStart.seconds ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(insertion?.scaledDuration.seconds ?? -1, 1.75, accuracy: 0.001)
    }

    func testMediaInsertionOffsetsOutputWhenOffsetTrackStartsInsideSegment() {
        let segment = TimelineExportEditPlan.Segment(
            sourceStart: 0,
            sourceEnd: 5,
            outputStart: 3,
            outputEnd: 8,
            speed: 1
        )
        let availableRange = CMTimeRange(
            start: CMTime(seconds: 2, preferredTimescale: 600),
            end: CMTime(seconds: 9, preferredTimescale: 600)
        )

        let insertion = VideoExportRenderer.mediaInsertion(
            for: segment,
            availableSourceRange: availableRange
        )

        XCTAssertEqual(insertion?.sourceRange.start.seconds ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(insertion?.sourceRange.end.seconds ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(insertion?.outputStart.seconds ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(insertion?.scaledDuration.seconds ?? -1, 3, accuracy: 0.001)
    }

    func testMediaInsertionReturnsNilWhenTrackDoesNotOverlapSegment() {
        let segment = TimelineExportEditPlan.Segment(
            sourceStart: 0,
            sourceEnd: 2,
            outputStart: 0,
            outputEnd: 2,
            speed: 1
        )
        let availableRange = CMTimeRange(
            start: CMTime(seconds: 3, preferredTimescale: 600),
            end: CMTime(seconds: 5, preferredTimescale: 600)
        )

        let insertion = VideoExportRenderer.mediaInsertion(
            for: segment,
            availableSourceRange: availableRange
        )

        XCTAssertNil(insertion)
    }

    func testExportSourceDurationUsesVideoTrackEndWhenContainerRunsLonger() {
        let duration = VideoExportRenderer.exportSourceDuration(
            assetDuration: CMTime(seconds: 12, preferredTimescale: 600),
            videoTrackTimeRange: CMTimeRange(
                start: .zero,
                end: CMTime(seconds: 10, preferredTimescale: 600)
            )
        )

        XCTAssertEqual(duration, 10, accuracy: 0.001)
    }

    func testExportSourceDurationFallsBackToAssetDurationWhenTrackDurationIsInvalid() {
        let duration = VideoExportRenderer.exportSourceDuration(
            assetDuration: CMTime(seconds: 8, preferredTimescale: 600),
            videoTrackTimeRange: CMTimeRange(start: .invalid, duration: .invalid)
        )

        XCTAssertEqual(duration, 8, accuracy: 0.001)
    }
}
