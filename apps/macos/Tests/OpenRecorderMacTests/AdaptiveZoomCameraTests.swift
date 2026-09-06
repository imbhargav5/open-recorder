import XCTest
@testable import OpenRecorderMac

final class AdaptiveZoomCameraTests: XCTestCase {
    private func generated() throws -> TimelineZoomRegion {
        let clicks = [(300, 1000), (550, 2000), (750, 3000)].map {
            CursorTelemetryClick(x: $0.0, y: 500, timestamp: $0.1, button: "left", clickCount: 1)
        }
        return try XCTUnwrap(AutoZoomGenerator.generate(from: .init(width: 1000, height: 1000, samples: [], clicks: clicks), duration: 8).first)
    }

    func testPanIsContinuousAndRandomSeekingIsDeterministic() throws {
        let region = try generated()
        let path = try XCTUnwrap(region.cameraPath)
        XCTAssertGreaterThan(path.keyframes.count, 4)
        let times = stride(from: region.span.start, through: region.span.end, by: 1.0 / 120).map { $0 }
        let sequential = times.map { path.effect(at: $0)! }
        for index in times.indices.reversed() { XCTAssertEqual(path.effect(at: times[index]), sequential[index]) }
        for pair in zip(sequential, sequential.dropFirst()) {
            XCTAssertLessThan(abs(pair.0.focusX - pair.1.focusX), 0.025)
            XCTAssertLessThan(abs(pair.0.depth - pair.1.depth), 0.035)
        }
        XCTAssertEqual(path.effect(at: 1.1)?.focusX, path.effect(at: 1.5)?.focusX)
    }

    func testViewportCenterHasCorrectGeometryAndNeverExposesCanvasEdges() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 700)
        for x in [0.0, 0.2, 0.5, 0.8, 1] {
            let effect = TimelineZoomEffect(depth: 2, focusX: x, focusY: x, usesViewportCenter: true)
            let transform = TimelineZoomCanvasTransform.transform(for: effect, in: rect)
            let bounds = rect.applying(transform)
            XCTAssertLessThanOrEqual(bounds.minX, 0)
            XCTAssertLessThanOrEqual(bounds.minY, 0)
            XCTAssertGreaterThanOrEqual(bounds.maxX, rect.maxX)
            XCTAssertGreaterThanOrEqual(bounds.maxY, rect.maxY)
        }
        let centered = TimelineZoomCanvasTransform.transform(for: .init(depth: 2, focusX: 0.4, focusY: 0.6, usesViewportCenter: true), in: rect)
        let point = CGPoint(x: 400, y: 420).applying(centered)
        XCTAssertEqual(point.x, rect.midX, accuracy: 0.001)
        XCTAssertEqual(point.y, rect.midY, accuracy: 0.001)
    }

    func testCroppedPortraitGeometryPreservesContextAndFlipsExportY() {
        let canvas = CGSize(width: 500, height: 900)
        let geometry = AutoZoomGeometry.fitted(sourceSize: CGSize(width: 1000, height: 1000),
            cropRect: CGRect(x: 300, y: 0, width: 400, height: 1000),
            container: CGRect(x: 20, y: 20, width: 460, height: 860), canvasSize: canvas)
        let effect = TimelineZoomEffect(depth: 3, focusX: 0.5, focusY: 0.3, usesViewportCenter: true,
                                       contextSize: CGSize(width: 0.5, height: 0.2))
        let mapped = geometry.canvasEffect(effect)
        XCTAssertLessThan(mapped.depth, 2)
        XCTAssertEqual(mapped.focusX, 0.5, accuracy: 0.001)
        let rect = CGRect(origin: .zero, size: canvas)
        let top = TimelineZoomCanvasTransform.transform(for: mapped, in: rect)
        let bottom = TimelineZoomCanvasTransform.transform(for: mapped, in: rect, flipsY: true)
        let a = CGPoint(x: 250, y: 270).applying(top)
        let b = CGPoint(x: 250, y: 630).applying(bottom)
        XCTAssertEqual(a.x, b.x, accuracy: 0.001)
        XCTAssertEqual(a.y, 900 - b.y, accuracy: 0.001)
    }

    func testPreviewAndExportEvaluateSameSourcePathAcrossCutsAndSpeedChanges() throws {
        let zoom = try generated()
        let edits = TimelineEditSnapshot(zoomRegions: [zoom], trimRegions: [.init(span: .init(start: 2.2, end: 2.7))],
                                         clipSplitTimes: [2, 4], clipSpeeds: [1: 2])
        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)
        for time in stride(from: 0.0, to: plan.outputDuration, by: 0.037) {
            let source = try XCTUnwrap(plan.sourceTime(forOutputTime: time))
            XCTAssertEqual(edits.activeZoomEffect(at: source), TimelineZoomCanvasTransform.activeEffect(edits: edits, editPlan: plan, outputTime: time))
        }
    }

    func testPathRoundTripAndRetimingPreservesMotion() throws {
        var region = try generated()
        let original = region
        let data = try JSONEncoder().encode(region)
        XCTAssertEqual(try JSONDecoder().decode(TimelineZoomRegion.self, from: data), region)
        let newSpan = TimelineSpan(start: 10, end: 20)
        region.cameraPath?.retime(from: region.span, to: newSpan)
        for progress in [0.0, 0.1, 0.5, 0.9, 1] {
            let before = original.cameraPath?.effect(at: original.span.start + original.span.duration * progress)
            let after = region.cameraPath?.effect(at: newSpan.start + newSpan.duration * progress)
            XCTAssertEqual(before!.depth, after!.depth, accuracy: 0.00001)
            XCTAssertEqual(before!.focusX, after!.focusX, accuracy: 0.00001)
        }
    }

    func testLegacyRegionStillUsesAnchorTransform() throws {
        let json = Data(#"{"span":{"start":0,"end":5},"depth":2,"focusX":0.2,"focusY":0.4,"mode":"auto"}"#.utf8)
        let zoom = try JSONDecoder().decode(TimelineZoomRegion.self, from: json)
        XCTAssertNil(zoom.cameraPath)
        XCTAssertFalse(zoom.isUserEdited)
        let effect = TimelineEditSnapshot(zoomRegions: [zoom]).activeZoomEffect(at: 2)!
        XCTAssertFalse(effect.usesViewportCenter)
        let anchor = CGPoint(x: 200, y: 400)
        XCTAssertEqual(anchor.applying(TimelineZoomCanvasTransform.transform(for: effect, in: CGRect(x: 0, y: 0, width: 1000, height: 1000))), anchor)
    }

    func testDepthEditingCanRecoverFromOneX() throws {
        var zoom = try generated()
        zoom.setEditedDepth(1)
        zoom.setEditedDepth(2.5)
        XCTAssertEqual(zoom.cameraPath?.effect(at: 1.2)?.depth, 2.5)
        XCTAssertTrue(zoom.isUserEdited)
    }

    @MainActor
    func testRegenerationPreservesEveryKindOfEditedZoomAndUndo() throws {
        for event in ["depth", "focus", "time", "style"] {
            let zoom = try generated()
            let driver = TimelineEditDriver()
            driver.applySnapshot(.init(zoomRegions: [zoom]))
            switch event {
            case "depth": driver.updateZoomDepth(id: zoom.id, depth: 1.5)
            case "focus": driver.updateZoomFocus(id: zoom.id, focusX: 0.6)
            case "time": driver.updateSpan(kind: .zoom, id: zoom.id, span: .init(start: 0.1, end: 5), duration: 8)
            default: driver.updateZoomAnimationPreset(id: zoom.id, preset: .cinematic)
            }
            let edited = driver.snapshot.zoomRegions[0]
            XCTAssertTrue(edited.isUserEdited)
            var extra = zoom
            extra.id = UUID()
            extra.cameraPath?.retime(from: extra.span, to: .init(start: 6, end: 8))
            extra.span = .init(start: 6, end: 8)
            driver.replaceAutoZooms(with: [zoom, extra])
            XCTAssertEqual(driver.snapshot.zoomRegions, [edited, extra])
            driver.undo()
            XCTAssertEqual(driver.snapshot.zoomRegions, [edited])
            driver.redo()
            XCTAssertEqual(driver.snapshot.zoomRegions, [edited, extra])
        }
    }

    func testLongTelemetryAnalysisScales() {
        var timings: [Double] = []
        for minutes in [1, 10, 60] {
            let count = minutes * 60 * 60
            let samples = (0..<count).map { CursorTelemetrySample(x: 400 + $0 % 10, y: 500, timestamp: $0 * 1000 / 60, cursorType: "arrow") }
            let clicks = stride(from: 1000, to: minutes * 60 * 1000, by: 5000).map {
                CursorTelemetryClick(x: 400, y: 500, timestamp: $0, button: "left", clickCount: 1)
            }
            let start = Date()
            let result = AutoZoomGenerator.generate(from: .init(width: 1000, height: 1000, samples: samples, clicks: clicks), duration: Double(minutes * 60))
            let elapsed = Date().timeIntervalSince(start)
            timings.append(elapsed)
            XCTAssertFalse(result.isEmpty)
            print("AUTO_ZOOM_BENCH minutes=\(minutes) samples=\(count) seconds=\(elapsed)")
        }
        // Generous bound detects accidental quadratic growth without making this a hardware benchmark gate.
        XCTAssertLessThan(timings[2], max(2, timings[1] * 12))
    }
}

private actor ZoomGenerationGate {
    private var continuation: CheckedContinuation<[TimelineZoomRegion], Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func generate() async -> [TimelineZoomRegion] {
        await withCheckedContinuation {
            continuation = $0
            hasStarted = true
            startContinuation?.resume()
            startContinuation = nil
        }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func finish(with regions: [TimelineZoomRegion]) {
        continuation?.resume(returning: regions)
        continuation = nil
    }
}

extension AdaptiveZoomCameraTests {
    @MainActor
    func testPendingGenerationCannotOverwriteEditsOrAnotherProject() async throws {
        for loadAnotherProject in [false, true] {
            let gate = ZoomGenerationGate()
            let driver = TimelineEditDriver(generationOperation: { _ in await gate.generate() })
            driver.regenerateAutoZooms(from: URL(fileURLWithPath: "/unused-test-source.mov"), duration: 10, preset: .balanced)
            await gate.waitUntilStarted()
            XCTAssertTrue(driver.isGeneratingAutoZooms)
            if loadAnotherProject { driver.applySnapshot(.empty) }
            else { driver.add(.zoom, at: 7, duration: 10) }
            let expected = driver.snapshot
            await gate.finish(with: [try generated()])
            // Yield to the completion callback without making the race dependent on telemetry size.
            for _ in 0..<20 { try await Task.sleep(for: .milliseconds(1)) }
            XCTAssertEqual(driver.snapshot, expected)
            XCTAssertFalse(driver.isGeneratingAutoZooms)
        }
    }

    @MainActor
    func testMaximumZoomPreferencePersistsAndClamps() throws {
        let name = "AdaptiveZoomTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RecordingPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.load().autoZoomMaximumDepth, 2)
        store.setAutoZoomMaximumDepth(2.35)
        XCTAssertEqual(store.load().autoZoomMaximumDepth, 2.35)
        store.setAutoZoomMaximumDepth(8)
        XCTAssertEqual(store.load().autoZoomMaximumDepth, 3)
    }

    func testInvalidPathFallsBackToLegacyRatherThanBreakingProjectLoad() throws {
        let json = Data(#"{"span":{"start":0,"end":5},"depth":2,"cameraPath":{"version":1,"keyframes":[{"time":3,"centerX":0.5,"centerY":0.5,"depth":2},{"time":1,"centerX":0.5,"centerY":0.5,"depth":2}]}}"#.utf8)
        let zoom = try JSONDecoder().decode(TimelineZoomRegion.self, from: json)
        XCTAssertNil(zoom.cameraPath)
        XCTAssertNotNil(TimelineEditSnapshot(zoomRegions: [zoom]).activeZoomEffect(at: 2))
    }
}

extension AdaptiveZoomCameraTests {
    func testLongExportsKeepFullMotionCadenceWithoutSamplingIdleHours() throws {
        var zoom = try generated()
        let lateSpan = TimelineSpan(start: 3500, end: 3505)
        zoom.cameraPath?.retime(from: zoom.span, to: lateSpan)
        zoom.span = lateSpan
        let edits = TimelineEditSnapshot(zoomRegions: [zoom])
        let plan = TimelineExportEditPlan.build(duration: 3600, edits: edits)
        let times = TimelineZoomCanvasTransform.animationSampleTimes(edits: edits, editPlan: plan)
        XCTAssertEqual(times.first, 0)
        XCTAssertEqual(times.last, 3600)
        XCTAssertLessThan(times.count, 400)
        let ramp = times.filter { $0 >= 3500 && $0 < 3500.5 }
        XCTAssertGreaterThan(ramp.count, 20)
        for (a, b) in zip(ramp, ramp.dropFirst()) { XCTAssertLessThanOrEqual(b - a, 1 / 60.0 + 0.0001) }
    }
}

extension AdaptiveZoomCameraTests {
    func testExplicitDepthBypassesAutomaticContextLimit() throws {
        var zoom = try generated()
        zoom.setEditedDepth(4)
        let geometry = AutoZoomGeometry(sourceSize: CGSize(width: 1000, height: 1000),
            cropRect: CGRect(x: 200, y: 0, width: 500, height: 1000),
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 1000), canvasSize: CGSize(width: 500, height: 1000))
        let effect = try XCTUnwrap(zoom.cameraPath?.effect(at: 1.2))
        XCTAssertNil(effect.contextSize)
        XCTAssertEqual(geometry.canvasEffect(effect).depth, 4)
    }

    func testTimeVaryingCameraContextUsesActualCanvasGeometry() {
        let size = CGSize(width: 1600, height: 900)
        let geometry = AutoZoomGeometry(sourceSize: size, cropRect: CGRect(origin: .zero, size: size),
            contentRect: CGRect(origin: .zero, size: size), canvasSize: size)
        let settings = defaultFacecamSettings(enabled: true)
        let camera = FacecamOverlayLayout.frame(in: size, settings: settings)
        let effect = TimelineZoomEffect(depth: 2, focusX: camera.midX / size.width, focusY: camera.midY / size.height,
            usesViewportCenter: true, contextSize: CGSize(width: 0.05, height: 0.05))
        XCTAssertEqual(geometry.canvasEffect(effect).depth, 2)
        XCTAssertEqual(geometry.canvasEffect(effect, cameraSettings: settings).depth, 1.35, accuracy: 0.001)
    }
}

extension AdaptiveZoomCameraTests {
    @MainActor
    func testStyleChangeOnResizedShortZoomSurvivesSaving() throws {
        let zoom = try generated()
        let driver = TimelineEditDriver()
        driver.applySnapshot(.init(zoomRegions: [zoom]))
        driver.updateSpan(kind: .zoom, id: zoom.id, span: .init(start: 1, end: 1.1), duration: 8)
        driver.updateZoomAnimationPreset(id: zoom.id, preset: .cinematic)
        let saved = try JSONEncoder().encode(driver.snapshot)
        let restored = try JSONDecoder().decode(TimelineEditSnapshot.self, from: saved)
        XCTAssertNotNil(restored.zoomRegions[0].cameraPath)
        XCTAssertEqual(restored, driver.snapshot)
    }
}

extension AdaptiveZoomCameraTests {
    func testAllStylesHonorMinimumDurationAwayFromRecordingBoundaries() {
        let payload = CursorTelemetryPayload(width: 1000, height: 1000, samples: [], clicks: [
            .init(x: 500, y: 500, timestamp: 4000, button: "left", clickCount: 1)
        ])
        for style in TimelineZoomAnimationPreset.allCases {
            let zooms = AutoZoomGenerator.generate(from: payload, duration: 10, preset: style)
            XCTAssertEqual(zooms.count, 1)
            XCTAssertGreaterThanOrEqual(zooms[0].span.duration, 2 - 0.000001)
        }
    }

    func testDenseClicksUseIndexedExtremaWithoutLosingClickPosition() throws {
        let samples = (0..<10000).map { CursorTelemetrySample(x: 700, y: 500, timestamp: 1100 + $0 / 100, cursorType: "arrow") }
        let clicks = (0..<10000).map { CursorTelemetryClick(x: 200, y: 500, timestamp: 1000 + $0 / 100, button: "left", clickCount: 1) }
        let start = Date()
        let zoom = try XCTUnwrap(AutoZoomGenerator.generate(from: .init(width: 1000, height: 1000, samples: samples, clicks: clicks), duration: 10).first)
        XCTAssertEqual(zoom.depth, 1 / 0.7, accuracy: 0.001)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
