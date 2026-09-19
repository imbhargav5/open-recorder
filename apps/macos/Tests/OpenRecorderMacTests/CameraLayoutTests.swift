import AVFoundation
import CoreImage
import XCTest
@testable import OpenRecorderMac

final class CameraLayoutTests: XCTestCase {
    private let canvas = CGSize(width: 640, height: 360)

    func testLegacySettingsDecodeAsOverlayWithoutChangingGeometry() throws {
        let json = ##"{"enabled":true,"shape":"circle","size":22,"cornerRadius":24,"borderWidth":4,"borderColor":"#FFFFFF","margin":4,"anchor":"bottom-right"}"##
        let settings = try JSONDecoder().decode(FacecamSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.resolvedLayout, .overlay)
        XCTAssertTrue(settings.isCircle)
        XCTAssertEqual(settings.resolvedLayoutTransition, CameraLayoutTransition())
        XCTAssertEqual(FacecamOverlayLayout.frame(in: canvas, settings: settings),
                       FacecamOverlayLayout.frame(in: canvas, settings: defaultFacecamSettings(enabled: true)))
    }

    func testLayoutsPersistInTimelineAndSwitchAtClipBoundaries() throws {
        let clips = [CameraLayout.cameraOnly, .split, .sideBySide].enumerated().map { index, layout in
            var settings = camera(layout)
            settings.cameraWidthPercent = 37
            settings.layoutPadding = 7
            settings.layoutGap = 5
            settings.cameraOnLeft = false
            settings.screenFit = "cover"
            settings.matchCameraCorners = false
            settings.screenCornerRadius = 35
            settings.centerFace = true
            return TimelineCameraClip(span: .init(start: Double(index), end: Double(index + 1)), settings: settings)
        }
        let edits = TimelineEditSnapshot(cameraClips: clips)
        let decoded = try JSONDecoder().decode(TimelineEditSnapshot.self, from: JSONEncoder().encode(edits))
        XCTAssertEqual(decoded, edits)
        for (time, expected) in [(0.0, CameraLayout.cameraOnly), (1, .split), (2, .sideBySide)] {
            let settings = try XCTUnwrap(decoded.activeCameraSettings(at: time, duration: 3, fallback: nil))
            XCTAssertEqual(settings.resolvedLayout, expected)
            XCTAssertEqual(settings.resolvedCameraWidth, 37)
            XCTAssertEqual(settings.resolvedLayoutPadding, 7)
            XCTAssertEqual(settings.resolvedLayoutGap, 5)
            XCTAssertFalse(settings.resolvedCameraOnLeft)
        }
    }

    @MainActor
    func testCameraLayoutChangesUndoAsOneSliderEdit() {
        let driver = TimelineEditDriver()
        driver.ensureCameraClips(duration: 4, fallback: camera(.split))
        let clip = driver.cameraClips[0]
        driver.beginUndoTransaction()
        for width in [20.0, 30, 70] {
            var settings = clip.settings
            settings.cameraWidthPercent = width
            driver.updateCameraClipSettings(id: clip.id, settings: settings)
        }
        driver.endUndoTransaction()
        XCTAssertEqual(driver.cameraClips[0].settings.resolvedCameraWidth, 70)
        driver.undo()
        XCTAssertEqual(driver.cameraClips[0].settings.resolvedCameraWidth, 50)
        driver.redo()
        XCTAssertEqual(driver.cameraClips[0].settings.resolvedCameraWidth, 70)
    }

    @MainActor
    func testTimelineLayoutChangeSplitsAtPlayheadAndUndoesAtomically() throws {
        let driver = TimelineEditDriver()
        var initial = camera(.split)
        initial.cameraWidthPercent = 35
        initial.centerFace = false
        driver.ensureCameraClips(duration: 12, fallback: initial)
        driver.setCameraLayout(.cameraOnly, at: 4, duration: 12, fallback: initial)
        XCTAssertEqual(driver.cameraClips.map(\.span), [.init(start: 0, end: 4), .init(start: 4, end: 12)])
        XCTAssertEqual(driver.cameraClips.map { $0.settings.resolvedLayout }, [.split, .cameraOnly])
        XCTAssertEqual(driver.selectedCameraClipID, driver.cameraClips[1].id)
        XCTAssertEqual(driver.cameraClips[1].settings.cameraWidthPercent, 35)
        XCTAssertEqual(driver.cameraClips[1].settings.centerFace, false)
        driver.undo()
        XCTAssertEqual(driver.cameraClips.count, 1)
        XCTAssertEqual(driver.cameraClips[0].settings, initial)
        driver.redo()
        XCTAssertEqual(driver.cameraClips.count, 2)
        driver.setCameraLayout(.sideBySide, at: 8, duration: 12, fallback: initial)
        // Editing an existing boundary changes only its following segment.
        driver.setCameraLayout(.overlay, at: 4, duration: 12, fallback: initial)
        XCTAssertEqual(driver.cameraClips.map { $0.settings.resolvedLayout }, [.split, .overlay, .sideBySide])
        driver.setCameraLayout(.overlay, at: 6, duration: 12, fallback: initial)
        XCTAssertEqual(driver.cameraClips.count, 3)
        let saved = try JSONDecoder().decode(TimelineEditSnapshot.self, from: JSONEncoder().encode(driver.snapshot))
        XCTAssertEqual(saved.activeCameraSettings(at: 3.99, duration: 12, fallback: initial)?.resolvedLayout, .split)
        XCTAssertEqual(saved.activeCameraSettings(at: 4, duration: 12, fallback: initial)?.resolvedLayout, .overlay)
        XCTAssertEqual(saved.activeCameraSettings(at: 8, duration: 12, fallback: initial)?.resolvedLayout, .sideBySide)
        for time in [Double.nan, -Double.infinity, -1, 12, 20, 7.99] {
            driver.setCameraLayout(.cameraOnly, at: time, duration: 12, fallback: initial)
            XCTAssertEqual(driver.snapshot, saved)
        }
    }

    func testLayoutMotionMovesBothPanelsAndFinishesAtTarget() {
        let crop = CGRect(origin: .zero, size: canvas)
        let layouts: [CameraLayout] = [.overlay, .split, .sideBySide, .cameraOnly, .overlay]
        for pair in zip(layouts, layouts.dropFirst()) {
            let before = camera(pair.0), after = camera(pair.1)
            let edits = TimelineEditSnapshot(cameraClips: [
                .init(span: .init(start: 0, end: 2), settings: before),
                .init(span: .init(start: 2, end: 4), settings: after)])
            let plan = TimelineExportEditPlan.build(duration: 4, edits: edits)
            let start = CameraLayoutPresentation.layout(before, canvas: canvas, crop: crop, styling: .none)
            let end = CameraLayoutPresentation.layout(after, canvas: canvas, crop: crop, styling: .none)
            func pose(_ time: Double) -> CameraLayoutPresentation {
                CameraLayoutMotion.presentation(edits: edits, plan: plan, time: time, duration: 4,
                    fallback: nil, canvas: canvas, crop: crop, styling: .none)
            }
            XCTAssertEqual(pose(2), start)
            XCTAssertEqual(pose(2.5), end)
            let middle = pose(2 + CameraLayoutMotion.duration / 2)
            XCTAssertEqual(middle.camera.width, (start.camera.width + end.camera.width) / 2, accuracy: 0.001)
            XCTAssertEqual(middle.screen.width, (start.screen.width + end.screen.width) / 2, accuracy: 0.001)
            XCTAssertEqual(middle.screenOpacity, (start.screenOpacity + end.screenOpacity) / 2, accuracy: 0.001)
            // Adjacent frames stay close at both transition endpoints.
            XCTAssertLessThan(abs(pose(2.001).camera.width - start.camera.width), 0.01)
            XCTAssertLessThan(abs(pose(2.419).camera.width - end.camera.width), 0.01)
        }
    }

    func testFitCoverAndSplitOptionsAnimateWithinTimelineSegments() {
        var fit = camera(.split)
        fit.cameraWidthPercent = 30
        var cover = fit
        cover.screenFit = "cover"
        cover.cameraWidthPercent = 60
        cover.cameraOnLeft = false
        let edits = TimelineEditSnapshot(cameraClips: [
            .init(span: .init(start: 0, end: 2), settings: fit),
            .init(span: .init(start: 2, end: 4), settings: cover)])
        let plan = TimelineExportEditPlan.build(duration: 4, edits: edits)
        let crop = CGRect(origin: .zero, size: canvas)
        let start = CameraLayoutPresentation.layout(fit, canvas: canvas, crop: crop, styling: .none)
        let end = CameraLayoutPresentation.layout(cover, canvas: canvas, crop: crop, styling: .none)
        let middle = CameraLayoutMotion.presentation(edits: edits, plan: plan, time: 2.21, duration: 4,
            fallback: nil, canvas: canvas, crop: crop, styling: .none)
        XCTAssertEqual(middle.screen.height, (start.screen.height + end.screen.height) / 2, accuracy: 0.001)
        XCTAssertEqual(middle.camera.minX, (start.camera.minX + end.camera.minX) / 2, accuracy: 0.001)
    }

    func testLayoutMotionUsesOutputClockAndIgnoresZoomBoundaries() {
        let before = camera(.overlay), after = camera(.split)
        let edits = TimelineEditSnapshot(zoomRegions: [.init(span: .init(start: 4.1, end: 4.2), depth: 2)],
            cameraClips: [.init(span: .init(start: 0, end: 4), settings: before),
                          .init(span: .init(start: 4, end: 8), settings: after)])
        let plan = TimelineExportEditPlan(segments: [
            .init(sourceStart: 1, sourceEnd: 4, outputStart: 0, outputEnd: 1.5, speed: 2),
            .init(sourceStart: 4, sourceEnd: 4.1, outputStart: 1.5, outputEnd: 1.55, speed: 2),
            .init(sourceStart: 4.1, sourceEnd: 8, outputStart: 1.55, outputEnd: 3.5, speed: 2)], outputDuration: 3.5)
        let crop = CGRect(origin: .zero, size: canvas)
        let a = CameraLayoutPresentation.layout(before, canvas: canvas, crop: crop, styling: .none)
        let b = CameraLayoutPresentation.layout(after, canvas: canvas, crop: crop, styling: .none)
        let actual = CameraLayoutMotion.presentation(edits: edits, plan: plan, time: 1.71, duration: 8,
            fallback: nil, canvas: canvas, crop: crop, styling: .none)
        XCTAssertEqual(actual.camera.width, (a.camera.width + b.camera.width) / 2, accuracy: 0.001)
    }

    func testLiveMotionRetargetsWithoutJumpAndSliderUpdatesAreAtomic() throws {
        let crop = CGRect(origin: .zero, size: canvas)
        let a = CameraLayoutPresentation.layout(camera(.overlay), canvas: canvas, crop: crop, styling: .none)
        let b = CameraLayoutPresentation.layout(camera(.split), canvas: canvas, crop: crop, styling: .none)
        let c = CameraLayoutPresentation.layout(camera(.cameraOnly), canvas: canvas, crop: crop, styling: .none)
        var motion = CameraLayoutLiveMotion()
        motion.retarget(a, at: 0, animated: false)
        motion.retarget(b, at: 1, animated: true)
        let current = try XCTUnwrap(motion.value(at: 1.15))
        motion.retarget(c, at: 1.15, animated: true)
        XCTAssertEqual(motion.value(at: 1.15), current)
        XCTAssertEqual(motion.value(at: 2), c)
        motion.retarget(b, at: 2.1, animated: false)
        XCTAssertEqual(motion.value(at: 2.1), b, "Slider changes update screen and camera on the same frame")
    }

    func testTransitionSettingsPersistAndClampInvalidValues() throws {
        var settings = camera(.split)
        settings.layoutTransition = .init(duration: 1.25, motion: .spring, easing: .easeOut, bounce: 0.65, blur: 0.3, fade: 0.4)
        let edits = TimelineEditSnapshot(cameraClips: [.init(span: .init(start: 0, end: 4), settings: settings)])
        XCTAssertEqual(try JSONDecoder().decode(TimelineEditSnapshot.self, from: JSONEncoder().encode(edits)), edits)
        settings.layoutTransition = .init(duration: .infinity, bounce: -1, blur: 5, fade: .nan)
        let clamped = settings.clamped.resolvedLayoutTransition
        XCTAssertEqual(clamped.duration, 0.42)
        XCTAssertEqual(clamped.bounce, 0)
        XCTAssertEqual(clamped.blur, 1)
        XCTAssertEqual(clamped.fade, 0)
    }

    @MainActor
    func testTransitionSliderUndoPreservesOtherSegments() {
        let driver = TimelineEditDriver()
        driver.ensureCameraClips(duration: 4, fallback: camera(.split))
        driver.splitCameraClip(at: 2, duration: 4, fallback: nil)
        let first = driver.cameraClips[0]
        let second = driver.cameraClips[1]
        driver.beginUndoTransaction()
        for duration in [0.5, 0.8, 1.2] {
            var settings = second.settings
            settings.layoutTransition = .init(duration: duration, motion: .spring, blur: 0.5)
            driver.updateCameraClipSettings(id: second.id, settings: settings)
        }
        driver.endUndoTransaction()
        XCTAssertEqual(driver.cameraClips[0], first)
        XCTAssertEqual(driver.cameraClips[1].settings.resolvedLayoutTransition.duration, 1.2)
        driver.undo()
        XCTAssertEqual(driver.cameraClips[1], second)
        driver.redo()
        XCTAssertEqual(driver.cameraClips[1].settings.resolvedLayoutTransition.blur, 0.5)
    }

    func testEasingAndSpringControlsReachExactEndpoints() {
        for easing in CameraLayoutTransition.Easing.allCases {
            let transition = CameraLayoutTransition(easing: easing)
            XCTAssertEqual(transition.progress(at: 0), 0)
            XCTAssertEqual(transition.progress(at: 1), 1)
        }
        XCTAssertLessThan(CameraLayoutTransition(easing: .easeIn).progress(at: 0.5), 0.5)
        XCTAssertGreaterThan(CameraLayoutTransition(easing: .easeOut).progress(at: 0.5), 0.5)
        let spring = CameraLayoutTransition(motion: .spring, bounce: 1)
        let damped = CameraLayoutTransition(motion: .spring, bounce: 0)
        XCTAssertEqual(spring.progress(at: 0), 0)
        XCTAssertEqual(spring.progress(at: 1), 1)
        XCTAssertGreaterThan(spring.progress(at: 0.3), 1, "Spring can overshoot instead of stopping abruptly")
        XCTAssertLessThan(damped.progress(at: 0.3), 1)
        XCTAssertEqual(spring.progress(at: 0.999), 1, accuracy: 0.00001)
    }

    func testCustomTransitionTimingMatchesLivePreviewAndShortSegmentsSettle() throws {
        let before = camera(.overlay)
        var after = camera(.split)
        after.layoutTransition = .init(duration: 1.2, motion: .spring, bounce: 0.6, blur: 0.3, fade: 0.4)
        let crop = CGRect(origin: .zero, size: canvas)
        let a = CameraLayoutPresentation.layout(before, canvas: canvas, crop: crop, styling: .none)
        let b = CameraLayoutPresentation.layout(after, canvas: canvas, crop: crop, styling: .none)
        func pose(_ time: Double, end: Double = 6) -> CameraLayoutPresentation {
            let edits = TimelineEditSnapshot(cameraClips: [.init(span: .init(start: 0, end: 2), settings: before),
                .init(span: .init(start: 2, end: end), settings: after)])
            return CameraLayoutMotion.presentation(edits: edits, plan: .build(duration: end, edits: edits), time: time,
                duration: end, fallback: nil, canvas: canvas, crop: crop, styling: .none)
        }
        var live = CameraLayoutLiveMotion()
        live.retarget(a, at: 0, animated: false)
        live.retarget(b, at: 2, animated: true, transition: after.resolvedLayoutTransition)
        XCTAssertEqual(pose(2.6), try XCTUnwrap(live.value(at: 2.6)))
        XCTAssertEqual(pose(2.6).transitionBlur, 0.3, accuracy: 0.0001)
        XCTAssertEqual(pose(2.6).transitionFade, 0.4, accuracy: 0.0001)
        XCTAssertEqual(pose(3.21), b)
        XCTAssertEqual(pose(2.399, end: 2.4).camera.width, b.camera.width, accuracy: 0.001,
                       "A segment shorter than the transition settles at its end")
        after.layoutTransition?.duration = 0
        XCTAssertEqual(pose(2), b, "Zero duration is an instant switch without transient effects")
    }

    func testSelectedTransitionDurationIsIndependentOfIncomingSegmentLength() {
        let before = camera(.overlay)
        var after = camera(.split)
        after.layoutTransition = .init(duration: 1.5, easing: .linear, blur: 0.4, fade: 0.3)
        let crop = CGRect(origin: .zero, size: canvas)
        let a = CameraLayoutPresentation.layout(before, canvas: canvas, crop: crop, styling: .none)
        let b = CameraLayoutPresentation.layout(after, canvas: canvas, crop: crop, styling: .none)
        for segmentLength in [1.8, 4, 15] {
            let end = 2 + segmentLength
            let edits = TimelineEditSnapshot(cameraClips: [.init(span: .init(start: 0, end: 2), settings: before),
                .init(span: .init(start: 2, end: end), settings: after)])
            let plan = TimelineExportEditPlan.build(duration: end, edits: edits)
            func pose(_ time: Double) -> CameraLayoutPresentation {
                CameraLayoutMotion.presentation(edits: edits, plan: plan, time: time, duration: end,
                    fallback: nil, canvas: canvas, crop: crop, styling: .none)
            }
            XCTAssertEqual(pose(2.75).camera.width, (a.camera.width + b.camera.width) / 2, accuracy: 0.001)
            XCTAssertEqual(pose(2.75).transitionBlur, 0.4, accuracy: 0.001)
            XCTAssertEqual(pose(2.75).transitionFade, 0.3, accuracy: 0.001)
            XCTAssertNotEqual(pose(3.2), b, "A short segment must not silently accelerate the transition")
            XCTAssertEqual(pose(3.5), b)
        }
    }

    func testTransitionFadeAffectsBothPanelsAndClearsAtEnd() throws {
        var before = camera(.split), after = camera(.sideBySide)
        before.cameraOnLeft = false
        after.layoutTransition = .init(duration: 1, easing: .linear, fade: 1)
        let edits = TimelineEditSnapshot(cameraClips: [.init(span: .init(start: 0, end: 2), settings: before),
            .init(span: .init(start: 2, end: 4), settings: after)])
        let compositor = VideoBackgroundCompositor()
        let source = try pixelBuffer(color: .blue), cameraBuffer = try pixelBuffer(color: .red)
        let instruction = instruction(settings: nil, edits: edits)
        let faded = try compositor.makeComposedImage(source: source, facecam: cameraBuffer, instruction: instruction, compositionTime: 2.5)
        let pose = CameraLayoutMotion.presentation(edits: edits, plan: .build(duration: 4, edits: edits), time: 2.5,
            duration: 4, fallback: nil, canvas: canvas, crop: CGRect(origin: .zero, size: canvas), styling: .none)
        assertColor(faded, at: CGPoint(x: pose.camera.midX, y: pose.camera.midY), red: 0, blue: 0)
        assertColor(faded, at: CGPoint(x: pose.screen.midX, y: pose.screen.midY), red: 0, blue: 0)
        let settled = try compositor.makeComposedImage(source: source, facecam: cameraBuffer, instruction: instruction, compositionTime: 3)
        let frames = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: after)
        assertColor(settled, at: CGPoint(x: frames.camera.midX, y: frames.camera.midY), red: 255, blue: 0)
        assertColor(settled, at: CGPoint(x: frames.screen.midX, y: frames.screen.midY), red: 0, blue: 255)
    }

    func testTransitionBlurSoftensDetailWithoutSmearingPanelsAcrossCanvas() {
        var pose = CameraLayoutPresentation.layout(camera(.split), canvas: canvas, crop: CGRect(origin: .zero, size: canvas), styling: .none)
        pose.transitionBlur = 1
        let left = CIImage(color: .red).cropped(to: CGRect(x: 100, y: 100, width: 100, height: 100))
        let right = CIImage(color: .blue).cropped(to: CGRect(x: 200, y: 100, width: 100, height: 100))
        let image = VideoBackgroundCompositor().applyCameraTransitionEffects(left.composited(over: right), presentation: pose, canvas: canvas)
        // Core Image blends in linear light; a half-intensity channel is ~188 in sRGB.
        assertColor(image, at: CGPoint(x: 200, y: 210), red: 188, blue: 188, tolerance: 12)
        assertColor(image, at: CGPoint(x: 2, y: 210), red: 0, blue: 0)
    }

    func testFaceMotionRejectsJitterAndEasesAtAnyFrameRate() {
        var motion = CameraFaceFocusMotion()
        let initial = CGPoint(x: 0.6, y: 0.4)
        XCTAssertEqual(motion.update(detection: initial, at: 0), initial)
        XCTAssertEqual(motion.update(detection: CGPoint(x: 0.61, y: 0.41), at: 0.1), initial)
        let moved = motion.update(detection: CGPoint(x: 0.8, y: 0.4), at: 0.12)
        XCTAssertGreaterThan(moved.x, 0.6)
        XCTAssertLessThan(moved.x, 0.63, "A fresh detection must not snap the crop")
        var slow = CameraFaceFocusMotion(), fast = CameraFaceFocusMotion()
        _ = slow.update(detection: initial, at: 0)
        _ = fast.update(detection: initial, at: 0)
        for index in 1...30 { _ = slow.update(detection: CGPoint(x: 0.8, y: 0.4), at: Double(index) / 30) }
        for index in 1...60 { _ = fast.update(detection: CGPoint(x: 0.8, y: 0.4), at: Double(index) / 60) }
        XCTAssertEqual(slow.position.x, fast.position.x, accuracy: 0.0001)
        XCTAssertEqual(slow.position.x, 0.8, accuracy: 0.003)
        XCTAssertEqual(motion.update(detection: initial, at: 3, reset: true), initial)
    }

    func testPanelGeometryAtBothWidthLimitsAndBothSides() {
        for size in [canvas, CGSize(width: 360, height: 640), CGSize(width: 500, height: 500)] {
            for layout in [CameraLayout.split, .sideBySide] {
                for percent in [10.0, 50, 70] {
                    for left in [true, false] {
                        var settings = camera(layout)
                        settings.cameraWidthPercent = percent
                        settings.cameraOnLeft = left
                        let frames = CameraLayoutGeometry.frames(in: size, screenAspectRatio: 16 / 9, settings: settings)
                        let base = min(size.width, size.height)
                        let pad = base * 0.04
                        let gap = base * 0.03
                        XCTAssertEqual(frames.camera.width, (size.width - pad * 2 - gap) * percent / 100, accuracy: 0.001)
                        XCTAssertFalse(frames.screen.intersects(frames.camera))
                        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frames.camera))
                        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frames.screen))
                        XCTAssertEqual(frames.screen.width / frames.screen.height, 16 / 9, accuracy: 0.001)
                        XCTAssertEqual(frames.camera.midY, size.height / 2, accuracy: 0.001)
                        XCTAssertEqual(left ? frames.screen.minX - frames.camera.maxX : frames.camera.minX - frames.screen.maxX,
                                       gap, accuracy: 0.001)
                        XCTAssertEqual(FacecamOverlayLayout.frame(in: size, settings: settings), frames.camera)
                        if layout == .split { XCTAssertEqual(frames.camera.height, size.height - 2 * pad, accuracy: 0.001) }
                        else { XCTAssertLessThanOrEqual(frames.camera.height, frames.camera.width) }
                    }
                }
            }
        }
    }

    func testCoverFillsHeightAndCropsWithinOriginalSelection() {
        for layout in [CameraLayout.split, .sideBySide] {
            for width in [10.0, 50, 70] {
                var settings = camera(layout)
                settings.cameraWidthPercent = width
                settings.screenFit = "cover"
                let frames = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: settings)
                XCTAssertEqual(frames.screen.height, canvas.height * 0.92, accuracy: 0.001)
                let crop = CGRect(x: 100, y: 50, width: 1000, height: 600)
                let covered = CameraLayoutGeometry.screenCrop(in: crop, panel: frames.screen.size, fit: .cover)
                XCTAssertTrue(crop.contains(covered))
                XCTAssertEqual(covered.midX, crop.midX, accuracy: 0.001)
                XCTAssertEqual(covered.midY, crop.midY, accuracy: 0.001)
                XCTAssertEqual(covered.width / covered.height, frames.screen.width / frames.screen.height, accuracy: 0.001)
                XCTAssertEqual(CameraLayoutGeometry.screenCrop(in: crop, panel: frames.screen.size, fit: .fit), crop)
            }
        }
    }

    func testScreenCornersMatchCameraAndStayRoundedDuringZoom() throws {
        var settings = camera(.split)
        settings.screenFit = "cover"
        settings.cornerRadius = 100
        XCTAssertEqual(settings.resolvedScreenCornerRadius, 100)
        let frames = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: settings)
        let edits = TimelineEditSnapshot(zoomRegions: [.init(span: .init(start: 0, end: 4), depth: 2)])
        let compositor = VideoBackgroundCompositor()
        let source = try pixelBuffer(color: .blue)
        let corner = CGPoint(x: frames.screen.minX + 2, y: frames.screen.minY + 2)
        let rounded = try compositor.makeComposedImage(source: source, facecam: nil,
            instruction: instruction(settings: settings, edits: edits), compositionTime: 2)
        assertColor(rounded, at: corner, red: 0, blue: 0)
        settings.matchCameraCorners = false
        settings.screenCornerRadius = 0
        XCTAssertEqual(settings.resolvedScreenCornerRadius, 0)
        XCTAssertEqual(settings.cornerRadius, 100)
        let square = try compositor.makeComposedImage(source: source, facecam: nil,
            instruction: instruction(settings: settings, edits: edits), compositionTime: 2)
        assertColor(square, at: corner, red: 0, blue: 255)
    }

    func testFaceStaysCenteredAcrossCameraWidthsWithoutBlankEdges() {
        let source = CGSize(width: 1920, height: 1080)
        let face = CGPoint(x: 0.65, y: 0.45)
        for width in [100.0, 300, 700] {
            let target = CGRect(x: 20, y: 10, width: width, height: 900)
            let frame = CameraFaceFraming.imageFrame(source: source, target: target, focus: face)
            XCTAssertEqual(frame.minX + face.x * frame.width, target.midX, accuracy: 0.001)
            XCTAssertTrue(frame.contains(target))
            for edge in [CGPoint.zero, CGPoint(x: 1, y: 1)] {
                XCTAssertTrue(CameraFaceFraming.imageFrame(source: source, target: target, focus: edge).contains(target))
            }
        }
    }

    func testFaceDetectionAndMissingFaceFallback() throws {
        let tracker = CameraFaceTracker()
        let blank = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvas))
        XCTAssertEqual(tracker.focus(in: blank, at: 0), CGPoint(x: 0.5, y: 0.5))
        guard let path = ProcessInfo.processInfo.environment["OPEN_RECORDER_FACE_FIXTURE"] else { return }
        let image = try XCTUnwrap(CIImage(contentsOf: URL(fileURLWithPath: path)))
        let face = tracker.focus(in: image, at: 0.5)
        XCTAssertNotEqual(face, CGPoint(x: 0.5, y: 0.5), "The supplied off-center face must be found")
        let held = tracker.focus(in: blank, at: 1)
        XCTAssertGreaterThan(hypot(held.x - 0.5, held.y - 0.5), hypot(face.x - 0.5, face.y - 0.5), "Missed detections continue easing toward the last face")
        _ = tracker.focus(in: blank, at: 1.5)
        _ = tracker.focus(in: blank, at: 2)
        let returning = tracker.focus(in: blank, at: 2.5)
        XCTAssertLessThan(hypot(returning.x - 0.5, returning.y - 0.5), hypot(held.x - 0.5, held.y - 0.5))
        XCTAssertNotEqual(returning, CGPoint(x: 0.5, y: 0.5), "Losing a face eases back without a jump")
    }

    func testCameraOnlyPaddingAndInvalidInput() {
        var settings = camera(.cameraOnly)
        settings.layoutPadding = 10
        let frames = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: settings)
        XCTAssertTrue(frames.screen.isEmpty)
        XCTAssertEqual(frames.camera, CGRect(x: 36, y: 36, width: 568, height: 288))
        settings.layoutPadding = .nan
        settings.layoutGap = .infinity
        settings.cameraWidthPercent = 90
        XCTAssertEqual(settings.clamped.resolvedLayoutPadding, 4)
        XCTAssertEqual(settings.clamped.resolvedLayoutGap, 3)
        XCTAssertEqual(settings.clamped.resolvedCameraWidth, 70)
        settings.cameraWidthPercent = -1
        XCTAssertEqual(settings.clamped.resolvedCameraWidth, 10)
        XCTAssertTrue(CameraLayoutGeometry.frames(in: .zero, screenAspectRatio: 1, settings: settings).camera.isEmpty)
        settings.layout = "future-layout"
        XCTAssertEqual(settings.resolvedLayout, .overlay)
    }

    func testCompositorRendersLayoutsAndPreservesGapsDuringZoom() throws {
        let source = try pixelBuffer(color: .blue)
        let facecam = try pixelBuffer(color: .red)
        for layout in [CameraLayout.cameraOnly, .split, .sideBySide] {
            for left in [true, false] {
                var settings = camera(layout)
                settings.cameraOnLeft = left
                let frames = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: settings)
                for zoomed in [false, true] {
                    let edits = TimelineEditSnapshot(zoomRegions: zoomed
                        ? [.init(span: .init(start: 0, end: 4), depth: 2)] : [])
                    let instruction = instruction(settings: settings, edits: edits)
                    let image = try VideoBackgroundCompositor().makeComposedImage(source: source, facecam: facecam,
                        instruction: instruction, compositionTime: 2)
                    assertColor(image, at: CGPoint(x: frames.camera.midX, y: frames.camera.midY), red: 255, blue: 0)
                    if !frames.screen.isEmpty {
                        assertColor(image, at: CGPoint(x: frames.screen.midX, y: frames.screen.midY), red: 0, blue: 255)
                        let gapX = left ? (frames.camera.maxX + frames.screen.minX) / 2 : (frames.screen.maxX + frames.camera.minX) / 2
                        assertColor(image, at: CGPoint(x: gapX, y: canvas.height / 2), red: 0, blue: 0)
                    }
                    assertColor(image, at: CGPoint(x: 2, y: 2), red: 0, blue: 0)
                    if layout == .cameraOnly {
                        assertColor(image, at: CGPoint(x: canvas.width / 2, y: canvas.height / 2), red: 255, blue: 0)
                    }
                }
            }
        }
    }

    func testPreviewUsesSameScreenPlacementWithoutDecodedCameraBuffer() throws {
        let settings = camera(.split)
        let frames = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: settings)
        let image = try VideoBackgroundCompositor().makeComposedImage(source: pixelBuffer(color: .blue), facecam: nil,
            instruction: instruction(settings: settings), compositionTime: 2)
        assertColor(image, at: CGPoint(x: frames.screen.midX, y: frames.screen.midY), red: 0, blue: 255)
        assertColor(image, at: CGPoint(x: frames.camera.midX, y: frames.camera.midY), red: 0, blue: 0)
    }

    func testDisabledCameraRestoresScreenAndLayoutsFollowEditedSourceTime() throws {
        let source = try pixelBuffer(color: .blue)
        let facecam = try pixelBuffer(color: .red)
        var hidden = camera(.cameraOnly)
        hidden.enabled = false
        let clips = [TimelineCameraClip(span: .init(start: 0, end: 2), settings: camera(.cameraOnly)),
                     TimelineCameraClip(span: .init(start: 2, end: 4), settings: hidden)]
        let edits = TimelineEditSnapshot(trimRegions: [.init(span: .init(start: 0, end: 1))], cameraClips: clips)
        let compositor = VideoBackgroundCompositor()
        for (time, red, blue) in [(0.5, UInt8(255), UInt8(0)), (1.5, 0, 255)] {
            let image = try compositor.makeComposedImage(source: source, facecam: facecam,
                instruction: instruction(settings: nil, edits: edits), compositionTime: time)
            assertColor(image, at: CGPoint(x: canvas.width / 2, y: canvas.height / 2), red: red, blue: blue)
        }
    }

    /// Encodes real source/camera tracks and exports timeline layout switches.
    /// Opt in to retain a review project and movie under .build/camera-layout-validation.
    @MainActor
    func testMovieExportWithLayoutSwitches() async throws {
        guard ProcessInfo.processInfo.environment["OPEN_RECORDER_CAMERA_LAYOUT_CHECK"] == "1" else {
            throw XCTSkip("Opt-in video encoding and review artifacts")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/camera-layout-validation/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let screenURL = root.appendingPathComponent("screen.mov")
        let cameraURL = root.appendingPathComponent("camera.mov")
        try await writeMovie(to: screenURL, buffer: pixelBuffer(color: .blue))
        try await writeMovie(to: cameraURL, buffer: pixelBuffer(color: .red))
        var right = camera(.split)
        right.cameraOnLeft = false
        right.cameraWidthPercent = 70
        right.layoutTransition = .init(duration: 0.8, motion: .spring, bounce: 0.6, blur: 0.3, fade: 0.4)
        let settings = [camera(.cameraOnly), camera(.split), camera(.sideBySide), right]
        let clips = settings.enumerated().map { index, settings in
            TimelineCameraClip(span: .init(start: Double(index), end: Double(index + 1)), settings: settings)
        }
        let edits = TimelineEditSnapshot(cameraClips: clips)
        var options = VideoExportOptions.default
        options.resolution = .source
        options.frameRate = .fps30
        options.styling = .none
        options.styling.background = .solid(SerializableColor(hex: "000000"))
        options.facecamVideoURL = cameraURL
        let output = root.appendingPathComponent("camera-layouts.mov")
        try await VideoExportRenderer.export(sourceURL: screenURL, targetURL: output, options: options, edits: edits)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for (index, settings) in settings.enumerated() {
            let frame = try await generator.image(at: CMTime(seconds: Double(index) + 0.9, preferredTimescale: 600)).image
            let image = CIImage(cgImage: frame)
            let geometry = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: settings)
            assertColor(image, at: CGPoint(x: geometry.camera.midX, y: geometry.camera.midY), red: 255, blue: 0, tolerance: 24)
            if !geometry.screen.isEmpty {
                assertColor(image, at: CGPoint(x: geometry.screen.midX, y: geometry.screen.midY), red: 0, blue: 255, tolerance: 24)
            }
            try CIContext().writePNGRepresentation(of: image, to: root.appendingPathComponent("layout-\(index).png"),
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        // Check an encoded in-between frame, not just the settled layouts.
        let transitionTime = 1.2
        let transitioningFrame = try await generator.image(at: CMTime(seconds: transitionTime, preferredTimescale: 600)).image
        let pose = CameraLayoutMotion.presentation(edits: edits, plan: .build(duration: 4, edits: edits), time: transitionTime,
            duration: 4, fallback: nil, canvas: canvas, crop: CGRect(origin: .zero, size: canvas), styling: options.styling)
        let finalCamera = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: settings[1]).camera
        XCTAssertGreaterThan(pose.camera.maxX, finalCamera.maxX + 20)
        assertColor(CIImage(cgImage: transitioningFrame), at: CGPoint(x: pose.camera.maxX - 15, y: pose.camera.midY),
            red: 255, blue: 0, tolerance: 24)
        // The final segment uses custom spring timing with blur and fade.
        let effectFrame = try await generator.image(at: CMTime(seconds: 3.4, preferredTimescale: 600)).image
        let effectPose = CameraLayoutMotion.presentation(edits: edits, plan: .build(duration: 4, edits: edits), time: 3.4,
            duration: 4, fallback: nil, canvas: canvas, crop: CGRect(origin: .zero, size: canvas), styling: options.styling)
        // 60% linear-light intensity is ~203 in sRGB.
        assertColor(CIImage(cgImage: effectFrame), at: CGPoint(x: effectPose.camera.midX, y: effectPose.camera.midY),
            red: 203, blue: 0, tolerance: 24)
        let project = ProjectDocument(schemaVersion: 2, title: "Camera Layout Review", recordingPath: screenURL.path,
            screenshotPath: nil, sourceName: "Synthetic layout check", createdAt: "2026-09-19T00:00:00Z",
            updatedAt: "2026-09-19T00:00:00Z", editorState: ProjectEditorState(timelineEdits: edits),
            recordingSession: RecordingSession(screenVideoPath: screenURL.path, facecamVideoPath: cameraURL.path,
                facecamOffsetMs: 0, facecamSettings: settings[0], sourceName: "Synthetic layout check",
                showCursorOverlay: false, cursorTelemetryPath: nil))
        try JSONEncoder().encode(project).write(to: root.appendingPathComponent("review.openrecorder"))
        print("CAMERA_LAYOUT_REVIEW \(root.path)")
    }

    @MainActor
    private func writeMovie(to url: URL, buffer: CVPixelBuffer, transform: CGAffineTransform = .identity) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<120 {
            while !input.isReadyForMoreMediaData {
                if let error = writer.error { throw error }
                try await Task.sleep(for: .milliseconds(2))
            }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    @MainActor
    func testVideoPreviewOrientationFromDecodedPlayerFrame() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try pixelBuffer(color: .blue)
        let top = CIImage(color: .red).cropped(to: CGRect(x: 0, y: canvas.height / 2, width: canvas.width, height: canvas.height / 2))
        CIContext().render(top.composited(over: CIImage(color: .blue).cropped(to: CGRect(origin: .zero, size: canvas))), to: source)
        let url = directory.appendingPathComponent("orientation.mov")
        try await writeMovie(to: url, buffer: source, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvas.height))
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        for _ in 0..<300 {
            if item.status == .readyToPlay { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(item.status, .readyToPlay)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        var decoded: CVPixelBuffer?
        for _ in 0..<300 {
            decoded = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
            if decoded != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let settings = camera(.split)
        let frames = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: 16 / 9, settings: settings)
        let image = try VideoBackgroundCompositor().makeComposedImage(source: XCTUnwrap(decoded), facecam: nil,
            instruction: instruction(settings: settings, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvas.height)), compositionTime: 0.5)
        assertColor(image, at: CGPoint(x: frames.screen.midX, y: frames.screen.minY + frames.screen.height * 0.25), red: 0, blue: 255, tolerance: 32)
        assertColor(image, at: CGPoint(x: frames.screen.midX, y: frames.screen.minY + frames.screen.height * 0.75), red: 255, blue: 0, tolerance: 32)
        player.pause()
    }

    private func camera(_ layout: CameraLayout) -> FacecamSettings {
        var settings = defaultFacecamSettings(enabled: true)
        settings.layout = layout.rawValue
        settings.borderWidth = 0
        settings.cornerRadius = 0
        return settings
    }

    private func instruction(settings: FacecamSettings?, edits: TimelineEditSnapshot = .empty,
                             transform: CGAffineTransform = .identity) -> VideoBackgroundCompositionInstruction {
        var styling = VideoBackgroundStyling.none
        styling.background = .solid(SerializableColor(hex: "000000"))
        return VideoBackgroundCompositionInstruction(timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 4, preferredTimescale: 600)),
            trackID: 1, facecamTrackID: 2, styling: styling, preferredTransform: transform,
            normalizedSize: canvas, facecamNormalizedSize: canvas, cropRect: CGRect(origin: .zero, size: canvas),
            renderSize: canvas, edits: edits, editPlan: .build(duration: 4, edits: edits), facecamFallbackSettings: settings)
    }

    private func pixelBuffer(color: CIColor) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(canvas.width), Int(canvas.height), kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(result)
        CIContext().render(CIImage(color: color).cropped(to: CGRect(origin: .zero, size: canvas)), to: buffer)
        return buffer
    }

    private func assertColor(_ image: CIImage, at point: CGPoint, red: UInt8, blue: UInt8,
                             tolerance: Int = 2, file: StaticString = #filePath, line: UInt = #line) {
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(image, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: point.x.rounded(.down), y: (canvas.height - point.y).rounded(.down), width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        XCTAssertEqual(Int(pixel[0]), Int(red), accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(Int(pixel[2]), Int(blue), accuracy: tolerance, file: file, line: line)
    }
}
