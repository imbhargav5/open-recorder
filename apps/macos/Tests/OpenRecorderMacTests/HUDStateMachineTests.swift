import XCTest
@testable import OpenRecorderMac

@MainActor
final class HUDStateMachineTests: XCTestCase {
    func testIdleAndChoosingModeDoNotOccupyCaptureSlot() {
        let states: [HUDState] = [.idle, .choosingMode]

        for state in states {
            XCTAssertNil(state.mode)
            XCTAssertNil(state.source)
            XCTAssertFalse(state.isCaptureOccupied)
            XCTAssertEqual(state.captureFlow, .choice)
            XCTAssertEqual(state.presentation, .visible)
        }
    }

    func testPresentationDoesNotChangeCaptureDerivedState() {
        let source = makeSource()
        let visible = HUDState(phase: .recording(source), presentation: .visible)
        let hidden = visible.withPresentation(.hidden)

        XCTAssertEqual(hidden.phase, visible.phase)
        XCTAssertEqual(hidden.presentation, .hidden)
        XCTAssertEqual(hidden.mode, visible.mode)
        XCTAssertEqual(hidden.source, visible.source)
        XCTAssertEqual(hidden.captureFlow, visible.captureFlow)
        XCTAssertEqual(hidden.isCaptureOccupied, visible.isCaptureOccupied)
    }

    func testSourceSetupStatesDeriveModeAndCaptureFlow() {
        let source = makeSource()

        let recording = HUDState.setup(.recording, source: source)
        XCTAssertEqual(recording.source, source)
        XCTAssertEqual(recording.mode, .recording)
        XCTAssertEqual(recording.captureFlow, .recordingSetup)
        XCTAssertFalse(recording.isCaptureOccupied)

        let selecting = HUDState.sourceSelecting(.screenshot, source: source)
        XCTAssertEqual(selecting.source, source)
        XCTAssertEqual(selecting.mode, .screenshot)
        XCTAssertEqual(selecting.captureFlow, .screenshotSetup)
        XCTAssertTrue(selecting.isCaptureOccupied)
    }

    func testAreaSelectionPreservesCaptureMode() {
        XCTAssertEqual(HUDState.areaSelecting(.recording).mode, .recording)
        XCTAssertEqual(HUDState.areaSelecting(.recording).captureFlow, .recordingSetup)
        XCTAssertTrue(HUDState.areaSelecting(.recording).isCaptureOccupied)

        XCTAssertEqual(HUDState.areaSelecting(.screenshot).mode, .screenshot)
        XCTAssertEqual(HUDState.areaSelecting(.screenshot).captureFlow, .screenshotSetup)
        XCTAssertTrue(HUDState.areaSelecting(.screenshot).isCaptureOccupied)
    }

    func testRecordingStatesExposeRecordingModeSourceAndFlow() {
        let source = makeSource()
        let states: [HUDState] = [
            .countingDownRecording(source),
            .startingRecording(source),
            .recording(source),
            .stoppingRecording(source)
        ]

        for state in states {
            XCTAssertEqual(state.mode, .recording)
            XCTAssertEqual(state.source, source)
            XCTAssertEqual(state.captureFlow, .recording)
            XCTAssertTrue(state.isCaptureOccupied)
        }
    }

    func testCountdownStateCanBeHiddenWithoutReleasingCaptureSlot() {
        let source = makeSource()
        let state = HUDState.countingDownRecording(source).withPresentation(.hidden)

        XCTAssertEqual(state.mode, .recording)
        XCTAssertEqual(state.source, source)
        XCTAssertEqual(state.captureFlow, .recording)
        XCTAssertTrue(state.isCaptureOccupied)
        XCTAssertEqual(state.presentation, .hidden)
    }

    func testActiveCaptureStatesForceHiddenPresentation() {
        let source = makeSource()
        let phases: [HUDPhase] = [
            .countingDownRecording(source),
            .startingRecording(source, stopRequested: false),
            .recording(source),
            .stoppingRecording(source),
            .capturingScreenshot(source)
        ]

        for phase in phases {
            let state = HUDState(phase: phase, presentation: .visible)

            XCTAssertTrue(state.requiresHiddenCaptureUI)
            XCTAssertEqual(state.presentation, .hidden)
            XCTAssertEqual(state.withPresentation(.visible).presentation, .hidden)
        }
    }

    func testScreenshotCaptureStateExposesScreenshotModeSourceAndFlow() {
        let source = makeSource()
        let state = HUDState.capturingScreenshot(source)

        XCTAssertEqual(state.mode, .screenshot)
        XCTAssertEqual(state.source, source)
        XCTAssertEqual(state.captureFlow, .screenshotSetup)
        XCTAssertTrue(state.isCaptureOccupied)
    }

    func testBeginCaptureWithExistingSourceReusesItInSetup() {
        let model = AppModel()
        let source = makeSource()
        model.setCaptureStateForTesting(CaptureState(phase: .choosingMode, selectedSource: source))

        model.beginCapture(.recording)

        XCTAssertEqual(model.hudState.phase, .setup(.recording))
        XCTAssertEqual(model.selectedSource, source)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertTrue(model.canStartNewCapture)
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testDuplicateCaptureRequestDuringReadyStatePreservesExistingModeAndFocusesSelector() {
        let model = AppModel()
        let source = makeSource(id: "window:1", kind: .window)
        model.setCaptureStateForTesting(.ready(.recording, source))

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.hudState, .ready(.recording, source))
        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.statusMessage, "Finish or cancel the current capture before starting another.")
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testDuplicateCaptureRequestDuringReadyScreenStateFocusesHUD() {
        let model = AppModel()
        let source = makeSource()
        model.setCaptureStateForTesting(.ready(.recording, source))

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.hudState, .ready(.recording, source))
        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.statusMessage, "Finish or cancel the current capture before starting another.")
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testDuplicateCaptureRequestDuringActiveRecordingStateKeepsCaptureUIHidden() {
        let model = AppModel()
        let source = makeSource()
        model.setCaptureStateForTesting(HUDState(phase: .recording(source), presentation: .hidden))

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.hudState.phase, .recording(source))
        XCTAssertEqual(model.hudState.presentation, .hidden)
        XCTAssertNil(model.windowCommand)
    }

    func testHUDPresentationTransitionsPreserveCapturePhase() {
        let model = AppModel()
        let source = makeSource()
        model.setCaptureStateForTesting(HUDState(phase: .ready(.recording, source), presentation: .visible))

        model.hideHUD()

        XCTAssertEqual(model.hudState.phase, .ready(.recording, source))
        XCTAssertEqual(model.hudState.presentation, .hidden)
        XCTAssertEqual(model.windowCommand?.action, .hideHUD)

        model.showHUD()

        XCTAssertEqual(model.hudState.phase, .ready(.recording, source))
        XCTAssertEqual(model.hudState.presentation, .visible)
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testShowHUDDuringActiveCaptureKeepsCaptureUIHidden() {
        let model = AppModel()
        let source = makeSource()
        model.setCaptureStateForTesting(HUDState(phase: .recording(source), presentation: .hidden))

        model.showHUD()

        XCTAssertEqual(model.hudState.phase, .recording(source))
        XCTAssertEqual(model.hudState.presentation, .hidden)
        XCTAssertNil(model.windowCommand)
    }

    func testToggleHUDPresentationSwitchesBetweenHiddenAndVisible() {
        let model = AppModel()

        model.toggleHUDPresentation()

        XCTAssertEqual(model.hudState.presentation, .hidden)
        XCTAssertEqual(model.windowCommand?.action, .hideHUD)

        model.toggleHUDPresentation()

        XCTAssertEqual(model.hudState.presentation, .visible)
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testAreaSelectionBlocksNewCapturesUntilCanceled() {
        let model = AppModel()

        model.beginCapture(.screenshot)
        model.requestInteractiveAreaSelection()

        XCTAssertEqual(model.hudState.phase, .areaSelecting(.screenshot))
        XCTAssertNil(model.selectedSource)
        XCTAssertTrue(model.isAreaSelectionActive)
        XCTAssertFalse(model.canStartNewCapture)

        model.beginCapture(.recording)

        XCTAssertEqual(model.hudState.phase, .areaSelecting(.screenshot))
        XCTAssertNil(model.selectedSource)
        XCTAssertEqual(model.captureMode, .screenshot)
        XCTAssertEqual(model.windowCommand?.action, .showAreaSelector)

        model.cancelInteractiveAreaSelection()

        XCTAssertEqual(model.hudState, .setup(.screenshot, preferredSourceKind: .area))
        XCTAssertFalse(model.isAreaSelectionActive)
        XCTAssertTrue(model.canStartNewCapture)
        XCTAssertNotEqual(model.windowCommand?.action, .showSourceSelector)
        XCTAssertNotEqual(model.windowCommand?.action, .closeAreaSelector)
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testEditorHandoffReleasesRecordingAndScreenshotStates() {
        let source = makeSource()
        let videoSession = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/example-recording.mp4"))
        let screenshotSession = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/example-screenshot.png"))

        let recordingModel = AppModel()
        recordingModel.setCaptureStateForTesting(.stoppingRecording(source))
        recordingModel.showEditor(for: videoSession)

        XCTAssertEqual(recordingModel.hudState, .setup(.recording, source: source))
        XCTAssertTrue(recordingModel.canStartNewCapture)
        XCTAssertEqual(recordingModel.windowCommand?.action, .showStudio)

        let screenshotModel = AppModel()
        screenshotModel.setCaptureStateForTesting(.capturingScreenshot(source))
        screenshotModel.showEditor(for: screenshotSession)

        XCTAssertEqual(screenshotModel.hudState, .setup(.screenshot, source: source))
        XCTAssertTrue(screenshotModel.canStartNewCapture)
        XCTAssertEqual(screenshotModel.windowCommand?.action, .showStudio)
    }

    private func makeSource(
        id: String = "display:1",
        kind: CaptureSourceKind = .display
    ) -> CaptureSource {
        CaptureSource(
            id: id,
            kind: kind,
            name: "Display 1",
            subtitle: "Built-in",
            displayIndex: 1,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
    }
}
