import XCTest
@testable import OpenRecorderMac

@MainActor
final class AppModelStateTests: XCTestCase {
    func testBeginRecordingMovesToSetupAndRequestsSelector() {
        let model = AppModel()

        model.beginCapture(.recording)

        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertEqual(model.hudState, .selectingSource(.recording))
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testBeginScreenshotMovesToSetupAndRequestsSelector() {
        let model = AppModel()

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.captureMode, .screenshot)
        XCTAssertEqual(model.captureFlow, .screenshotSetup)
        XCTAssertEqual(model.hudState, .selectingSource(.screenshot))
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testNewCaptureIsDisabledDuringRecordingSetup() {
        let model = AppModel()

        model.beginCapture(.recording)

        XCTAssertFalse(model.canStartNewCapture)

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertEqual(model.hudState, .selectingSource(.recording))
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testNewCaptureIsDisabledDuringScreenshotSetup() {
        let model = AppModel()

        model.beginCapture(.screenshot)

        XCTAssertFalse(model.canStartNewCapture)

        model.beginCapture(.recording)

        XCTAssertEqual(model.captureMode, .screenshot)
        XCTAssertEqual(model.captureFlow, .screenshotSetup)
        XCTAssertEqual(model.hudState, .selectingSource(.screenshot))
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testNewCaptureIsDisabledOnlyWhileRecording() {
        let model = AppModel()

        XCTAssertTrue(model.canStartNewCapture)

        model.capture.setRecordingForTesting(true)

        XCTAssertFalse(model.canStartNewCapture)
    }

    func testNewCaptureIsDisabledDuringRecordingTransitions() {
        let model = AppModel()

        model.recordingPhase = .starting
        XCTAssertFalse(model.canStartNewCapture)

        model.recordingPhase = .countingDown
        XCTAssertFalse(model.canStartNewCapture)

        model.recordingPhase = .stopping
        XCTAssertFalse(model.canStartNewCapture)

        model.recordingPhase = .idle
        XCTAssertTrue(model.canStartNewCapture)
    }

    func testActiveHUDStatesDisableNewCaptures() {
        let source = CaptureSource(
            id: "display:1",
            kind: .display,
            name: "Display 1",
            subtitle: "Built-in",
            displayIndex: 1,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
        let occupiedStates: [HUDState] = [
            .ready(.recording, source),
            .areaSelecting(.screenshot),
            .countingDownRecording(source),
            .startingRecording(source),
            .recording(source),
            .stoppingRecording(source),
            .capturingScreenshot(source)
        ]

        for state in occupiedStates {
            let model = AppModel()

            model.hudState = state

            XCTAssertFalse(model.canStartNewCapture, "\(state) should occupy the capture slot")
        }
    }

    func testShowEditorCarriesIndependentEditorSession() {
        let model = AppModel()
        let url = URL(fileURLWithPath: "/tmp/example-recording.mp4")
        let session = EditorSession(kind: .video, url: url, title: "Example Recording")
        model.beginCapture(.recording)

        model.showEditor(for: session)

        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertEqual(model.lastEditorSession, session)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertTrue(model.canStartNewCapture)
        XCTAssertEqual(model.windowCommand?.action, .showStudio)
        XCTAssertEqual(model.windowCommand?.editorSession, session)
    }

    func testEditorSessionDefaultTitleOmitsFileExtension() {
        let videoSession = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/example-recording.mp4"))
        let screenshotSession = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/example-screenshot.png"))

        XCTAssertEqual(videoSession.title, "example-recording")
        XCTAssertEqual(videoSession.displayTitle, "example-recording")
        XCTAssertEqual(screenshotSession.title, "example-screenshot")
        XCTAssertEqual(screenshotSession.displayTitle, "example-screenshot")
    }

    func testEditorSessionDisplayTitleStripsMatchingProvidedExtension() {
        let url = URL(fileURLWithPath: "/tmp/example-recording.mp4")
        let session = EditorSession(kind: .video, url: url, title: "Example Recording.mov")
        let dottedTitleSession = EditorSession(kind: .video, url: url, title: "Example Recording v1.2")

        XCTAssertEqual(session.title, "Example Recording.mov")
        XCTAssertEqual(session.displayTitle, "Example Recording")
        XCTAssertEqual(dottedTitleSession.displayTitle, "Example Recording v1.2")
    }

    func testEditorMediaKindTitleIconsMatchEditorType() {
        XCTAssertEqual(EditorMediaKind.video.titleIconSystemName, "video.fill")
        XCTAssertEqual(EditorMediaKind.screenshot.titleIconSystemName, "photo.fill")
    }

    func testSelectingSourceMovesHUDToReadyState() {
        let model = AppModel()
        let source = CaptureSource(
            id: "display:1",
            kind: .display,
            name: "Display 1",
            subtitle: "Built-in",
            displayIndex: 1,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )

        model.beginCapture(.recording)
        model.selectSource(source)

        XCTAssertEqual(model.hudState, .ready(.recording, source))
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertFalse(model.canStartNewCapture)
    }

    func testScreenshotEditorReleasesCaptureSlot() {
        let model = AppModel()
        let url = URL(fileURLWithPath: "/tmp/example-screenshot.png")
        let session = EditorSession(kind: .screenshot, url: url)

        model.beginCapture(.screenshot)
        model.showEditor(for: session)

        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertTrue(model.canStartNewCapture)
    }

    func testEditorSessionCanCarryRecordingSessionMetadata() {
        let url = URL(fileURLWithPath: "/tmp/example-recording.mp4")
        let recordingSession = RecordingSession(
            screenVideoPath: url.path,
            facecamVideoPath: "/tmp/example-recording.facecam.mov",
            facecamOffsetMs: 120,
            facecamSettings: defaultFacecamSettings(enabled: true),
            sourceName: "Display",
            showCursorOverlay: true,
            cursorTelemetryPath: "/tmp/example-recording.cursor.json"
        )

        let session = EditorSession(kind: .video, url: url, recordingSession: recordingSession)

        XCTAssertEqual(session.recordingSession, recordingSession)
        XCTAssertEqual(session.recordingSession?.facecamOffsetMs, 120)
        XCTAssertEqual(session.recordingSession?.cursorTelemetryPath, "/tmp/example-recording.cursor.json")
    }

    func testAreaSelectionUsesInteractiveAreaSource() {
        let model = AppModel()

        model.selectInteractiveAreaSource()

        XCTAssertEqual(model.selectedSource?.kind, .area)
        XCTAssertEqual(model.selectedSource?.id, "area:interactive")
        XCTAssertEqual(model.statusMessage, "Selected area")
    }

    func testSelectingMicrophoneDeviceEnablesMicrophoneAndStoresDevice() {
        let model = AppModel()
        model.microphoneDevices = [
            CaptureDeviceInfo(id: "mic-1", name: "Studio Mic", isDefault: false)
        ]

        model.selectMicrophoneDevice("mic-1")

        XCTAssertTrue(model.includeMicrophone)
        XCTAssertEqual(model.selectedMicrophoneDeviceID, "mic-1")
        XCTAssertEqual(model.selectedMicrophoneDeviceName, "Studio Mic")
        XCTAssertEqual(model.windowCommand?.action, .closeMicrophoneSelector)
    }

    func testSelectingCameraDeviceEnablesCameraAndStoresDevice() {
        let model = AppModel()
        model.cameraDevices = [
            CaptureDeviceInfo(id: "cam-1", name: "Desk Camera", isDefault: false)
        ]

        model.selectCameraDevice("cam-1")

        XCTAssertTrue(model.includeCamera)
        XCTAssertEqual(model.selectedCameraDeviceID, "cam-1")
        XCTAssertEqual(model.selectedCameraDeviceName, "Desk Camera")
        XCTAssertEqual(model.windowCommand?.action, .closeCameraSelector)
    }

    func testCancelingMicrophoneSelectorOpenedFromOffLeavesMicrophoneOff() {
        let model = AppModel()

        model.requestMicrophoneSelection(refreshDevices: false)
        model.cancelMicrophoneSelection()

        XCTAssertFalse(model.includeMicrophone)
        XCTAssertNil(model.selectedMicrophoneDeviceID)
        XCTAssertEqual(model.windowCommand?.action, .closeMicrophoneSelector)
    }

    func testCancelingCameraSelectorOpenedFromOffLeavesCameraOff() {
        let model = AppModel()

        model.requestCameraSelection(refreshDevices: false)
        model.cancelCameraSelection()

        XCTAssertFalse(model.includeCamera)
        XCTAssertNil(model.selectedCameraDeviceID)
        XCTAssertEqual(model.windowCommand?.action, .closeCameraSelector)
    }

    func testDisablingActiveCaptureDevicesPreservesSelectedDevices() {
        let model = AppModel()
        model.microphoneDevices = [
            CaptureDeviceInfo(id: "mic-1", name: "Studio Mic", isDefault: false)
        ]
        model.cameraDevices = [
            CaptureDeviceInfo(id: "cam-1", name: "Desk Camera", isDefault: false)
        ]
        model.selectMicrophoneDevice("mic-1")
        model.selectCameraDevice("cam-1")

        model.disableMicrophone()
        model.disableCamera()

        XCTAssertFalse(model.includeMicrophone)
        XCTAssertFalse(model.includeCamera)
        XCTAssertEqual(model.selectedMicrophoneDeviceID, "mic-1")
        XCTAssertEqual(model.selectedCameraDeviceID, "cam-1")
    }

    func testSelectingNoMicrophoneInputDisablesMicrophoneAndClosesSelector() {
        let model = AppModel()
        model.microphoneDevices = [
            CaptureDeviceInfo(id: "mic-1", name: "Studio Mic", isDefault: false)
        ]
        model.selectMicrophoneDevice("mic-1")

        model.selectNoMicrophoneInput()

        XCTAssertFalse(model.includeMicrophone)
        XCTAssertEqual(model.selectedMicrophoneDeviceID, "mic-1")
        XCTAssertEqual(model.statusMessage, "Microphone off")
        XCTAssertEqual(model.windowCommand?.action, .closeMicrophoneSelector)
    }

    func testSelectingNoCameraInputDisablesCameraAndClosesSelector() {
        let model = AppModel()
        model.cameraDevices = [
            CaptureDeviceInfo(id: "cam-1", name: "Desk Camera", isDefault: false)
        ]
        model.selectCameraDevice("cam-1")

        model.selectNoCameraInput()

        XCTAssertFalse(model.includeCamera)
        XCTAssertEqual(model.selectedCameraDeviceID, "cam-1")
        XCTAssertEqual(model.statusMessage, "Camera off")
        XCTAssertEqual(model.windowCommand?.action, .closeCameraSelector)
    }

    func testWindowCommandIsConsumedOnce() {
        let model = AppModel()
        model.requestWindow(.showStudio)

        let firstCommand = model.consumeWindowCommand(model.windowCommand)
        let secondCommand = model.consumeWindowCommand(model.windowCommand)

        XCTAssertEqual(firstCommand?.action, .showStudio)
        XCTAssertNil(secondCommand)
    }

    func testHideHUDWindowCommandIsConsumedOnce() {
        let model = AppModel()
        model.hideHUD()

        let firstCommand = model.consumeWindowCommand(model.windowCommand)
        let secondCommand = model.consumeWindowCommand(model.windowCommand)

        XCTAssertEqual(model.hudState.presentation, .hidden)
        XCTAssertEqual(firstCommand?.action, .hideHUD)
        XCTAssertNil(secondCommand)
    }

    func testRecordingShortcutCancelsCountdownAndRestoresReadyHUD() {
        let model = AppModel()
        let source = CaptureSource(
            id: "display:1",
            kind: .display,
            name: "Display 1",
            subtitle: "Built-in",
            displayIndex: 1,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
        model.selectedSource = source
        model.recordingPhase = .countingDown
        model.hudState = HUDState(phase: .countingDownRecording(source), presentation: .hidden)

        model.toggleRecordingShortcut()

        XCTAssertEqual(model.recordingPhase, .idle)
        XCTAssertEqual(model.hudState, .ready(.recording, source))
        XCTAssertEqual(model.hudState.presentation, .visible)
        XCTAssertEqual(model.statusMessage, "Recording canceled.")
        XCTAssertEqual(model.windowCommand?.action, .showRecordingSetup)
    }

    func testRecordingShortcutDuringStartingQueuesStop() {
        let model = AppModel()
        let source = CaptureSource(
            id: "display:1",
            kind: .display,
            name: "Display 1",
            subtitle: "Built-in",
            displayIndex: 1,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
        model.recordingPhase = .starting
        model.hudState = .startingRecording(source)

        model.toggleRecordingShortcut()

        XCTAssertEqual(model.recordingPhase, .starting)
        XCTAssertEqual(model.hudState, .startingRecording(source))
        XCTAssertEqual(model.statusMessage, "Recording will stop after it starts.")
    }

    func testAppWindowActionsOpenEditorCommandUsesEditorWindow() {
        let actions = AppWindowActions()
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/example-recording.mp4"),
            title: "Example Recording"
        )
        var openedWindows: [String] = []
        var openedEditorSession: EditorSession?
        var dismissedWindows: [String] = []

        actions.install(
            openWindow: { openedWindows.append($0) },
            openEditor: { openedEditorSession = $0 },
            dismissWindow: { dismissedWindows.append($0) },
            activateApp: {}
        )
        actions.perform(NativeWindowCommand(action: .showStudio, editorSession: session))

        XCTAssertTrue(actions.isInstalled)
        XCTAssertEqual(openedEditorSession, session)
        XCTAssertTrue(openedWindows.isEmpty)
        XCTAssertTrue(dismissedWindows.isEmpty)
    }

    func testAppWindowActionsHideRecordingSetupClosesCaptureWindows() {
        let actions = AppWindowActions()
        var openedWindows: [String] = []
        var dismissedWindows: [String] = []

        actions.install(
            openWindow: { openedWindows.append($0) },
            openEditor: { _ in },
            dismissWindow: { dismissedWindows.append($0) },
            activateApp: {}
        )
        actions.perform(NativeWindowCommand(action: .hideRecordingSetup))

        XCTAssertTrue(openedWindows.isEmpty)
        XCTAssertEqual(dismissedWindows, ["hud", "source-selector"])
    }
}
