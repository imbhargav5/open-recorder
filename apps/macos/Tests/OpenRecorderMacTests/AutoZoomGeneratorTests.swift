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
        XCTAssertEqual(zooms[0].animationPreset, .balanced)
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
        XCTAssertEqual(zoom.animationPreset, .balanced)
        XCTAssertNil(zoom.sourceClickTimestamp)
    }

    func testStoredZoomAnimationPresetTrimsWhitespace() {
        XCTAssertEqual(TimelineZoomAnimationPreset.storedValue(" snappy\n"), .snappy)
        XCTAssertEqual(TimelineZoomAnimationPreset.storedValue("CINEMATIC"), .cinematic)
        XCTAssertEqual(TimelineZoomAnimationPreset.storedValue("\tGuIdEd "), .guided)
    }

    func testStoredZoomAnimationPresetDefaultsInvalidValuesToBalanced() {
        XCTAssertEqual(TimelineZoomAnimationPreset.storedValue(nil), .balanced)
        XCTAssertEqual(TimelineZoomAnimationPreset.storedValue(""), .balanced)
        XCTAssertEqual(TimelineZoomAnimationPreset.storedValue("unknown"), .balanced)
    }

    func testZoomEasingClampsOutOfRangeInputs() {
        XCTAssertEqual(TimelineZoomEasing.smoothstep.value(-0.25), 0, accuracy: 0.001)
        XCTAssertEqual(TimelineZoomEasing.easeOut.value(1.25), 1, accuracy: 0.001)
        XCTAssertEqual(TimelineZoomEasing.easeInOut.value(0.5), 0.5, accuracy: 0.001)
    }

    func testPresetChangesGeneratedTimingAndDepth() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [
                CursorTelemetrySample(x: 250, y: 300, timestamp: 1_150, cursorType: "arrow"),
                CursorTelemetrySample(x: 252, y: 302, timestamp: 1_350, cursorType: "arrow")
            ],
            clicks: [CursorTelemetryClick(x: 250, y: 300, timestamp: 1_000, button: "left", clickCount: 2)]
        )

        let subtle = AutoZoomGenerator.generate(from: payload, duration: 5, preset: .subtle)
        let snappy = AutoZoomGenerator.generate(from: payload, duration: 5, preset: .snappy)

        XCTAssertEqual(subtle.count, 1)
        XCTAssertEqual(snappy.count, 1)
        XCTAssertEqual(subtle[0].animationPreset, .subtle)
        XCTAssertEqual(snappy[0].animationPreset, .snappy)
        XCTAssertEqual(subtle[0].depth, 1.35, accuracy: 0.001)
        XCTAssertEqual(snappy[0].depth, 1.85, accuracy: 0.001)
        XCTAssertNotEqual(subtle[0].span, snappy[0].span)
    }

    func testPresetControlsRapidClickMerging() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [],
            clicks: [
                CursorTelemetryClick(x: 100, y: 200, timestamp: 1_000, button: "left", clickCount: 1),
                CursorTelemetryClick(x: 700, y: 800, timestamp: 2_200, button: "left", clickCount: 1)
            ]
        )

        let snappy = AutoZoomGenerator.generate(from: payload, duration: 6, preset: .snappy)
        let cinematic = AutoZoomGenerator.generate(from: payload, duration: 6, preset: .cinematic)

        XCTAssertEqual(snappy.count, 2)
        XCTAssertEqual(cinematic.count, 1)
        XCTAssertEqual(cinematic[0].focusX, 0.70, accuracy: 0.001)
    }

    func testSubtleSkipsLowConfidenceClickThatSnappyAccepts() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [],
            clicks: [CursorTelemetryClick(x: 250, y: 300, timestamp: 1_000, button: "left", clickCount: 1)]
        )

        XCTAssertTrue(AutoZoomGenerator.generate(from: payload, duration: 5, preset: .subtle).isEmpty)
        XCTAssertEqual(AutoZoomGenerator.generate(from: payload, duration: 5, preset: .snappy).count, 1)
    }

    func testGuidedPresetCreatesSustainedDropdownRegion() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [
                CursorTelemetrySample(x: 500, y: 560, timestamp: 1_250, cursorType: "arrow"),
                CursorTelemetrySample(x: 502, y: 650, timestamp: 1_700, cursorType: "arrow"),
                CursorTelemetrySample(x: 504, y: 760, timestamp: 2_500, cursorType: "arrow")
            ],
            clicks: [CursorTelemetryClick(x: 500, y: 500, timestamp: 1_000, button: "left", clickCount: 1)]
        )

        let zooms = AutoZoomGenerator.generate(from: payload, duration: 5, preset: .guided)

        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms[0].animationPreset, .guided)
        XCTAssertGreaterThan(zooms[0].span.duration, 3.0)
    }

    func testGuidedPresetCreatesCursorOnlyDwellRegion() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [
                CursorTelemetrySample(x: 500, y: 500, timestamp: 1_000, cursorType: "arrow"),
                CursorTelemetrySample(x: 504, y: 525, timestamp: 1_150, cursorType: "arrow"),
                CursorTelemetrySample(x: 508, y: 550, timestamp: 1_300, cursorType: "arrow"),
                CursorTelemetrySample(x: 510, y: 580, timestamp: 1_450, cursorType: "arrow"),
                CursorTelemetrySample(x: 512, y: 610, timestamp: 1_600, cursorType: "arrow"),
                CursorTelemetrySample(x: 514, y: 635, timestamp: 1_750, cursorType: "arrow"),
                CursorTelemetrySample(x: 516, y: 660, timestamp: 1_900, cursorType: "arrow"),
                CursorTelemetrySample(x: 518, y: 680, timestamp: 2_050, cursorType: "arrow")
            ],
            clicks: []
        )

        let guided = AutoZoomGenerator.generate(from: payload, duration: 5, preset: .guided)
        let balanced = AutoZoomGenerator.generate(from: payload, duration: 5, preset: .balanced)

        XCTAssertEqual(guided.count, 1)
        XCTAssertEqual(guided[0].animationPreset, .guided)
        XCTAssertNil(guided[0].sourceClickTimestamp)
        XCTAssertEqual(guided[0].focusX, 0.509, accuracy: 0.001)
        XCTAssertEqual(guided[0].focusY, 0.590, accuracy: 0.001)
        XCTAssertTrue(balanced.isEmpty)
    }

    func testGuidedPresetSkipsIdleCursorOnlySamples() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: (0..<20).map { index in
                CursorTelemetrySample(x: 500, y: 500, timestamp: 1_000 + index * 100, cursorType: "arrow")
            },
            clicks: []
        )

        XCTAssertTrue(AutoZoomGenerator.generate(from: payload, duration: 5, preset: .guided).isEmpty)
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

    func testCinematicZoomRampsMoreSlowlyThanSnappy() {
        let snappy = TimelineZoomRegion(span: TimelineSpan(start: 1, end: 4), depth: 2, animationPreset: .snappy)
        let cinematic = TimelineZoomRegion(span: TimelineSpan(start: 1, end: 4), depth: 2, animationPreset: .cinematic)

        XCTAssertGreaterThan(
            TimelineZoomAnimator.animatedDepth(for: snappy, at: 1.2),
            TimelineZoomAnimator.animatedDepth(for: cinematic, at: 1.2)
        )
    }

    func testGuidedFocusHoldsFollowsAndFreezesDuringZoomOut() {
        let payload = CursorTelemetryPayload(
            width: 1000,
            height: 1000,
            samples: [
                CursorTelemetrySample(x: 550, y: 500, timestamp: 1_200, cursorType: "arrow"),
                CursorTelemetrySample(x: 800, y: 500, timestamp: 2_000, cursorType: "arrow"),
                CursorTelemetrySample(x: 200, y: 500, timestamp: 3_800, cursorType: "arrow")
            ],
            clicks: []
        )
        let track = CursorTelemetryTrack(payload: payload)
        let zoom = TimelineZoomRegion(
            span: TimelineSpan(start: 1, end: 4),
            depth: 2,
            focusX: 0.5,
            focusY: 0.5,
            animationPreset: .guided
        )
        let edits = TimelineEditSnapshot(zoomRegions: [zoom])

        XCTAssertEqual(edits.activeZoomEffect(at: 1.25, cursorTrack: track)?.focusX ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(edits.activeZoomEffect(at: 2.1, cursorTrack: track)?.focusX ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(edits.activeZoomEffect(at: 3.9, cursorTrack: track)?.focusX ?? 0, 0.8, accuracy: 0.001)
    }
}
