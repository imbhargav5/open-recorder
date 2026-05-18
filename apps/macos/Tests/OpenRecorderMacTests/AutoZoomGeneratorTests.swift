import XCTest
@testable import OpenRecorderMac

final class AutoZoomGeneratorTests: XCTestCase {
    func testNoClicksGenerateNoZooms() {
        let payload = CursorTelemetryPayload(width: 1000, height: 700, samples: [], clicks: [])

        let zooms = AutoZoomGenerator.generate(from: payload, duration: 10)

        XCTAssertTrue(zooms.isEmpty)
    }

    func testSingleClickGeneratesAutoZoomAtClickFocus() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 500,
            samples: [],
            clicks: [CursorTelemetryClick(x: 250, y: 300, timestamp: 1_000, button: "left", clickCount: 1)]
        )

        let zooms = AutoZoomGenerator.generate(from: payload, duration: 5)

        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].mode, .auto)
        XCTAssertEqual(zooms[0].span.start, 0.75, accuracy: 0.001)
        XCTAssertEqual(zooms[0].span.end, 2.35, accuracy: 0.001)
        XCTAssertEqual(zooms[0].depth, 1.75, accuracy: 0.001)
        XCTAssertEqual(zooms[0].focusX, 0.25, accuracy: 0.001)
        XCTAssertEqual(zooms[0].focusY, 0.60, accuracy: 0.001)
        XCTAssertEqual(zooms[0].sourceClickTimestamp, 1_000)
    }

    func testRapidNearbyClicksMergeIntoOneZoomFocusedOnLastClick() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [],
            clicks: [
                CursorTelemetryClick(x: 100, y: 200, timestamp: 1_000, button: "left", clickCount: 1),
                CursorTelemetryClick(x: 600, y: 700, timestamp: 1_800, button: "left", clickCount: 1)
            ]
        )

        let zooms = AutoZoomGenerator.generate(from: payload, duration: 6)

        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].span.start, 0.75, accuracy: 0.001)
        XCTAssertEqual(zooms[0].span.end, 3.15, accuracy: 0.001)
        XCTAssertEqual(zooms[0].focusX, 0.60, accuracy: 0.001)
        XCTAssertEqual(zooms[0].focusY, 0.70, accuracy: 0.001)
    }

    func testSeparatedClicksKeepMinimumGap() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [],
            clicks: [
                CursorTelemetryClick(x: 100, y: 200, timestamp: 1_000, button: "left", clickCount: 1),
                CursorTelemetryClick(x: 800, y: 900, timestamp: 2_400, button: "left", clickCount: 1)
            ]
        )

        let zooms = AutoZoomGenerator.generate(from: payload, duration: 6)

        XCTAssertEqual(zooms.count, 2)
        XCTAssertEqual(zooms[0].span.end, 2.35, accuracy: 0.001)
        XCTAssertEqual(zooms[1].span.start, 2.55, accuracy: 0.001)
    }

    func testEdgeClicksClampFocusAndDuration() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [],
            clicks: [
                CursorTelemetryClick(x: 0, y: 1_000, timestamp: 50, button: "left", clickCount: 1),
                CursorTelemetryClick(x: 1_000, y: 0, timestamp: 4_900, button: "left", clickCount: 1)
            ]
        )

        let zooms = AutoZoomGenerator.generate(from: payload, duration: 5)

        XCTAssertEqual(zooms.count, 2)
        XCTAssertEqual(zooms[0].span.start, 0, accuracy: 0.001)
        XCTAssertEqual(zooms[0].focusX, 0.08, accuracy: 0.001)
        XCTAssertEqual(zooms[0].focusY, 0.92, accuracy: 0.001)
        XCTAssertEqual(zooms[1].span.end, 5, accuracy: 0.001)
        XCTAssertEqual(zooms[1].focusX, 0.92, accuracy: 0.001)
        XCTAssertEqual(zooms[1].focusY, 0.08, accuracy: 0.001)
    }

    func testOldZoomJSONDefaultsToManualMode() throws {
        let json = """
        {
          "span": { "start": 1, "end": 2 },
          "depth": 2.2,
          "focusX": 0.4,
          "focusY": 0.5
        }
        """
        let zoom = try JSONDecoder().decode(TimelineZoomRegion.self, from: Data(json.utf8))

        XCTAssertEqual(zoom.mode, .manual)
        XCTAssertNil(zoom.sourceClickTimestamp)
    }

    func testLegacyStringClickTelemetryDecodesAsEmptyClicks() throws {
        let json = """
        {
          "width": 100,
          "height": 100,
          "samples": [],
          "clicks": ["legacy"]
        }
        """

        let payload = try JSONDecoder().decode(CursorTelemetryPayload.self, from: Data(json.utf8))

        XCTAssertTrue(payload.clicks.isEmpty)
    }

    @MainActor
    func testRegenerateAutoZoomsPreservesManualZooms() {
        let edits = TimelineEditDriver()
        let manual = TimelineZoomRegion(span: TimelineSpan(start: 0, end: 1), mode: .manual)
        let oldAuto = TimelineZoomRegion(span: TimelineSpan(start: 1, end: 2), mode: .auto, sourceClickTimestamp: 1_000)
        let newAuto = TimelineZoomRegion(span: TimelineSpan(start: 3, end: 4), mode: .auto, sourceClickTimestamp: 3_000)
        edits.applySnapshot(TimelineEditSnapshot(zoomRegions: [manual, oldAuto]))

        edits.replaceAutoZooms(with: [newAuto])

        XCTAssertEqual(edits.zoomRegions.count, 2)
        XCTAssertTrue(edits.zoomRegions.contains { $0.id == manual.id && $0.mode == .manual })
        XCTAssertTrue(edits.zoomRegions.contains { $0.sourceClickTimestamp == 3_000 && $0.mode == .auto })
        XCTAssertFalse(edits.zoomRegions.contains { $0.sourceClickTimestamp == 1_000 })
    }

    func testTimelineRenderDataShowsAutoBadgeOnlyForAutoZooms() {
        let auto = TimelineRegionRenderData.zoom(TimelineZoomRegion(span: TimelineSpan(start: 0, end: 1), mode: .auto))
        let manual = TimelineRegionRenderData.zoom(TimelineZoomRegion(span: TimelineSpan(start: 0, end: 1), mode: .manual))

        XCTAssertTrue(auto.showsAutoBadge)
        XCTAssertFalse(manual.showsAutoBadge)
    }

    func testZoomAnimationRampsInAndOut() {
        let zoom = TimelineZoomRegion(span: TimelineSpan(start: 1, end: 3), depth: 2)

        XCTAssertEqual(TimelineZoomAnimator.animatedDepth(for: zoom, at: 0.5), 1, accuracy: 0.001)
        XCTAssertGreaterThan(TimelineZoomAnimator.animatedDepth(for: zoom, at: 1.1), 1)
        XCTAssertEqual(TimelineZoomAnimator.animatedDepth(for: zoom, at: 2), 2, accuracy: 0.001)
        XCTAssertLessThan(TimelineZoomAnimator.animatedDepth(for: zoom, at: 2.95), 2)
    }
}
