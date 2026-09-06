import XCTest
@testable import OpenRecorderMac

final class ReviewRenderRegressionTests: XCTestCase {
    func testCoreAnimationSamplesDoNotPanAcrossHoldAfterCut() throws {
        var zoom = TimelineZoomRegion(span: .init(start: 0, end: 9), depth: 2)
        zoom.cameraPath = AutoZoomCameraPath(keyframes: [
            .init(time: 0, centerX: 0.25, centerY: 0.5, depth: 1),
            .init(time: 1, centerX: 0.25, centerY: 0.5, depth: 2),
            .init(time: 4, centerX: 0.25, centerY: 0.5, depth: 2),
            .init(time: 5, centerX: 0.75, centerY: 0.5, depth: 2),
            .init(time: 8, centerX: 0.75, centerY: 0.5, depth: 2),
            .init(time: 9, centerX: 0.75, centerY: 0.5, depth: 1)
        ])
        let edits = TimelineEditSnapshot(zoomRegions: [zoom],
            trimRegions: [.init(span: .init(start: 3, end: 6))])
        let plan = TimelineExportEditPlan.build(duration: 9, edits: edits)
        let times = TimelineZoomCanvasTransform.animationSampleTimes(edits: edits, editPlan: plan)
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        func transform(_ time: Double) -> CGAffineTransform {
            TimelineZoomCanvasTransform.transform(for: TimelineZoomCanvasTransform.activeEffect(
                edits: edits, editPlan: plan, outputTime: time), in: rect)
        }
        // Simulate Core Animation's linear interpolation between stored samples.
        for time in [2.5, 3.001, 3.5, 4.5] {
            let lower = try XCTUnwrap(times.last(where: { $0 <= time }))
            let upper = try XCTUnwrap(times.first(where: { $0 > time }))
            let progress = (time - lower) / (upper - lower)
            let actual = transform(lower).tx + (transform(upper).tx - transform(lower).tx) * progress
            XCTAssertEqual(actual, transform(time).tx, accuracy: 0.001)
        }
    }

    func testUnknownCameraVersionUsesLegacyEffect() {
        var zoom = TimelineZoomRegion(span: .init(start: 0, end: 5), depth: 2)
        var path = AutoZoomCameraPath(keyframes: [
            .init(time: 0, centerX: 0.25, centerY: 0.25, depth: 1),
            .init(time: 5, centerX: 0.25, centerY: 0.25, depth: 2)
        ])
        path.version = 2
        zoom.cameraPath = path
        let edits = TimelineEditSnapshot(zoomRegions: [zoom])
        XCTAssertFalse(edits.hasAdaptiveCamera)
        XCTAssertFalse(edits.activeZoomEffect(at: 2)?.usesViewportCenter ?? true)
    }
}
