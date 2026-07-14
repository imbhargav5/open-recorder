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
        XCTAssertEqual(recording.effects, [.showHUD])

        let screenshot = CaptureState.areaSelecting(.screenshot).applying(.completeInteractiveAreaSelection(source))
        XCTAssertEqual(screenshot.state.phase, .capturingScreenshot(source))
        XCTAssertEqual(screenshot.effects, [.dismissScreenSelection, .hideAppWindowsForCapture, .runScreenshotCapture(source)])
    }

    func testCaptureReadinessReportsTypedBlockersBeforeRuntimeWorkBegins() {
        let selected = makeSource(id: "window:chosen", kind: .window)
        let missingMicrophoneID = "mic:missing"
        let state = CaptureState.ready(.recording, selected)
        let options = CaptureOptionsState(
            includeMicrophone: true,
            includeCamera: true,
            microphoneDevices: [CaptureDeviceInfo(id: "mic:other", name: "Other Mic", isDefault: true)],
            cameraDevices: [],
            selectedMicrophoneDeviceID: missingMicrophoneID
        )

        let readiness = state.readiness(
            availableSources: [],
            screenRecordingPermissionState: .requestAlreadyShown,
            options: options,
            runtimeIsRecording: false
        )

        XCTAssertFalse(readiness.canCapture)
        XCTAssertEqual(readiness.source, selected)
        XCTAssertEqual(readiness.blockers, [
            .screenRecordingPermissionNeedsRestart,
            .sourceUnavailable(name: selected.name),
            .microphoneUnavailable(deviceID: missingMicrophoneID),
            .cameraUnavailable(deviceID: nil)
        ])
        XCTAssertEqual(readiness.primaryBlocker?.recoveryAction, .openScreenRecordingSettings)
    }

    func testCaptureReadinessSucceedsOnlyAfterSourcePermissionAndDevicesAreAvailable() {
        let selected = makeSource(id: "window:chosen", kind: .window)
        let options = CaptureOptionsState(
            includeMicrophone: true,
            includeCamera: true,
            microphoneDevices: [CaptureDeviceInfo(id: "mic:1", name: "Mic", isDefault: true)],
            cameraDevices: [CaptureDeviceInfo(id: "cam:1", name: "Camera", isDefault: true)],
            selectedMicrophoneDeviceID: "mic:1",
            selectedCameraDeviceID: "cam:1"
        )

        let ready = CaptureState.ready(.recording, selected).readiness(
            availableSources: [selected],
            screenRecordingPermissionState: .granted,
            options: options,
            runtimeIsRecording: false
        )
        let checking = CaptureState.ready(.recording, selected).readiness(
            availableSources: [selected],
            screenRecordingPermissionState: .granted,
            options: options,
            runtimeIsRecording: false,
            isChecking: true
        )

        XCTAssertTrue(ready.canCapture)
        XCTAssertEqual(ready.blockers, [])
        XCTAssertFalse(checking.canCapture)
        XCTAssertEqual(checking.blockers, [])
    }

    func testCaptureReadinessReportsDeniedMediaPermissionsBeforeDeviceAvailability() {
        let selected = makeSource()
        let options = CaptureOptionsState(
            includeMicrophone: true,
            includeCamera: true,
            microphoneDevices: [],
            cameraDevices: []
        )

        let readiness = CaptureState.ready(.recording, selected).readiness(
            availableSources: [selected],
            screenRecordingPermissionState: .granted,
            options: options,
            runtimeIsRecording: false,
            microphoneAuthorization: .denied,
            cameraAuthorization: .denied
        )

        XCTAssertEqual(readiness.blockers, [
            .microphonePermissionDenied,
            .cameraPermissionDenied
        ])
        XCTAssertEqual(readiness.blockers.map(\.recoveryAction), [
            .openMicrophoneSettings,
            .openCameraSettings
        ])
    }

    func testScreenshotReadinessIgnoresRecordingOnlyDeviceChoices() {
        let selected = makeSource()
        let options = CaptureOptionsState(
            includeMicrophone: true,
            includeCamera: true,
            microphoneDevices: [],
            cameraDevices: []
        )

        let readiness = CaptureState.ready(.screenshot, selected).readiness(
            availableSources: [selected],
            screenRecordingPermissionState: .granted,
            options: options,
            runtimeIsRecording: false
        )

        XCTAssertTrue(readiness.canCapture)
    }

    func testAreaReadinessRequiresCompletedGeometryButNotCatalogMembership() {
        let placeholder = makeSource(id: "area:interactive", kind: .area)
        var completed = placeholder
        completed.area = CaptureArea(x: 10, y: 20, width: 640, height: 360, displayID: 1)
        let options = CaptureOptionsState()

        let placeholderReadiness = CaptureState.ready(.recording, placeholder).readiness(
            availableSources: [],
            screenRecordingPermissionState: .granted,
            options: options,
            runtimeIsRecording: false
        )
        let completedReadiness = CaptureState.ready(.recording, completed).readiness(
            availableSources: [],
            screenRecordingPermissionState: .granted,
            options: options,
            runtimeIsRecording: false
        )

        XCTAssertEqual(placeholderReadiness.blockers, [.areaSelectionRequired])
        XCTAssertTrue(completedReadiness.canCapture)
    }

    func testCatalogRefreshNeverChoosesOrSilentlyReplacesASource() {
        let previous = makeSource(id: "display:2", kind: .display)
        let unrelated = makeSource(id: "display:1", kind: .display)

        let withoutSelection = CaptureState.selectingSource(.recording)
            .applying(.refreshSelectedSource(unrelated))
        XCTAssertNil(withoutSelection.state.selectedSource)
        XCTAssertEqual(withoutSelection.state.phase, .selectingSource(.recording))

        let missing = CaptureState.ready(.recording, previous)
            .applying(.refreshSelectedSource(unrelated))
        XCTAssertNil(missing.state.selectedSource)
        XCTAssertEqual(missing.state.phase, .selectingSource(.recording))
        XCTAssertEqual(missing.state.preferredSourceKind, .display)
        XCTAssertEqual(missing.statusMessage, "Display 1 is no longer available. Choose another source.")
    }

    func testCatalogRefreshUpdatesMatchingSourceMetadataAndPreservesInteractiveArea() {
        var previous = makeSource(id: "window:old", kind: .window)
        previous.ownerBundleID = "com.example.app"
        previous.windowID = 42
        var refreshed = previous
        refreshed.id = "window:new"
        refreshed.subtitle = "Updated"

        let updated = CaptureState.ready(.recording, previous)
            .applying(.refreshSelectedSource(refreshed))
        XCTAssertEqual(updated.state.phase, .ready(.recording, refreshed))

        var area = makeSource(id: "area:interactive", kind: .area)
        area.area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        let preserved = CaptureState.ready(.recording, area)
            .applying(.refreshSelectedSource(nil))
        XCTAssertEqual(preserved.state, CaptureState.ready(.recording, area))
    }

    func testCatalogRefreshDoesNotRetargetToSameTitleWindowWithDifferentWindowID() {
        var selected = makeSource(id: "window:selected", kind: .window)
        selected.name = "Document"
        selected.ownerBundleID = "com.example.editor"
        selected.windowID = 41
        var differentWindow = selected
        differentWindow.id = "window:different"
        differentWindow.windowID = 42

        let refreshed = CaptureState.ready(.recording, selected)
            .applying(.refreshSelectedSource(differentWindow))

        XCTAssertNil(refreshed.state.selectedSource)
        XCTAssertEqual(refreshed.state.phase, .selectingSource(.recording))
        XCTAssertEqual(refreshed.statusMessage, "Document is no longer available. Choose another source.")
    }

    func testCatalogRefreshCannotRewriteSourceDuringRuntimeCapture() {
        let source = makeSource()
        let states: [CaptureState] = [
            .countingDownRecording(source),
            .startingRecording(source),
            .recording(source),
            .stoppingRecording(source),
            .capturingScreenshot(source)
        ]

        for state in states {
            let transition = state.applying(.refreshSelectedSource(nil))
            XCTAssertEqual(transition.state, state)
            XCTAssertNil(transition.statusMessage)
        }
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
