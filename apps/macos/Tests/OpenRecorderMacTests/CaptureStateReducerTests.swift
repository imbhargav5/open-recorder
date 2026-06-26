import XCTest
@testable import OpenRecorderMac

final class CaptureStateReducerTests: XCTestCase {
    func testBeginCaptureMovesIdleFlowToSourceTypeChoice() {
        let transition = CaptureState.choosingMode.applying(.beginCapture(.recording, runtimeIsRecording: false))

        XCTAssertEqual(transition.state.phase, .choosingSourceType(.recording))
        XCTAssertEqual(transition.state.captureFlow, .recordingSetup)
        XCTAssertEqual(transition.effects, [.dismissScreenSelection, .showHUD])
        XCTAssertEqual(transition.statusMessage, "Choose a source type.")
    }

    func testDuplicateBeginCaptureFocusesExistingFlowWithoutChangingState() {
        let source = makeSource(kind: .window)
        let state = CaptureState.ready(.recording, source)

        let transition = state.applying(.beginCapture(.screenshot, runtimeIsRecording: false))

        XCTAssertEqual(transition.state, state)
        XCTAssertEqual(transition.effects, [.focusActiveCaptureWindow])
        XCTAssertEqual(transition.statusMessage, "Finish or cancel the current capture before starting another.")
    }

    func testRecordingHotKeyRegistersOnlyForRecordingReadyAndActiveStates() {
        let source = makeSource()

        let enabledStates: [CaptureState] = [
            CaptureState.ready(.recording, source),
            .countingDownRecording(source),
            .startingRecording(source),
            .recording(source)
        ]

        for state in enabledStates {
            XCTAssertTrue(state.shouldRegisterRecordingHotKey(runtimeIsRecording: false), "\(state.phase) should register Cmd-R")
        }

        let disabledStates: [CaptureState] = [
            CaptureState.idle,
            .choosingMode,
            .choosingSourceType(.recording),
            .screenSelecting(.recording),
            .selectingSource(.recording),
            .ready(.screenshot, source),
            .areaSelecting(.recording),
            .stoppingRecording(source),
            .capturingScreenshot(source)
        ]

        for state in disabledStates {
            XCTAssertFalse(state.shouldRegisterRecordingHotKey(runtimeIsRecording: false), "\(state.phase) should not register Cmd-R")
        }
    }

    func testRecordingHotKeyStaysRegisteredWhenRuntimeIsRecording() {
        let source = makeSource()

        XCTAssertTrue(CaptureState.choosingMode.shouldRegisterRecordingHotKey(runtimeIsRecording: true))
        XCTAssertTrue(CaptureState.stoppingRecording(source).shouldRegisterRecordingHotKey(runtimeIsRecording: true))
    }

    func testChoosingSourceTypesMovesToDeclarativeSelectionStates() {
        let screen = CaptureState.choosingSourceType(.screenshot).applying(.chooseSourceType(.screen))
        XCTAssertEqual(screen.state.phase, .screenSelecting(.screenshot))
        XCTAssertEqual(screen.state.preferredSourceKind, .display)
        XCTAssertEqual(screen.effects, [.dismissScreenSelection])

        let window = CaptureState.choosingSourceType(.recording).applying(.chooseSourceType(.window))
        XCTAssertEqual(window.state.phase, .selectingSource(.recording))
        XCTAssertEqual(window.state.preferredSourceKind, .window)
        XCTAssertEqual(window.effects, [.showSourceSelector])

        let area = CaptureState.choosingSourceType(.screenshot).applying(.chooseSourceType(.area))
        XCTAssertEqual(area.state.phase, .selectingSource(.screenshot))
        XCTAssertEqual(area.state.preferredSourceKind, .area)
        XCTAssertEqual(area.effects, [.showSourceSelector])
    }

    func testSelectingSourceMovesToReadyAndFlashesDisplays() {
        let source = makeSource()

        let transition = CaptureState.selectingSource(.recording).applying(.selectSource(source))

        XCTAssertEqual(transition.state.phase, .ready(.recording, source))
        XCTAssertEqual(transition.state.source, source)
        XCTAssertEqual(transition.state.preferredSourceKind, .display)
        XCTAssertEqual(transition.effects, [.flashDisplay(source)])
        XCTAssertEqual(transition.statusMessage, "Selected Display 1")
    }

    func testAreaSelectionRequestCompletionAndCancellation() {
        let areaSource = makeSource(id: "area:interactive", kind: .area)
        let requested = CaptureState.choosingSourceType(.screenshot).applying(.requestInteractiveAreaSelection)

        XCTAssertEqual(requested.state.phase, .areaSelecting(.screenshot))
        XCTAssertTrue(requested.state.isAreaSelectionActive)
        XCTAssertEqual(requested.effects, [.showAreaSelector])

        let completed = requested.state.applying(.completeInteractiveAreaSelection(areaSource))
        XCTAssertEqual(completed.state.phase, .capturingScreenshot(areaSource))
        XCTAssertFalse(completed.state.isAreaSelectionActive)
        XCTAssertEqual(completed.effects, [.dismissScreenSelection, .hideAppWindowsForCapture, .runScreenshotCapture(areaSource)])
        XCTAssertEqual(completed.statusMessage, "Selected area")

        let canceled = requested.state.applying(.cancelCapture)
        XCTAssertEqual(canceled.state.phase, .choosingMode)
        XCTAssertFalse(canceled.state.isAreaSelectionActive)
        XCTAssertTrue(canceled.effects.contains(.closeCaptureSetup))
    }

    func testRecordingFlowTracksCountdownStartingQueuedStopRecordingAndRestore() {
        let source = makeSource()
        let outputURL = URL(fileURLWithPath: "/tmp/example-recording.mp4")
        let requested = CaptureState.ready(.recording, source).applying(.recordingStartRequested)

        XCTAssertEqual(requested.state.phase, .ready(.recording, source))
        XCTAssertEqual(requested.effects, [.prepareRecordingFile(source)])

        let countdown = requested.state.applying(.recordingFilePrepared(source, outputURL))

        XCTAssertEqual(countdown.state.phase, .countingDownRecording(source))
        XCTAssertEqual(countdown.state.presentation, .hidden)
        XCTAssertEqual(countdown.effects, [.dismissScreenSelection, .hideAppWindowsForCapture, .runRecordingStart(source, outputURL)])

        let canceled = countdown.state.applying(.recordingStopRequested)
        XCTAssertEqual(canceled.state.phase, .ready(.recording, source))
        XCTAssertEqual(canceled.state.presentation, .visible)
        XCTAssertEqual(canceled.effects, [.cancelRecordingStart, .showRecordingSetup(.display)])

        let starting = countdown.state.applying(.recordingStarting(source))
        XCTAssertEqual(starting.state.phase, .startingRecording(source, stopRequested: false))
        XCTAssertEqual(starting.state.presentation, .hidden)
        XCTAssertEqual(starting.effects, [.dismissScreenSelection, .hideAppWindowsForCapture])

        let queuedStop = starting.state.applying(.recordingStopRequested)
        XCTAssertEqual(queuedStop.state.phase, .startingRecording(source, stopRequested: true))
        XCTAssertEqual(queuedStop.statusMessage, "Recording will stop after it starts.")

        let recording = queuedStop.state.applying(.recordingStarted(source))
        XCTAssertEqual(recording.state.phase, .recording(source))
        XCTAssertEqual(recording.state.presentation, .hidden)
        XCTAssertEqual(recording.statusMessage, "Recording Display 1")
        XCTAssertEqual(recording.effects, [.dismissScreenSelection, .hideAppWindowsForCapture])

        let stopping = recording.state.applying(.recordingStopRequested)
        XCTAssertEqual(stopping.state.phase, .stoppingRecording(source))
        XCTAssertEqual(stopping.effects, [.dismissCaptureWindows, .stopRecording(source)])

        let restored = stopping.state.applying(.recordingRestored(source, message: "Recording canceled."))
        XCTAssertEqual(restored.state.phase, .ready(.recording, source))
        XCTAssertEqual(restored.state.presentation, .visible)
        XCTAssertEqual(restored.effects, [.showRecordingSetup(.display)])

        let stopped = stopping.state.applying(.recordingStopped(message: "Recording stopped before a file was written."))
        XCTAssertEqual(stopped.state.phase, .choosingMode)
        XCTAssertEqual(stopped.statusMessage, "Recording stopped before a file was written.")
    }

    func testScreenshotFlowTracksCaptureSuccessFailureAndCancellation() {
        let source = makeSource()
        let capturing = CaptureState.ready(.screenshot, source).applying(.screenshotRequested)

        XCTAssertEqual(capturing.state.phase, .capturingScreenshot(source))
        XCTAssertEqual(capturing.state.presentation, .hidden)
        XCTAssertEqual(capturing.effects, [.dismissScreenSelection, .hideAppWindowsForCapture, .runScreenshotCapture(source)])

        let failed = capturing.state.applying(.screenshotRestored(source, message: "No screen"))
        XCTAssertEqual(failed.state.phase, .ready(.screenshot, source))
        XCTAssertEqual(failed.state.presentation, .visible)
        XCTAssertEqual(failed.effects, [.showHUD])
        XCTAssertEqual(failed.statusMessage, "No screen")

        let succeeded = capturing.state.applying(.screenshotSucceeded)
        XCTAssertEqual(succeeded.state.phase, .choosingMode)
        XCTAssertEqual(succeeded.state.presentation, .visible)
        XCTAssertTrue(succeeded.effects.contains(.cancelScreenshotCapture))

        let canceled = capturing.state.applying(.cancelCapture)
        XCTAssertEqual(canceled.state.phase, .choosingMode)
        XCTAssertTrue(canceled.effects.contains(.cancelScreenshotCapture))

        let screenshotCanceled = capturing.state.applying(.screenshotCanceled)
        XCTAssertEqual(screenshotCanceled.state.phase, .choosingMode)
        XCTAssertTrue(screenshotCanceled.effects.contains(.cancelScreenshotCapture))
    }

    func testCompletingInteractiveAreaStartsRuntimeCaptureForActiveMode() {
        let source = makeSource(id: "area:interactive", kind: .area)

        let recording = CaptureState.areaSelecting(.recording).applying(.completeInteractiveAreaSelection(source))
        XCTAssertEqual(recording.state.phase, .ready(.recording, source))
        XCTAssertEqual(recording.effects, [.prepareRecordingFile(source)])

        let screenshot = CaptureState.areaSelecting(.screenshot).applying(.completeInteractiveAreaSelection(source))
        XCTAssertEqual(screenshot.state.phase, .capturingScreenshot(source))
        XCTAssertEqual(screenshot.effects, [.dismissScreenSelection, .hideAppWindowsForCapture, .runScreenshotCapture(source)])
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
            displayIndex: kind == .display ? 1 : nil,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
    }
}
