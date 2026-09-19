import XCTest
@testable import OpenRecorderMac

final class CameraTransitionSharingTests: XCTestCase {
    @MainActor
    func testPasteAndApplyToAllOnlyChangeTransitionsAndUndoAtomically() {
        let driver = TimelineEditDriver()
        var left = defaultFacecamSettings(enabled: true)
        left.layout = CameraLayout.split.rawValue
        left.cameraWidthPercent = 65
        var right = defaultFacecamSettings(enabled: false)
        right.layout = CameraLayout.sideBySide.rawValue
        right.cameraOnLeft = false
        let clips = [TimelineCameraClip(span: .init(start: 0, end: 2), settings: left),
                     TimelineCameraClip(span: .init(start: 2, end: 6), settings: right)]
        driver.applySnapshot(.init(cameraClips: clips))
        driver.selectCameraClip(id: clips[0].id)
        let original = driver.snapshot
        let transition = CameraLayoutTransition(duration: 1.5, motion: .spring, bounce: 0.7,
            blur: 0.4, fade: 0.6, blurStart: 0.1, blurDuration: 0.25)
        driver.applyCameraTransition(transition, to: [clips[1].id])
        XCTAssertEqual(driver.cameraClips[0], clips[0])
        XCTAssertEqual(driver.cameraClips[1].settings.layoutTransition, transition)
        var expectedRight = right
        expectedRight.layoutTransition = transition
        XCTAssertEqual(driver.cameraClips[1].settings, expectedRight)
        driver.undo()
        XCTAssertEqual(driver.snapshot, original)

        driver.applyCameraTransition(transition, to: clips.map(\.id))
        let applied = driver.snapshot
        for (before, after) in zip(clips, driver.cameraClips) {
            var expected = before
            expected.settings.layoutTransition = transition
            XCTAssertEqual(after, expected)
        }
        XCTAssertEqual(driver.selectedCameraClip(duration: 6, fallback: nil)?.id, clips[0].id)
        driver.undo()
        XCTAssertEqual(driver.snapshot, original, "Apply to all is a single undo step")
        driver.redo()
        XCTAssertEqual(driver.snapshot, applied)
    }

    @MainActor
    func testPresetsPersistAcrossProjectsAndRestartsWithoutOverwritingNames() throws {
        let suite = "CameraTransitionSharingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CameraTransitionStore(defaults: defaults)
        XCTAssertNil(store.copiedTransition)
        let transition = CameraLayoutTransition(duration: 1.5, motion: .spring, blur: 0.5, fade: 0.25,
            blurStart: 0.2, blurDuration: 0.3)
        store.copy(transition)
        XCTAssertEqual(store.copiedTransition, transition)
        let first = try XCTUnwrap(store.save(name: "  Soft spring  ", transition: transition))
        let second = try XCTUnwrap(store.save(name: "Soft spring", transition: .init()))
        XCTAssertEqual(first.name, "Soft spring")
        XCTAssertEqual(second.name, "Soft spring (2)")
        XCTAssertNil(store.save(name: " \n ", transition: transition))
        let reopened = CameraTransitionStore(defaults: defaults)
        XCTAssertEqual(reopened.presets, [first, second])
        XCTAssertEqual(reopened.presets[0].transition, transition)
        reopened.delete(id: first.id)
        XCTAssertEqual(CameraTransitionStore(defaults: defaults).presets, [second])
    }

    func testLegacyTransitionsDecodeWithIndependentBlurDefaults() throws {
        let json = #"{"duration":1.5,"motion":"spring","easing":"smooth","bounce":0.25,"blur":0.5,"fade":0}"#
        let transition = try JSONDecoder().decode(CameraLayoutTransition.self, from: Data(json.utf8))
        XCTAssertEqual(transition.resolvedBlurStart, 0)
        XCTAssertEqual(transition.resolvedBlurDuration, 0.2)
    }

    func testBlurTimingIsIndependentAndNeverExtendsPastTransition() {
        let transition = CameraLayoutTransition(blur: 1, blurStart: 0.1, blurDuration: 0.2)
        for duration in [0.5, 1.5, 2] {
            XCTAssertEqual(transition.blurEnvelope(at: 0.1, transitionDuration: duration), 0)
            XCTAssertEqual(transition.blurEnvelope(at: 0.2, transitionDuration: duration), 1, accuracy: 0.00001)
            XCTAssertEqual(transition.blurEnvelope(at: 0.31, transitionDuration: duration), 0)
            XCTAssertEqual(transition.blurEnvelope(at: duration, transitionDuration: duration), 0)
            XCTAssertEqual(transition.blurEnvelope(at: duration + 0.1, transitionDuration: duration), 0)
        }
        XCTAssertEqual(transition.blurEnvelope(at: 0.125, transitionDuration: 0.15), 1, accuracy: 0.00001)
        XCTAssertEqual(transition.blurEnvelope(at: 0.15, transitionDuration: 0.15), 0)
        XCTAssertEqual(transition.blurEnvelope(at: 0.025, transitionDuration: 0.05), 0)
    }

    func testInterruptedLiveBlurClearsBeforeSpringFinishes() throws {
        let canvas = CGSize(width: 640, height: 360)
        var camera = defaultFacecamSettings(enabled: true)
        let a = CameraLayoutPresentation.layout(camera, canvas: canvas, crop: .init(origin: .zero, size: canvas), styling: .none)
        camera.layout = CameraLayout.split.rawValue
        let b = CameraLayoutPresentation.layout(camera, canvas: canvas, crop: .init(origin: .zero, size: canvas), styling: .none)
        var live = CameraLayoutLiveMotion()
        let transition = CameraLayoutTransition(duration: 1.5, motion: .spring, blur: 1)
        live.retarget(a, at: 0, animated: false)
        live.retarget(b, at: 1, animated: true, transition: transition)
        let blurred = try XCTUnwrap(live.value(at: 1.1))
        XCTAssertEqual(blurred.transitionBlur, 1, accuracy: 0.00001)
        live.retarget(a, at: 1.1, animated: true, transition: transition)
        XCTAssertEqual(live.value(at: 1.1), blurred)
        XCTAssertEqual(live.value(at: 1.4)?.transitionBlur, 0)
        XCTAssertTrue(live.isAnimating(at: 1.4))
        XCTAssertEqual(live.value(at: 2.7), a)
    }
}
