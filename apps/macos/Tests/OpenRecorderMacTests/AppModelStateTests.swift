import XCTest
@testable import OpenRecorderMac

@MainActor
final class AppModelStateTests: XCTestCase {
    func testBeginRecordingMovesToSourceTypeChoiceAndRequestsHUD() {
        let model = AppModel()

        model.beginCapture(.recording)

        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertEqual(model.hudState, .choosingSourceType(.recording))
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testBeginScreenshotMovesToSourceTypeChoiceAndRequestsHUD() {
        let model = AppModel()

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.captureMode, .screenshot)
        XCTAssertEqual(model.captureFlow, .screenshotSetup)
        XCTAssertEqual(model.hudState, .choosingSourceType(.screenshot))
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testChoosingWindowSourceTypeOpensSourceSelectorOnWindowTab() {
        let model = AppModel()

        model.beginCapture(.recording)
        model.chooseSourceType(.window)

        XCTAssertEqual(model.hudState, .selectingSource(.recording))
        XCTAssertEqual(model.preferredSourceSelectorKind, .window)
        XCTAssertEqual(model.statusMessage, "Choose a window.")
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testChoosingAreaSourceTypeOpensSourceSelectorOnAreaTab() {
        let model = AppModel()

        model.beginCapture(.screenshot)
        model.chooseSourceType(.area)

        XCTAssertEqual(model.hudState, .selectingSource(.screenshot))
        XCTAssertEqual(model.preferredSourceSelectorKind, .area)
        XCTAssertEqual(model.statusMessage, "Choose an area.")
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testCancelRecordingSetupReturnsToChoiceAndClosesCaptureSetup() {
        let model = AppModel()

        model.beginCapture(.recording)
        model.cancelCapture()

        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertFalse(model.isAreaSelectionActive)
        XCTAssertEqual(model.windowCommand?.action, .closeCaptureSetup)
    }

    func testCancelScreenshotSetupReturnsToChoiceAndClosesCaptureSetup() {
        let model = AppModel()

        model.beginCapture(.screenshot)
        model.cancelCapture()

        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertFalse(model.isAreaSelectionActive)
        XCTAssertEqual(model.windowCommand?.action, .closeCaptureSetup)
    }

    func testCancelReadySetupDoesNotLeaveSelectorOrAreaCloseCommand() {
        let model = AppModel()
        let source = makeSource()
        model.selectedSource = source

        model.beginCapture(.recording)
        model.cancelCapture()

        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertNotEqual(model.windowCommand?.action, .showSourceSelector)
        XCTAssertNotEqual(model.windowCommand?.action, .closeAreaSelector)
        XCTAssertEqual(model.windowCommand?.action, .closeCaptureSetup)
    }

    func testNewCaptureIsDisabledDuringRecordingSetup() {
        let model = AppModel()

        model.beginCapture(.recording)

        XCTAssertFalse(model.canStartNewCapture)

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertEqual(model.hudState, .choosingSourceType(.recording))
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testNewCaptureIsDisabledDuringScreenshotSetup() {
        let model = AppModel()

        model.beginCapture(.screenshot)

        XCTAssertFalse(model.canStartNewCapture)

        model.beginCapture(.recording)

        XCTAssertEqual(model.captureMode, .screenshot)
        XCTAssertEqual(model.captureFlow, .screenshotSetup)
        XCTAssertEqual(model.hudState, .choosingSourceType(.screenshot))
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
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
            .choosingSourceType(.recording),
            .screenSelecting(.screenshot),
            .selectingSource(.recording),
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

    func testChoosingScreenSourceTypePresentsDisplayOverlay() {
        let presenter = ScreenSelectionPresenterSpy()
        let model = AppModel(screenSelectionPresenter: presenter)
        let source = makeSource(displayID: 42)
        model.capture.setSourcesForTesting([source])

        model.beginCapture(.screenshot)
        model.chooseSourceType(.screen)

        XCTAssertEqual(model.hudState, .screenSelecting(.screenshot))
        XCTAssertEqual(model.preferredSourceSelectorKind, .display)
        XCTAssertEqual(presenter.presentedSources, [source])
        XCTAssertNotNil(presenter.onSelect)
        XCTAssertNotNil(presenter.onCancel)
    }

    func testChoosingScreenSelectsDisplayAndReturnsReadyHUD() {
        let presenter = ScreenSelectionPresenterSpy()
        let model = AppModel(screenSelectionPresenter: presenter)
        let source = makeSource(displayID: 42)
        model.capture.setSourcesForTesting([source])

        model.beginCapture(.recording)
        model.chooseSourceType(.screen)
        presenter.select(source)

        XCTAssertEqual(model.hudState, .ready(.recording, source))
        XCTAssertEqual(model.selectedSource, source)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
        XCTAssertGreaterThanOrEqual(presenter.dismissCallCount, 1)
    }

    func testCancelingScreenSelectionReturnsToSourceTypeChoice() {
        let presenter = ScreenSelectionPresenterSpy()
        let model = AppModel(screenSelectionPresenter: presenter)
        let source = makeSource(displayID: 42)
        model.capture.setSourcesForTesting([source])

        model.beginCapture(.recording)
        model.chooseSourceType(.screen)
        presenter.cancel()

        XCTAssertEqual(model.hudState, .choosingSourceType(.recording))
        XCTAssertEqual(model.statusMessage, "Choose a source type.")
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
        XCTAssertGreaterThanOrEqual(presenter.dismissCallCount, 1)
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

    func testAreaScreenshotCompletionOpensEditorEvenIfScreenshotIndexingFails() throws {
        var capturedSources: [CaptureSource] = []
        let screenshotsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-recorder-screenshots-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: screenshotsDir)
        }
        let paths = AppPaths(
            recordingsDir: screenshotsDir.path,
            screenshotsDir: screenshotsDir.path,
            projectsDir: screenshotsDir.path,
            supportDir: screenshotsDir.path
        )
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            screenshotCapture: { source, outputURL in
                capturedSources.append(source)
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard FileManager.default.createFile(atPath: outputURL.path, contents: Data("png".utf8)) else {
                    throw TestScreenshotError.writeFailed
                }
            },
            rememberScreenshot: { _ in
                throw TestScreenshotError.rememberFailed
            }
        )
        let area = CaptureArea(x: 24, y: 48, width: 320, height: 180, displayID: 7)

        model.paths = paths
        model.beginCapture(.screenshot)
        model.requestInteractiveAreaSelection()
        model.completeInteractiveAreaSelection(area)

        let editorSession = try XCTUnwrap(model.windowCommand?.editorSession)
        let screenshotURL = try XCTUnwrap(model.currentScreenshotURL)
        XCTAssertEqual(capturedSources.first?.area, area)
        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertTrue(model.canStartNewCapture)
        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertEqual(model.windowCommand?.action, .showStudio)
        XCTAssertEqual(editorSession.kind, .screenshot)
        XCTAssertEqual(editorSession.url, screenshotURL)
        XCTAssertTrue(screenshotURL.path.hasPrefix(screenshotsDir.path))
        XCTAssertEqual(model.statusMessage, "Captured \(screenshotURL.lastPathComponent)")
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

    func testSystemAudioToggleUpdatesRecordingOptionState() {
        let model = AppModel()

        XCTAssertFalse(model.includeSystemAudio)
        XCTAssertTrue(model.canChangeRecordingOptions)

        model.toggleSystemAudio()

        XCTAssertTrue(model.includeSystemAudio)
        XCTAssertEqual(model.statusMessage, "System audio on")

        model.toggleSystemAudio()

        XCTAssertFalse(model.includeSystemAudio)
        XCTAssertEqual(model.statusMessage, "System audio off")
    }

    func testSystemAudioToggleIsLockedDuringActiveRecording() {
        let model = AppModel()
        model.includeSystemAudio = true
        model.recordingPhase = .recording
        model.capture.setRecordingForTesting(true)

        XCTAssertFalse(model.canChangeRecordingOptions)

        model.toggleSystemAudio()

        XCTAssertTrue(model.includeSystemAudio)
        XCTAssertEqual(model.statusMessage, "System audio is on for this recording.")
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

    func testIncompleteOnboardingRequestsOnboardingWindow() {
        let completion = OnboardingCompletionBox(false)
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            accessibilityPermission: makeAccessibilityPermission(isTrusted: false),
            onboardingStore: completion.store
        )

        model.presentOnboardingIfNeeded()

        XCTAssertEqual(model.windowCommand?.action, .showOnboarding)
        XCTAssertEqual(model.hudState.presentation, .hidden)
    }

    func testCompletedOnboardingDoesNotRequestOnboardingWindow() {
        let completion = OnboardingCompletionBox(true)
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            accessibilityPermission: makeAccessibilityPermission(isTrusted: false),
            onboardingStore: completion.store
        )

        model.presentOnboardingIfNeeded()

        XCTAssertNil(model.windowCommand)
    }

    func testOnboardingCannotCompleteWithoutScreenRecordingPermission() {
        let completion = OnboardingCompletionBox(false)
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: false),
            accessibilityPermission: makeAccessibilityPermission(isTrusted: true),
            onboardingStore: completion.store
        )

        let didComplete = model.completeOnboarding()

        XCTAssertFalse(didComplete)
        XCTAssertFalse(completion.value)
        XCTAssertNil(model.windowCommand)
        XCTAssertEqual(model.onboardingStatusMessage, "Screen Recording permission is required before continuing.")
    }

    func testOnboardingCompletesWhenScreenRecordingPermissionIsGranted() {
        let completion = OnboardingCompletionBox(false)
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            accessibilityPermission: makeAccessibilityPermission(isTrusted: false),
            onboardingStore: completion.store
        )

        let didComplete = model.completeOnboarding()

        XCTAssertTrue(didComplete)
        XCTAssertTrue(completion.value)
        XCTAssertEqual(model.windowCommand?.action, .finishOnboarding)
        XCTAssertEqual(model.hudState.presentation, .visible)
    }

    func testOnboardingRefreshMarksScreenRecordingGrantedAfterPermissionChanges() {
        var isGranted = false
        let model = AppModel(
            screenRecordingPermission: ScreenRecordingPermission(client: ScreenRecordingPermissionClient(
                preflight: { isGranted },
                request: { isGranted },
                hasRequestedPrompt: { true },
                setRequestedPrompt: { _ in }
            )),
            accessibilityPermission: makeAccessibilityPermission(isTrusted: false),
            onboardingStore: OnboardingCompletionBox(false).store
        )

        XCTAssertEqual(model.screenRecordingPermissionState, .requestAlreadyShown)

        isGranted = true
        model.refreshOnboardingPermissionStates()

        XCTAssertEqual(model.screenRecordingPermissionState, .granted)
        XCTAssertTrue(model.canContinueOnboarding)
    }

    func testOnboardingRefreshMarksAccessibilityGrantedAfterPermissionChanges() {
        var isTrusted = false
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: false),
            accessibilityPermission: AccessibilityPermission(client: AccessibilityPermissionClient(
                isTrusted: { isTrusted },
                request: { isTrusted },
                hasRequestedPrompt: { true },
                setRequestedPrompt: { _ in }
            )),
            onboardingStore: OnboardingCompletionBox(false).store
        )

        XCTAssertEqual(model.accessibilityPermissionState, .requestAlreadyShown)

        isTrusted = true
        model.refreshOnboardingPermissionStates()

        XCTAssertEqual(model.accessibilityPermissionState, .granted)
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

    func testAppWindowActionsCloseCaptureSetupClosesSelectorsWithoutHUD() {
        let actions = AppWindowActions()
        var openedWindows: [String] = []
        var dismissedWindows: [String] = []

        actions.install(
            openWindow: { openedWindows.append($0) },
            openEditor: { _ in },
            dismissWindow: { dismissedWindows.append($0) },
            activateApp: {}
        )
        actions.perform(NativeWindowCommand(action: .closeCaptureSetup))

        XCTAssertTrue(openedWindows.isEmpty)
        XCTAssertEqual(dismissedWindows, ["source-selector", "area-selector"])
        XCTAssertFalse(dismissedWindows.contains("hud"))
    }

    func testAppWindowActionsShowOnboardingClosesCaptureWindowsAndOpensOnboarding() {
        let actions = AppWindowActions()
        var openedWindows: [String] = []
        var dismissedWindows: [String] = []

        actions.install(
            openWindow: { openedWindows.append($0) },
            openEditor: { _ in },
            dismissWindow: { dismissedWindows.append($0) },
            activateApp: {}
        )
        actions.perform(NativeWindowCommand(action: .showOnboarding))

        XCTAssertEqual(openedWindows, ["onboarding"])
        XCTAssertEqual(dismissedWindows, ["hud", "source-selector"])
    }

    func testAppWindowActionsFinishOnboardingClosesOnboardingAndOpensHUD() {
        let actions = AppWindowActions()
        var openedWindows: [String] = []
        var dismissedWindows: [String] = []

        actions.install(
            openWindow: { openedWindows.append($0) },
            openEditor: { _ in },
            dismissWindow: { dismissedWindows.append($0) },
            activateApp: {}
        )
        actions.perform(NativeWindowCommand(action: .finishOnboarding))

        XCTAssertEqual(openedWindows, ["hud"])
        XCTAssertEqual(dismissedWindows, ["onboarding"])
    }
}

@MainActor
private final class OnboardingCompletionBox {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    var store: OnboardingStateStore {
        OnboardingStateStore(
            isCompleted: { self.value },
            setCompleted: { self.value = $0 }
        )
    }
}

@MainActor
private func makeScreenRecordingPermission(isGranted: Bool) -> ScreenRecordingPermission {
    ScreenRecordingPermission(client: ScreenRecordingPermissionClient(
        preflight: { isGranted },
        request: { isGranted },
        hasRequestedPrompt: { false },
        setRequestedPrompt: { _ in }
    ))
}

@MainActor
private func makeAccessibilityPermission(isTrusted: Bool) -> AccessibilityPermission {
    AccessibilityPermission(client: AccessibilityPermissionClient(
        isTrusted: { isTrusted },
        request: { isTrusted },
        hasRequestedPrompt: { false },
        setRequestedPrompt: { _ in }
    ))
}

private func makeSource(
    id: String = "display:1",
    kind: CaptureSourceKind = .display,
    displayID: UInt32? = nil
) -> CaptureSource {
    CaptureSource(
        id: id,
        kind: kind,
        name: "Display 1",
        subtitle: "Built-in",
        displayIndex: kind == .display ? 1 : nil,
        displayID: displayID,
        windowID: nil,
        area: nil,
        thumbnailData: nil
    )
}

@MainActor
private final class ScreenSelectionPresenterSpy: ScreenSelectionPresenting {
    var presentedSources: [CaptureSource] = []
    var dismissCallCount = 0
    var onSelect: ((CaptureSource) -> Void)?
    var onCancel: (() -> Void)?

    func present(
        displaySources: [CaptureSource],
        onSelect: @escaping (CaptureSource) -> Void,
        onCancel: @escaping () -> Void
    ) {
        presentedSources = displaySources
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    func dismiss() {
        dismissCallCount += 1
    }

    func select(_ source: CaptureSource) {
        onSelect?(source)
    }

    func cancel() {
        onCancel?()
    }
}

private enum TestScreenshotError: Error {
    case writeFailed
    case rememberFailed
}
