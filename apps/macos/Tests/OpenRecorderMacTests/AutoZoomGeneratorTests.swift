import XCTest
@testable import OpenRecorderMac

final class AutoZoomGeneratorTests: XCTestCase {
    func testNoClicksGenerateNoZooms() {
        let payload = CursorTelemetryPayload(width: 1000, height: 700, samples: [], clicks: [])

        let zooms = AutoZoomGenerator.generate(from: payload, duration: 10)

        XCTAssertTrue(zooms.isEmpty)
    }

    func testSingleClickSettlesByActionAndReturnsToFullView() throws {
        let zoom = try XCTUnwrap(AutoZoomGenerator.generate(from: payload(clicks: [click(250, 600, 1000)]), duration: 5).first)
        XCTAssertEqual(zoom.mode, .auto)
        XCTAssertEqual(zoom.span.start, 0.4, accuracy: 0.001)
        XCTAssertEqual(zoom.span.end, 3.1, accuracy: 0.001)
        XCTAssertEqual(zoom.depth, 2)
        XCTAssertEqual(zoom.cameraPath?.effect(at: 1)?.depth, 2)
        XCTAssertEqual(zoom.cameraPath?.effect(at: 0.4)?.depth, 1)
        XCTAssertEqual(zoom.cameraPath?.effect(at: 3.1)?.depth, 1)
    }

    func testNearbyActionsShareOneSustainedZoom() throws {
        let zooms = AutoZoomGenerator.generate(from: payload(clicks: [click(400, 500, 1000), click(500, 500, 1800)]), duration: 6)
        XCTAssertEqual(zooms.count, 1)
        let zoom = try XCTUnwrap(zooms.first)
        XCTAssertEqual(zoom.span.end, 3.9, accuracy: 0.001)
        XCTAssertEqual(zoom.cameraPath?.effect(at: 1.5)?.depth, 2)
    }

    func testDistantRapidActionsNeverDelayZoomPastTrigger() {
        let zooms = AutoZoomGenerator.generate(from: payload(clicks: [click(100, 100, 1000), click(900, 900, 1800)]), duration: 6)
        XCTAssertEqual(zooms.count, 1) // Overlapping unrelated candidates: retain the complete stronger/earlier action.
        for zoom in zooms {
            XCTAssertLessThanOrEqual(zoom.span.start, Double(zoom.sourceClickTimestamp!) / 1000)
        }
    }

    func testSeparatedActionsHaveAnOverviewBetweenThem() {
        let zooms = AutoZoomGenerator.generate(from: payload(clicks: [click(100, 100, 1000), click(900, 900, 5000)]), duration: 8)
        XCTAssertEqual(zooms.count, 2)
        XCTAssertLessThan(zooms[0].span.end, zooms[1].span.start)
    }

    func testBoundaryActionsAreClampedWithoutInvalidKeyframes() {
        let zooms = AutoZoomGenerator.generate(from: payload(clicks: [click(0, 1000, 50), click(1000, 0, 4900)]), duration: 5)
        for zoom in zooms {
            XCTAssertGreaterThanOrEqual(zoom.span.start, 0)
            XCTAssertLessThanOrEqual(zoom.span.end, 5)
            let frames = zoom.cameraPath!.keyframes
            for pair in zip(frames, frames.dropFirst()) { XCTAssertLessThan(pair.0.time, pair.1.time) }
        }
    }

    func testPanRequiresSustainedBoundaryEvidence() throws {
        let clicks = [click(300, 500, 1000), click(500, 500, 2000)]
        func frames(_ positions: [(Int, Int)]) throws -> [AutoZoomCameraKeyframe] {
            let samples = positions.map {
                CursorTelemetrySample(x: $0.0, y: 500, timestamp: $0.1, cursorType: "arrow")
            }
            return try XCTUnwrap(AutoZoomGenerator.generate(from: payload(clicks: clicks, samples: samples),
                duration: 6).first?.cameraPath?.keyframes)
        }
        let sustained = try frames([(500, 2000), (500, 2100), (500, 2200), (500, 2300)])
        XCTAssertTrue(sustained.contains { $0.depth > 1 && $0.centerX == 0.5 })
        for samples in [[(500, 2000), (300, 2100), (300, 2200)],
                        [(500, 2000)], [(500, 2000), (500, 2300)]] {
            let path = try frames(samples)
            XCTAssertTrue(path.filter { $0.depth > 1 }.allSatisfy { $0.centerX == 0.3 })
        }
        // Explicit clicks remain usable when a recording contains no pointer samples.
        XCTAssertTrue(try frames([]).contains { $0.depth > 1 && $0.centerX == 0.5 })
    }

    func testConflictResolutionUsesWholeInteractionEvidence() throws {
        let isolated = CursorTelemetryClick(x: 100, y: 100, timestamp: 1000, button: "left", clickCount: 2)
        let later = [click(800, 800, 1800), click(810, 800, 2100), click(820, 800, 2400)]
        let zooms = AutoZoomGenerator.generate(from: payload(clicks: [isolated] + later), duration: 7)
        XCTAssertEqual(zooms.count, 1)
        XCTAssertEqual(zooms.first?.sourceClickTimestamp, 1800)
        XCTAssertLessThan(try XCTUnwrap(zooms.first).span.start, 1.8)
    }

    func testSuppressedPanWidensToKeepExplicitTargetVisible() throws {
        let samples = [(570, 2000), (300, 2100), (300, 2200)].map {
            CursorTelemetrySample(x: $0.0, y: 500, timestamp: $0.1, cursorType: "arrow")
        }
        let zoom = try XCTUnwrap(AutoZoomGenerator.generate(from: payload(
            clicks: [click(300, 500, 1000), click(570, 500, 2000)], samples: samples), duration: 6).first)
        let effect = try XCTUnwrap(zoom.cameraPath?.effect(at: 2))
        XCTAssertEqual(effect.focusX, 0.3)
        XCTAssertLessThan(effect.depth, 2)
        let transform = TimelineZoomCanvasTransform.transform(for: effect, in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertLessThanOrEqual(CGPoint(x: 670, y: 500).applying(transform).x, 1000 + 0.00001)
        XCTAssertEqual(zoom.cameraPath?.keyframes.first?.depth, 1)
        XCTAssertEqual(zoom.cameraPath?.keyframes.last?.depth, 1)
    }

    func testUnfinishedPanKeepsActionContextVisibleAtMaximumZoom() throws {
        let telemetry = CursorTelemetryPayload(width: 1920, height: 1080, samples: [],
            clicks: [click(960, 300, 1000), click(960, 700, 2000)])
        let zoom = try XCTUnwrap(AutoZoomGenerator.generate(from: telemetry, duration: 6, maximumZoom: 3).first)
        let effect = try XCTUnwrap(zoom.cameraPath?.effect(at: 2))
        let transform = TimelineZoomCanvasTransform.transform(for: effect, in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertLessThanOrEqual(CGPoint(x: 960, y: 808).applying(transform).y, 1080 + 0.00001)
    }

    func testTelemetryGapCannotProveDeliberateArrival() {
        var samples = [CursorTelemetrySample(x: 100, y: 500, timestamp: 0, cursorType: "arrow")]
        samples += stride(from: 10000, through: 12000, by: 100).map {
            CursorTelemetrySample(x: 500, y: 500, timestamp: $0, cursorType: "arrow")
        }
        XCTAssertTrue(AutoZoomGenerator.generate(from: payload(clicks: [], samples: samples), duration: 15).isEmpty)
    }

    func testCameraClipGapDoesNotApplyFallbackOverlay() throws {
        let settings = defaultFacecamSettings(enabled: true)
        let frame = FacecamOverlayLayout.frame(in: CGSize(width: 1000, height: 1000), settings: settings)
        let telemetry = payload(clicks: [click(Int(frame.midX), Int(frame.midY), 3000)])
        let fallback = try XCTUnwrap(AutoZoomGenerator.generate(from: telemetry, duration: 6,
            cameraSettings: settings).first)
        let gap = try XCTUnwrap(AutoZoomGenerator.generate(from: telemetry, duration: 6,
            cameraSettings: settings, cameraClips: [.init(span: .init(start: 0, end: 1), settings: settings)]).first)
        XCTAssertEqual(fallback.depth, 1.35, accuracy: 0.001)
        XCTAssertEqual(gap.depth, 2, accuracy: 0.001)
    }

    private func click(_ x: Int, _ y: Int, _ time: Int) -> CursorTelemetryClick {
        .init(x: x, y: y, timestamp: time, button: "left", clickCount: 1)
    }

    private func payload(clicks: [CursorTelemetryClick], samples: [CursorTelemetrySample] = []) -> CursorTelemetryPayload {
        .init(width: 1000, height: 1000, samples: samples, clicks: clicks)
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

    func testZoomAnimationPresetDisplayTitles() {
        XCTAssertEqual(TimelineZoomAnimationPreset.allCases.map(\.title), [
            "Balanced",
            "Subtle",
            "Snappy",
            "Cinematic",
            "Guided"
        ])
        XCTAssertEqual(TimelineZoomAnimationPreset.allCases.map(\.shortTitle), [
            "Bal",
            "Sub",
            "Snap",
            "Cine",
            "Guide"
        ])
    }

    func testZoomEasingClampsOutOfRangeInputs() {
        XCTAssertEqual(TimelineZoomEasing.smoothstep.value(-0.25), 0, accuracy: 0.001)
        XCTAssertEqual(TimelineZoomEasing.easeOut.value(1.25), 1, accuracy: 0.001)
        XCTAssertEqual(TimelineZoomEasing.easeInOut.value(0.5), 0.5, accuracy: 0.001)
    }

    func testAnimationStyleDoesNotChooseMagnification() throws {
        let data = payload(clicks: [click(250, 300, 1000)])
        let subtle = try XCTUnwrap(AutoZoomGenerator.generate(from: data, duration: 5, preset: .subtle).first)
        let snappy = try XCTUnwrap(AutoZoomGenerator.generate(from: data, duration: 5, preset: .snappy).first)
        XCTAssertEqual(subtle.depth, snappy.depth)
        XCTAssertNotEqual(subtle.span, snappy.span)
        XCTAssertEqual(subtle.animationPreset, .subtle)
    }

    func testArrivalDwellIsDetectedOnceAndDoesNotFollowIdleTail() throws {
        let samples = [CursorTelemetrySample(x: 100, y: 100, timestamp: 900, cursorType: "arrow")] + (0..<60).map {
            CursorTelemetrySample(x: 500, y: 500, timestamp: 1000 + $0 * 100, cursorType: "arrow")
        }
        for preset in TimelineZoomAnimationPreset.allCases {
            let zooms = AutoZoomGenerator.generate(from: payload(clicks: [], samples: samples), duration: 10, preset: preset)
            XCTAssertEqual(zooms.count, 1)
            XCTAssertLessThan(try XCTUnwrap(zooms.first).span.end, 5)
        }
    }

    func testBroadActivityWidensZoomAndMaximumIsRespected() throws {
        let data = payload(clicks: [click(200, 500, 1000)], samples: [
            .init(x: 700, y: 500, timestamp: 1300, cursorType: "arrow")
        ])
        let zoom = try XCTUnwrap(AutoZoomGenerator.generate(from: data, duration: 6).first)
        XCTAssertEqual(zoom.depth, 1 / 0.7, accuracy: 0.001)
        XCTAssertEqual(AutoZoomGenerator.generate(from: data, duration: 6, maximumZoom: 1.25).first?.depth, 1.25)
        XCTAssertTrue(AutoZoomGenerator.generate(from: data, duration: 6, maximumZoom: 1).isEmpty)
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
