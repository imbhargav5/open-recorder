import XCTest
@testable import OpenRecorderMac

final class TimelineZoomTransitionTests: XCTestCase {
    func testExistingZoomKeepsDefaultsUntilCustomized() throws {
        var zoom = TimelineZoomRegion(span: .init(start: 0, end: 6), depth: 2, focusX: 0.3, focusY: 0.7)
        let data = try JSONEncoder().encode(zoom)
        XCTAssertNil(try JSONDecoder().decode(TimelineZoomRegion.self, from: data).transition)
        XCTAssertEqual(TimelineZoomAnimator.animatedDepth(for: zoom, at: 0.225), 1.5, accuracy: 0.001)
        zoom.transition = .init(enterDuration: 1, exitDuration: 2, easing: .linear)
        let edits = TimelineEditSnapshot(zoomRegions: [zoom])
        let plan = TimelineExportEditPlan.build(duration: 6, edits: edits)
        for (time, depth) in [(0.5, 1.5), (1, 2), (3, 2), (5, 1.5), (5.99, 1.005)] {
            let effect = try XCTUnwrap(TimelineZoomCanvasTransform.activeEffect(edits: edits, editPlan: plan, outputTime: time))
            XCTAssertEqual(effect.depth, depth, accuracy: 0.001)
            XCTAssertEqual(effect.focusX, 0.3)
            XCTAssertEqual(effect.focusY, 0.7)
            XCTAssertEqual(edits.activeZoomEffect(at: time)?.depth, effect.depth)
        }
        XCTAssertEqual(try JSONDecoder().decode(TimelineEditSnapshot.self, from: JSONEncoder().encode(edits)), edits)
    }

    func testZoomDoesNotRestartAcrossExportFragmentsAndLayoutBoundaries() throws {
        let zoom = TimelineZoomRegion(span: .init(start: 0, end: 8), depth: 2,
            transition: .init(enterDuration: 1, exitDuration: 1, easing: .linear))
        var camera = defaultFacecamSettings(enabled: true)
        camera.layout = "split"
        let edits = TimelineEditSnapshot(zoomRegions: [zoom], cameraClips: [
            .init(span: .init(start: 0, end: 4), settings: defaultFacecamSettings(enabled: true)),
            .init(span: .init(start: 4, end: 8), settings: camera)])
        let plan = TimelineExportEditPlan(segments: [
            .init(sourceStart: 0, sourceEnd: 2, outputStart: 0, outputEnd: 2, speed: 1),
            .init(sourceStart: 2, sourceEnd: 4, outputStart: 2, outputEnd: 3, speed: 2),
            .init(sourceStart: 4, sourceEnd: 8, outputStart: 3, outputEnd: 5, speed: 2)], outputDuration: 5)
        for time in [1.999, 2.001, 2.999, 3.001, 3.75] {
            XCTAssertEqual(try XCTUnwrap(TimelineZoomCanvasTransform.activeEffect(edits: edits, editPlan: plan, outputTime: time)).depth, 2)
        }
        XCTAssertEqual(try XCTUnwrap(TimelineZoomCanvasTransform.activeEffect(edits: edits, editPlan: plan, outputTime: 4.5)).depth, 1.5, accuracy: 0.001)
        var legacy = edits
        legacy.zoomRegions[0].transition = nil
        XCTAssertEqual(try XCTUnwrap(TimelineZoomCanvasTransform.activeEffect(edits: legacy, editPlan: plan, outputTime: 3.001)).depth, 2)
    }

    func testPreviewUsesSameTransitionClockAtEditedPlaybackSpeeds() throws {
        var edits = TimelineEditSnapshot(zoomRegions: [.init(span: .init(start: 0, end: 8), depth: 2,
            transition: .init(enterDuration: 1, exitDuration: 1, easing: .linear))])
        edits.clipSplitTimes = [2]
        edits.clipSpeeds = [1: 2]
        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)
        for sourceTime in [0.5, 2.001, 5, 7] {
            let output = try XCTUnwrap(plan.outputTime(forSourceTime: sourceTime))
            XCTAssertEqual(TimelineZoomCanvasTransform.previewEffect(edits: edits, sourceTime: sourceTime, duration: 8),
                TimelineZoomCanvasTransform.activeEffect(edits: edits, editPlan: plan, outputTime: output))
        }
    }

    func testPresetTransitionKeepsEntranceCurveAndUsesForwardExit() {
        let span = TimelineSpan(start: 0, end: 5)
        for preset in TimelineZoomAnimationPreset.allCases {
            let transition = TimelineZoomTransition.defaults(for: preset)
            let ramps = transition.durations(in: span)
            for fraction in [0.1, 0.25, 0.5, 0.75, 0.9] {
                XCTAssertEqual(transition.envelope(in: span, at: ramps.enter * fraction),
                    preset.configuration.easing.value(fraction), accuracy: 0.00001)
                XCTAssertEqual(transition.envelope(in: span, at: span.end - ramps.exit + ramps.exit * fraction),
                    1 - preset.configuration.easing.value(fraction), accuracy: 0.00001)
            }
        }
    }

    func testManualAndAdaptiveZoomUseSameInAndOutTimingForEveryCurve() throws {
        let span = TimelineSpan(start: 2, end: 8)
        let path = AutoZoomCameraPath(keyframes: [
            .init(time: 2, centerX: 0.5, centerY: 0.5, depth: 1),
            .init(time: 2.4, centerX: 0.5, centerY: 0.5, depth: 2),
            .init(time: 7.6, centerX: 0.5, centerY: 0.5, depth: 2),
            .init(time: 8, centerX: 0.5, centerY: 0.5, depth: 1)])
        for motion in CameraLayoutTransition.Motion.allCases {
            for easing in TimelineZoomEasing.allCases {
                for bounce in [0.0, 0.25, 0.58, 1] {
                    let transition = TimelineZoomTransition(enterDuration: 1.5, exitDuration: 1.5,
                        motion: motion, easing: easing, bounce: bounce)
                    XCTAssertEqual(transition.durations(in: span).enter, 1.5)
                    XCTAssertEqual(transition.durations(in: span).exit, 1.5)
                    XCTAssertEqual(transition.envelope(in: span, at: 2), 0)
                    XCTAssertEqual(transition.envelope(in: span, at: 3.5), 1)
                    XCTAssertEqual(transition.envelope(in: span, at: 6.5), 1)
                    XCTAssertEqual(transition.envelope(in: span, at: 8), 0)
                    for time in stride(from: 2.0, through: 8, by: 0.025) {
                        let manualDepth = 1 + transition.envelope(in: span, at: time)
                        let adaptiveDepth = try XCTUnwrap(transition.effect(path: path, span: span, at: time)).depth
                        XCTAssertEqual(manualDepth, adaptiveDepth, accuracy: 0.0001,
                            "Manual and generated zooms must use the same curve direction and duration")
                    }
                }
            }
        }
    }

    func testEaseInAndEaseOutApplyToElapsedExitTime() {
        let span = TimelineSpan(start: 0, end: 6)
        let slowStart = TimelineZoomTransition(enterDuration: 1.5, exitDuration: 1.5, easing: .easeIn)
        let fastStart = TimelineZoomTransition(enterDuration: 1.5, exitDuration: 1.5, easing: .easeOut)
        XCTAssertEqual(slowStart.envelope(in: span, at: 4.875), 0.984375, accuracy: 0.00001)
        XCTAssertEqual(fastStart.envelope(in: span, at: 4.875), 0.421875, accuracy: 0.00001)
    }

    func testZoomSpringStillMovesLateInItsDurationAndSettlesAtEnd() {
        for bounce in [0.0, 0.25, 0.58, 1] {
            let transition = TimelineZoomTransition(enterDuration: 1.5, exitDuration: 1.5, motion: .spring, bounce: bounce)
            XCTAssertGreaterThan(abs(transition.progress(0.75) - 1), 0.005)
            for fraction in stride(from: 0.01, through: 0.99, by: 0.01) {
                XCTAssertGreaterThan(transition.progress(fraction), 0)
                XCTAssertLessThan(transition.progress(fraction), 1, "Zoom-out must not hit the renderer’s 1x clamp early")
            }
            XCTAssertEqual(transition.progress(1), 1)
            XCTAssertEqual(transition.progress(1.2), 1)
            XCTAssertEqual(transition.progress(0.99999), 1, accuracy: 0.000001)
        }
    }

    func testShortZoomFitsBothRampsAndSpringSettles() {
        let transition = TimelineZoomTransition(enterDuration: 2, exitDuration: 1, motion: .spring, bounce: 0.8)
        let span = TimelineSpan(start: 0, end: 1.5)
        XCTAssertEqual(transition.durations(in: span).enter, 1)
        XCTAssertEqual(transition.durations(in: span).exit, 0.5)
        XCTAssertEqual(transition.envelope(in: span, at: 0), 0)
        XCTAssertEqual(transition.envelope(in: span, at: 1), 1)
        XCTAssertEqual(transition.envelope(in: span, at: 1.5), 0)
        XCTAssertEqual(transition.envelope(in: span, at: 1.49999), 0, accuracy: 0.001)
    }

    func testAdaptiveZoomKeepsPanAndFocusWhenRampsAreCustomized() throws {
        let path = AutoZoomCameraPath(keyframes: [
            .init(time: 0, centerX: 0.5, centerY: 0.5, depth: 1),
            .init(time: 0.4, centerX: 0.3, centerY: 0.4, depth: 2),
            .init(time: 3.5, centerX: 0.7, centerY: 0.6, depth: 2),
            .init(time: 4, centerX: 0.5, centerY: 0.5, depth: 1)])
        let transition = TimelineZoomTransition(enterDuration: 1, exitDuration: 1, easing: .linear)
        let span = TimelineSpan(start: 0, end: 4)
        let entrance = try XCTUnwrap(transition.effect(path: path, span: span, at: 0.5))
        XCTAssertEqual(entrance.depth, 1.5, accuracy: 0.001)
        XCTAssertEqual(entrance.focusX, 0.4, accuracy: 0.001)
        let holdStart = try XCTUnwrap(transition.effect(path: path, span: span, at: 1))
        let holdEnd = try XCTUnwrap(transition.effect(path: path, span: span, at: 3))
        XCTAssertEqual(holdStart.focusX, 0.3, accuracy: 0.001)
        XCTAssertEqual(holdEnd.focusX, 0.7, accuracy: 0.001)
        XCTAssertEqual(holdStart.depth, 2)
        XCTAssertEqual(holdEnd.depth, 2)
        XCTAssertEqual(try XCTUnwrap(transition.effect(path: path, span: span, at: 3.5)).depth, 1.5, accuracy: 0.001)
    }

    @MainActor
    func testCopyPasteOnlyCopiesAnimationAndApplyAllUndoesOnce() {
        let first = TimelineZoomRegion(span: .init(start: 0, end: 3), depth: 1.5, focusX: 0.2, focusY: 0.3,
            transition: .init(enterDuration: 1.1, exitDuration: 0.7, motion: .spring, bounce: 0.6))
        let second = TimelineZoomRegion(span: .init(start: 4, end: 8), depth: 3, focusX: 0.8, focusY: 0.6)
        let driver = TimelineEditDriver()
        driver.applySnapshot(.init(zoomRegions: [first, second]))
        let original = driver.snapshot
        let clipboard = ZoomTransitionStore()
        clipboard.copy(first.transition!)
        driver.applyZoomTransition(clipboard.copiedTransition!, to: [second.id])
        var expected = second
        expected.transition = first.transition
        expected.isUserEdited = true
        XCTAssertEqual(driver.zoomRegions, [first, expected])
        driver.undo()
        XCTAssertEqual(driver.snapshot, original)
        driver.applyZoomTransition(clipboard.copiedTransition!, to: driver.zoomRegions.map(\.id))
        XCTAssertEqual(driver.zoomRegions[0].depth, 1.5)
        XCTAssertEqual(driver.zoomRegions[1].depth, 3)
        XCTAssertEqual(driver.zoomRegions[1].focusX, 0.8)
        driver.undo()
        XCTAssertEqual(driver.snapshot, original)
    }

    @MainActor
    func testSelectedZoomTransitionEditIsUndoableAndKeepsDepthAndFocus() throws {
        let driver = TimelineEditDriver()
        driver.add(.zoom, at: 1, duration: 8)
        let original = try XCTUnwrap(driver.zoomRegions.first)
        driver.beginUndoTransaction()
        for seconds in [0.2, 0.6, 1.5] {
            driver.updateZoomTransition(id: original.id, transition: .init(enterDuration: seconds))
        }
        driver.endUndoTransaction()
        let changed = try XCTUnwrap(driver.zoomRegions.first)
        XCTAssertEqual(changed.transition?.enterDuration, 1.5)
        XCTAssertEqual(changed.depth, original.depth)
        XCTAssertEqual(changed.focusX, original.focusX)
        XCTAssertEqual(changed.focusY, original.focusY)
        XCTAssertTrue(changed.isUserEdited)
        driver.undo()
        XCTAssertEqual(driver.zoomRegions.first, original)
        driver.redo()
        XCTAssertEqual(driver.zoomRegions.first, changed)
        driver.updateZoomTransition(id: original.id, transition: nil)
        XCTAssertNil(driver.zoomRegions.first?.transition)
    }
}
