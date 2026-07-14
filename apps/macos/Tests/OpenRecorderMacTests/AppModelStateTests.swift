import Combine
import Darwin
import Observation
import XCTest
@testable import OpenRecorderMac

@MainActor
final class AppModelStateTests: XCTestCase {
    func testDriverBackedFacadeParticipatesInObservationTracking() async {
        let model = AppModel()
        let changeObserved = expectation(description: "Driver-backed facade change observed")

        withObservationTracking {
            _ = model.includeCamera
        } onChange: {
            changeObserved.fulfill()
        }

        model.includeCamera = true

        await fulfillment(of: [changeObserved], timeout: 1)
    }

    func testDriverBackedFacadePreservesObservableObjectNotifications() throws {
        let suiteName = "AppModelStateTests.notifications.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(recordingPreferences: RecordingPreferencesStore(defaults: defaults))
        var emissionCount = 0
        let observation = model.objectWillChange.sink {
            emissionCount += 1
        }

        model.includeMicrophone.toggle()
        model.createZoomsAutomatically.toggle()

        XCTAssertEqual(emissionCount, 2)
        withExtendedLifetime(observation) {}
    }

    func testTimestampedFileNameUsesProvidedDate() {
        let date = Date(timeIntervalSince1970: 1_767_267_303)
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss-SSS"

        XCTAssertEqual(
            timestampedFileName(prefix: "recording", extension: "mp4", date: date),
            "recording-\(formatter.string(from: date)).mp4"
        )
    }

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

    func testDeniedScreenPermissionBlocksRecordingBeforePreparingOrHidingCaptureUI() async {
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: false),
            prepareRecordingFilePath: { _ in
                XCTFail("File preparation must not run before permission preflight succeeds")
                return PreparedFile(path: "/tmp/unexpected.mp4")
            }
        )
        let source = makeSource()
        model.capture.setSourcesForTesting([source])
        model.setCaptureStateForTesting(.ready(.recording, source))

        model.startRecording()
        await waitForCondition {
            !model.isCapturePreflightRunning
        }

        XCTAssertEqual(model.hudState.phase, .ready(.recording, source))
        XCTAssertEqual(model.hudState.presentation, .visible)
        XCTAssertEqual(model.recordingPhase, .idle)
        XCTAssertEqual(model.statusMessage, CaptureBlocker.screenRecordingPermissionNeedsRestart.message)
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testDeniedScreenPermissionBlocksScreenshotBeforeHidingUIOrInvokingCapturer() {
        var didCapture = false
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: false),
            screenshotCapture: { _, _ in
                didCapture = true
            }
        )
        let source = makeSource()
        model.capture.setSourcesForTesting([source])
        model.setCaptureStateForTesting(.ready(.screenshot, source))

        model.takeScreenshot()

        XCTAssertFalse(didCapture)
        XCTAssertEqual(model.hudState.phase, .ready(.screenshot, source))
        XCTAssertEqual(model.hudState.presentation, .visible)
        XCTAssertEqual(model.statusMessage, CaptureBlocker.screenRecordingPermissionNeedsRestart.message)
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testChoosingWindowSourceTypeOpensSourceSelectorOnWindowTab() {
        let model = AppModel()

        model.beginCapture(.recording)
        model.chooseSourceType(.window)

        XCTAssertEqual(model.hudState.phase, .selectingSource(.recording))
        XCTAssertEqual(model.preferredSourceSelectorKind, .window)
        XCTAssertEqual(model.statusMessage, "Choose a window.")
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testCancelingSourceChangeKeepsPreviouslyCommittedReadySource() {
        let model = AppModel()
        let source = makeSource(id: "window:committed", kind: .window)
        model.setCaptureStateForTesting(.ready(.recording, source))
        model.requestSourceSelector(kind: .window)

        model.cancelSourceSelection()

        XCTAssertEqual(model.hudState.phase, .ready(.recording, source))
        XCTAssertEqual(model.selectedSource, source)
        XCTAssertEqual(model.statusMessage, "Selected \(source.name)")
        XCTAssertEqual(model.windowCommand?.action, .showHUD)
    }

    func testCancelingInitialSourceSelectionStillCancelsCaptureSetup() {
        let model = AppModel()
        model.beginCapture(.recording)
        model.chooseSourceType(.window)

        model.cancelSourceSelection()

        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.windowCommand?.action, .closeCaptureSetup)
    }

    func testChoosingAreaSourceTypeOpensSourceSelectorOnAreaTab() {
        let model = AppModel()

        model.beginCapture(.screenshot)
        model.chooseSourceType(.area)

        XCTAssertEqual(model.hudState.phase, .selectingSource(.screenshot))
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
        model.setCaptureStateForTesting(CaptureState(phase: .choosingMode, selectedSource: source))

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
        let source = makeSource()

        model.setCaptureStateForTesting(.startingRecording(source))
        XCTAssertFalse(model.canStartNewCapture)

        model.setCaptureStateForTesting(.countingDownRecording(source))
        XCTAssertFalse(model.canStartNewCapture)

        model.setCaptureStateForTesting(.stoppingRecording(source))
        XCTAssertFalse(model.canStartNewCapture)

        model.setCaptureStateForTesting(.choosingMode)
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

            model.setCaptureStateForTesting(state)

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

    func testEditorWindowTitleOnlyShowsProjectExtensionForManagedProjects() {
        XCTAssertEqual(
            editorWindowTitle(displayTitle: "Imported Recording", projectPath: nil),
            "Imported Recording"
        )
        XCTAssertEqual(
            editorWindowTitle(displayTitle: "Managed Recording", projectPath: "/tmp/managed.openrecorder"),
            "Managed Recording.openrecorder"
        )
        XCTAssertEqual(
            editorWindowTitle(displayTitle: "Already.openrecorder", projectPath: "/tmp/already.openrecorder"),
            "Already.openrecorder"
        )
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

    func testRecordingFilePreparationRunsOffMainActorAfterSuccessfulPreflight() async {
        var source = makeSource(id: "area:interactive", kind: .area)
        source.area = CaptureArea(x: 10, y: 20, width: 640, height: 360, displayID: 1)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("preflight-\(UUID().uuidString).mp4")
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            runRecordingCountdown: { _ in throw CancellationError() },
            prepareRecordingFilePath: { _ in
                guard !Thread.isMainThread else {
                    throw AppModelTestError.recordingFilePreparationRanOnMainThread
                }
                return PreparedFile(path: outputURL.path)
            }
        )
        model.setCaptureStateForTesting(.ready(.recording, source))

        model.startRecording()
        await waitForCondition { model.statusMessage == "Recording canceled." }

        XCTAssertFalse(model.isCapturePreflightRunning)
        XCTAssertEqual(model.captureOptions.state.deviceLoadPhase, .idle)
        XCTAssertEqual(model.hudState.phase, .ready(.recording, source))
        XCTAssertEqual(model.hudState.presentation, .visible)
    }

    func testCanceledPermissionPreflightCannotOverwriteANewerCaptureFlow() async {
        let permissionGate = AsyncPermissionGate()
        var source = makeSource(id: "area:interactive", kind: .area)
        source.area = CaptureArea(x: 0, y: 0, width: 800, height: 450, displayID: 1)
        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            prepareCameraPermission: {
                await permissionGate.wait()
                return true
            }
        )
        model.includeCamera = true
        model.setCaptureStateForTesting(.ready(.recording, source))

        model.startRecording()
        let permissionCheckStarted = await permissionGate.waitUntilStarted()
        XCTAssertTrue(permissionCheckStarted)
        XCTAssertFalse(model.canChangeRecordingOptions)
        XCTAssertFalse(model.captureOptions.state.canChangeOptions)
        model.toggleSystemAudio()
        XCTAssertFalse(model.includeSystemAudio)
        model.cancelCapture()
        model.beginCapture(.screenshot)
        await permissionGate.open()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(model.isCapturePreflightRunning)
        XCTAssertEqual(model.hudState.phase, .choosingSourceType(.screenshot))
        XCTAssertEqual(model.statusMessage, "Choose a source type.")
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
        XCTAssertNotEqual(model.windowCommand?.action, .showSourceSelector)
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

    func testRequestingSourceSelectorForSelectedScreenReopensScreenSelectionOverlay() {
        let presenter = ScreenSelectionPresenterSpy()
        let model = AppModel(screenSelectionPresenter: presenter)
        let source = makeSource(displayID: 42)
        model.capture.setSourcesForTesting([source])
        model.setCaptureStateForTesting(.ready(.recording, source))

        model.requestSourceSelector()

        XCTAssertEqual(model.hudState.phase, .screenSelecting(.recording))
        XCTAssertEqual(model.preferredSourceSelectorKind, .display)
        XCTAssertEqual(presenter.presentedSources, [source])
        XCTAssertNotEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testCancelingScreenSelectionReturnsToSourceTypeChoice() {
        let presenter = ScreenSelectionPresenterSpy()
        let model = AppModel(screenSelectionPresenter: presenter)
        let source = makeSource(displayID: 42)
        model.capture.setSourcesForTesting([source])

        model.beginCapture(.recording)
        model.chooseSourceType(.screen)
        presenter.cancel()

        XCTAssertEqual(model.hudState.phase, .choosingSourceType(.recording))
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

    func testOpenEditorFileRegistersScreenshotProjectBeforeOpeningEditor() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("example-screenshot.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("image".utf8)))
        let project = makeImportedProjectSummary(
            path: directory.appendingPathComponent("example-screenshot.openrecorder").path,
            screenshotPath: url.path
        )
        let model = AppModel(registerImportedMedia: { _, _ in project })

        let importTask = try XCTUnwrap(model.openEditorFile(at: url))
        await importTask.value

        let editorSession = try XCTUnwrap(model.windowCommand?.editorSession)
        XCTAssertEqual(model.currentScreenshotURL, url)
        XCTAssertNil(model.currentVideoURL)
        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertEqual(model.windowCommand?.action, .showStudio)
        XCTAssertEqual(editorSession.kind, .screenshot)
        XCTAssertEqual(editorSession.url, url)
        XCTAssertEqual(editorSession.projectPath, project.path)
        XCTAssertEqual(model.projects.first, project)
        XCTAssertEqual(model.statusMessage, "Opened example-screenshot.png")
    }

    func testOpenEditorFileRestoresExistingManagedProjectStateDuringImport() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mediaURL = directory.appendingPathComponent("existing.png")
        let projectURL = directory.appendingPathComponent("existing.openrecorder")
        XCTAssertTrue(FileManager.default.createFile(atPath: mediaURL.path, contents: Data("image".utf8)))
        let savedState = ScreenshotEditorState(padding: 92, imageRoundness: 24)
        let document = ProjectDocument(
            schemaVersion: 2,
            title: "Existing Project",
            recordingPath: nil,
            screenshotPath: mediaURL.path,
            sourceName: "Imported",
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-11T00:00:00Z",
            editorState: ProjectEditorState(screenshot: savedState),
            recordingSession: nil
        )
        try JSONEncoder().encode(document).write(to: projectURL)
        let project = makeImportedProjectSummary(path: projectURL.path, screenshotPath: mediaURL.path)
        let model = AppModel(registerImportedMedia: { _, _ in project })

        let importTask = try XCTUnwrap(model.openEditorFile(at: mediaURL))
        await importTask.value

        let session = try XCTUnwrap(model.windowCommand?.editorSession)
        XCTAssertEqual(session.projectPath, projectURL.path)
        XCTAssertEqual(session.title, "Existing Project")
        XCTAssertEqual(session.screenshotEditorState, savedState)
    }

    func testConcurrentRequestsForSameMediaShareOneProjectImport() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mediaURL = directory.appendingPathComponent("duplicate.png")
        let mediaAliasURL = directory.appendingPathComponent("duplicate-alias.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: mediaURL.path, contents: Data("image".utf8)))
        try FileManager.default.createSymbolicLink(at: mediaAliasURL, withDestinationURL: mediaURL)
        let project = makeImportedProjectSummary(
            path: directory.appendingPathComponent("duplicate.openrecorder").path,
            screenshotPath: mediaURL.path
        )
        let registration = BlockingImportRegistration(summary: project)
        let model = AppModel(registerImportedMedia: { _, _ in
            registration.register()
        })

        let first = try XCTUnwrap(model.openEditorFile(at: mediaURL))
        let didStartRegistration = await registration.waitForCallCount(1)
        XCTAssertTrue(didStartRegistration)
        let second = try XCTUnwrap(model.openEditorFile(at: mediaAliasURL))
        XCTAssertEqual(registration.callCount, 1)

        registration.release()
        await first.value
        await second.value

        XCTAssertEqual(registration.callCount, 1)
        XCTAssertEqual(model.projects, [project])
    }

    func testOpenProjectFileLoadsManagedStateAndMediaAsynchronously() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mediaURL = directory.appendingPathComponent("project-image.png")
        let projectURL = directory.appendingPathComponent("project.openrecorder")
        XCTAssertTrue(FileManager.default.createFile(atPath: mediaURL.path, contents: Data("image".utf8)))
        let savedState = ScreenshotEditorState(padding: 74, backgroundRoundness: 18)
        let document = ProjectDocument(
            schemaVersion: 2,
            title: "Managed Screenshot",
            recordingPath: nil,
            screenshotPath: mediaURL.path,
            sourceName: "Display",
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-11T00:00:00Z",
            editorState: ProjectEditorState(screenshot: savedState),
            recordingSession: nil
        )
        try JSONEncoder().encode(document).write(to: projectURL)
        let model = AppModel()

        await model.openProjectFile(at: projectURL).value

        let session = try XCTUnwrap(model.windowCommand?.editorSession)
        XCTAssertEqual(session.url, mediaURL)
        XCTAssertEqual(session.projectPath, projectURL.path)
        XCTAssertEqual(session.screenshotEditorState, savedState)
        XCTAssertEqual(model.statusMessage, "Opened Managed Screenshot")
    }

    func testOpenProjectFileReportsMissingMediaWithoutOpeningEditor() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let projectURL = directory.appendingPathComponent("missing-media.openrecorder")
        let missingMediaURL = directory.appendingPathComponent("missing.mp4")
        let document = ProjectDocument(
            schemaVersion: 2,
            title: "Missing Recording",
            recordingPath: missingMediaURL.path,
            screenshotPath: nil,
            sourceName: nil,
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-11T00:00:00Z",
            editorState: .empty,
            recordingSession: nil
        )
        try JSONEncoder().encode(document).write(to: projectURL)
        let model = AppModel()

        await model.openProjectFile(at: projectURL).value

        XCTAssertNil(model.windowCommand?.editorSession)
        XCTAssertNil(model.currentVideoURL)
        XCTAssertTrue(model.statusMessage.contains("recording file is missing or unreadable"))
    }

    func testOpenEditorFileFallsBackToDurableLocalVideoProjectWhenRegistrationFails() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("example-recording.mp4")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("video".utf8)))
        let model = AppModel(registerImportedMedia: { _, _ in throw AppModelTestError.importFailed })
        model.paths = AppPaths(
            recordingsDir: directory.path,
            screenshotsDir: directory.path,
            projectsDir: directory.path,
            supportDir: directory.path
        )

        let importTask = try XCTUnwrap(model.openEditorFile(at: url))
        await importTask.value

        let session = try XCTUnwrap(model.windowCommand?.editorSession)
        let projectPath = try XCTUnwrap(session.projectPath)
        XCTAssertEqual(session.kind, .video)
        XCTAssertEqual(session.url, url)
        XCTAssertEqual(model.currentVideoURL, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(projectPath).recovery"))
        XCTAssertEqual(model.statusMessage, "Opened example-recording.mp4")

        let relaunchedModel = AppModel(registerImportedMedia: { _, _ in
            throw AppModelTestError.importFailed
        })
        relaunchedModel.paths = model.paths
        let reopenedImport = try XCTUnwrap(relaunchedModel.openEditorFile(at: url))
        await reopenedImport.value

        XCTAssertEqual(relaunchedModel.windowCommand?.editorSession?.projectPath, projectPath)
        let recoveredProjects = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "openrecorder" }
        XCTAssertEqual(recoveredProjects.count, 1)
    }

    func testOpenEditorFileFallsBackToDurableLocalScreenshotProjectWhenRegistrationFails() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("example-screenshot.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("image".utf8)))
        let model = AppModel(registerImportedMedia: { _, _ in throw AppModelTestError.importFailed })
        model.paths = AppPaths(
            recordingsDir: directory.path,
            screenshotsDir: directory.path,
            projectsDir: directory.path,
            supportDir: directory.path
        )

        let importTask = try XCTUnwrap(model.openEditorFile(at: url))
        await importTask.value

        let session = try XCTUnwrap(model.windowCommand?.editorSession)
        let projectPath = try XCTUnwrap(session.projectPath)
        XCTAssertEqual(session.kind, .screenshot)
        XCTAssertEqual(session.url, url)
        XCTAssertEqual(session.screenshotEditorState, .default)
        XCTAssertEqual(model.currentScreenshotURL, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(projectPath).recovery"))
        XCTAssertEqual(model.statusMessage, "Opened example-screenshot.png")
    }

    func testOpenEditorFileRejectsMissingMediaBeforeCreatingProject() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mp4")
        let model = AppModel(registerImportedMedia: { _, _ in
            XCTFail("Registration should not run for a missing file")
            return makeImportedProjectSummary(path: "/tmp/unexpected.openrecorder", screenshotPath: nil)
        })

        let task = model.openEditorFile(at: url)

        XCTAssertNil(task)
        XCTAssertNil(model.windowCommand?.editorSession)
        XCTAssertTrue(model.statusMessage.contains("missing or unreadable"))
    }

    func testBackendRefreshRunsServiceWorkOffMainActor() async {
        let snapshot = BackendSnapshot(
            health: HealthPayload(service: "open-recorder", version: "1", platform: "macOS"),
            paths: AppPaths(recordingsDir: "/r", screenshotsDir: "/s", projectsDir: "/p", supportDir: "/support"),
            projects: []
        )
        let model = AppModel(loadBackendSnapshot: {
            guard pthread_main_np() == 0 else { throw AppModelTestError.backendRanOnMainThread }
            return snapshot
        })

        let refresh = model.refreshBackendState()
        XCTAssertTrue(model.appShell.settings.state.isRefreshingService)
        let succeeded = await refresh.value

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.backendLoadPhase, .loaded)
        XCTAssertEqual(model.paths, snapshot.paths)
        XCTAssertEqual(model.serviceHealth, snapshot.health)
    }

    func testBackendRefreshFailureKeepsPreviouslyLoadedProjects() async {
        let project = makeImportedProjectSummary(
            path: "/tmp/existing.openrecorder",
            screenshotPath: "/tmp/existing.png"
        )
        let model = AppModel(loadBackendSnapshot: {
            throw AppModelTestError.backendUnavailable
        })
        model.projects = [project]

        let succeeded = await model.refreshBackendState().value

        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.projects, [project])
        XCTAssertEqual(model.backendLoadPhase, .failed("Test backend unavailable"))
    }

    func testNewestBackendRefreshWinsWhenOlderRequestFinishesLast() async {
        let gate = BackendSnapshotGate()
        let olderProject = makeImportedProjectSummary(
            path: "/tmp/older.openrecorder",
            screenshotPath: "/tmp/older.png"
        )
        let newerProject = makeImportedProjectSummary(
            path: "/tmp/newer.openrecorder",
            screenshotPath: "/tmp/newer.png"
        )
        let model = AppModel(loadBackendSnapshot: {
            try await gate.load()
        })

        let olderRefresh = model.refreshBackendState()
        await waitForBackendCallCount(1, gate: gate)
        let newerRefresh = model.refreshBackendState()
        await waitForBackendCallCount(2, gate: gate)

        await gate.resume(call: 2, with: BackendSnapshot(
            health: HealthPayload(service: "new", version: "2", platform: "macOS"),
            paths: AppPaths(recordingsDir: "/new/r", screenshotsDir: "/new/s", projectsDir: "/new/p", supportDir: "/new"),
            projects: [newerProject]
        ))
        let newerSucceeded = await newerRefresh.value
        XCTAssertTrue(newerSucceeded)

        await gate.resume(call: 1, with: BackendSnapshot(
            health: HealthPayload(service: "old", version: "1", platform: "macOS"),
            paths: AppPaths(recordingsDir: "/old/r", screenshotsDir: "/old/s", projectsDir: "/old/p", supportDir: "/old"),
            projects: [olderProject]
        ))
        let olderSucceeded = await olderRefresh.value
        XCTAssertFalse(olderSucceeded)

        XCTAssertEqual(model.projects, [newerProject])
        XCTAssertEqual(model.serviceHealth?.service, "new")
        XCTAssertEqual(model.paths?.projectsDir, "/new/p")
    }

    func testBackendRefreshMergesProjectMutationsThatFinishWhileItIsLoading() async {
        let gate = BackendSnapshotGate()
        let deletedProject = makeImportedProjectSummary(
            path: "/tmp/deleted-during-refresh.openrecorder",
            screenshotPath: "/tmp/deleted.png"
        )
        let importedProject = makeImportedProjectSummary(
            path: "/tmp/imported-during-refresh.openrecorder",
            screenshotPath: "/tmp/imported.png"
        )
        let remoteProject = makeImportedProjectSummary(
            path: "/tmp/remote.openrecorder",
            screenshotPath: "/tmp/remote.png"
        )
        let model = AppModel(loadBackendSnapshot: {
            try await gate.load()
        })
        model.projects = [deletedProject]

        let refresh = model.refreshBackendState()
        await waitForBackendCallCount(1, gate: gate)
        model.projects = [importedProject]
        await gate.resume(call: 1, with: BackendSnapshot(
            health: HealthPayload(service: "open-recorder", version: "1", platform: "macOS"),
            paths: AppPaths(recordingsDir: "/r", screenshotsDir: "/s", projectsDir: "/p", supportDir: "/support"),
            projects: [deletedProject, remoteProject]
        ))

        let refreshSucceeded = await refresh.value
        XCTAssertTrue(refreshSucceeded)
        XCTAssertEqual(model.projects, [importedProject, remoteProject])
    }

    func testAreaScreenshotCompletionOpensEditorEvenIfScreenshotIndexingFails() async throws {
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
            captureUIHideDelayNanoseconds: 0,
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
            },
            registerCapturedMedia: { _, _ in
                throw AppModelTestError.backendUnavailable
            }
        )
        let area = CaptureArea(x: 24, y: 48, width: 320, height: 180, displayID: 7)

        model.paths = paths
        model.beginCapture(.screenshot)
        model.requestInteractiveAreaSelection()
        model.completeInteractiveAreaSelection(area)
        await waitForCondition {
            model.windowCommand?.action == .showStudio
        }

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
        let projectPath = try XCTUnwrap(editorSession.projectPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectPath))
        let document = try JSONDecoder().decode(
            ProjectDocument.self,
            from: Data(contentsOf: URL(fileURLWithPath: projectPath))
        )
        XCTAssertEqual(document.screenshotPath, screenshotURL.path)
        XCTAssertEqual(document.editorState?.screenshot, .default)
        XCTAssertTrue(screenshotURL.path.hasPrefix(screenshotsDir.path))
        XCTAssertEqual(model.statusMessage, "Captured \(screenshotURL.lastPathComponent)")
    }

    func testScreenshotCaptureHidesCaptureUIBeforeInvokingCapturer() async throws {
        var observedPresentation: HUDPresentationState?
        var observedWindowAction: NativeWindowCommandAction?
        var model: AppModel!
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
        model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            captureUIHideDelayNanoseconds: 0,
            screenshotCapture: { _, outputURL in
                observedPresentation = model.hudState.presentation
                observedWindowAction = model.windowCommand?.action
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard FileManager.default.createFile(atPath: outputURL.path, contents: Data("png".utf8)) else {
                    throw TestScreenshotError.writeFailed
                }
            }
        )
        let source = makeSource()

        model.paths = paths
        model.setCaptureStateForTesting(HUDState(phase: .ready(.screenshot, source), presentation: .visible))

        model.takeScreenshot()
        await waitForCondition {
            observedPresentation != nil
        }

        XCTAssertEqual(observedPresentation, .hidden)
        XCTAssertEqual(observedWindowAction, .hideAppWindowsForCapture)

        await waitForCondition {
            model.windowCommand?.action == .showStudio
        }
        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.windowCommand?.action, .showStudio)
    }

    func testScreenshotCompletionEmitsEditorCommandThroughNativeHandlerWhenCaptureWindowsAreHidden() async throws {
        var handledCommands: [NativeWindowCommand] = []
        var model: AppModel!
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
        model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            captureUIHideDelayNanoseconds: 0,
            screenshotCapture: { _, outputURL in
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard FileManager.default.createFile(atPath: outputURL.path, contents: Data("png".utf8)) else {
                    throw TestScreenshotError.writeFailed
                }
            }
        )
        model.installNativeWindowCommandHandler { command in
            handledCommands.append(command)
            _ = model.consumeWindowCommand(command)
        }
        let source = makeSource()

        model.paths = paths
        model.setCaptureStateForTesting(HUDState(phase: .ready(.screenshot, source), presentation: .visible))
        model.takeScreenshot()
        await waitForCondition {
            handledCommands.contains { $0.action == .showStudio }
        }

        XCTAssertTrue(handledCommands.contains { $0.action == .hideAppWindowsForCapture })
        let editorCommand = try XCTUnwrap(handledCommands.last { $0.action == .showStudio })
        XCTAssertEqual(editorCommand.editorSession?.kind, .screenshot)
        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertNil(model.windowCommand)
    }

    func testCancelingScreenshotDuringCaptureDoesNotOpenEditor() async throws {
        var didCapture = false
        var model: AppModel!
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
        model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            captureUIHideDelayNanoseconds: 0,
            screenshotCapture: { _, outputURL in
                didCapture = true
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard FileManager.default.createFile(atPath: outputURL.path, contents: Data("png".utf8)) else {
                    throw TestScreenshotError.writeFailed
                }
                model.cancelCapture()
            }
        )
        let source = makeSource()

        model.paths = paths
        model.setCaptureStateForTesting(.ready(.screenshot, source))
        model.takeScreenshot()
        await waitForCondition {
            didCapture
        }
        await waitForCondition {
            model.canStartNewCapture
        }

        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.statusMessage, "Ready")
        XCTAssertNil(model.currentScreenshotURL)
        XCTAssertNil(model.currentVideoURL)
        XCTAssertNotEqual(model.windowCommand?.action, .showStudio)
        XCTAssertTrue(model.canStartNewCapture)
    }

    func testStoppingRecordingWithoutWrittenFileReleasesCaptureState() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-recording-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let model = AppModel(
            stopRecording: {
                outputURL
            }
        )
        let source = makeSource()

        model.setCaptureStateForTesting(.recording(source))
        model.stopRecording()
        await waitForCondition {
            model.statusMessage == "Recording stopped before a file was written."
        }

        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertTrue(model.canStartNewCapture)
        XCTAssertEqual(model.currentVideoURL, outputURL)
        XCTAssertNil(model.currentScreenshotURL)
    }

    func testStoppingRecordingWithWrittenFileOpensEditorEvenIfProjectIndexingFails() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("finished-recording-\(UUID().uuidString).mp4")
        try Data("mp4".utf8).write(to: outputURL)
        let model = AppModel(
            stopRecording: {
                outputURL
            },
            registerCapturedMedia: { _, _ in
                throw AppModelTestError.backendUnavailable
            }
        )
        model.paths = AppPaths(
            recordingsDir: directory.path,
            screenshotsDir: directory.path,
            projectsDir: directory.path,
            supportDir: directory.path
        )
        let source = makeSource()

        model.setCaptureStateForTesting(.recording(source))
        model.stopRecording()
        await waitForCondition {
            model.windowCommand?.action == .showStudio
        }

        let editorSession = try XCTUnwrap(model.windowCommand?.editorSession)
        XCTAssertEqual(model.currentVideoURL, outputURL)
        XCTAssertNil(model.currentScreenshotURL)
        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertEqual(editorSession.kind, .video)
        XCTAssertEqual(editorSession.url, outputURL)
        let projectPath = try XCTUnwrap(editorSession.projectPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectPath))
        let document = try JSONDecoder().decode(
            ProjectDocument.self,
            from: Data(contentsOf: URL(fileURLWithPath: projectPath))
        )
        XCTAssertEqual(document.recordingPath, outputURL.path)
        XCTAssertEqual(document.recordingSession, editorSession.recordingSession)
        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertTrue(model.canStartNewCapture)
    }

    func testRecordingCompletionEmitsEditorCommandThroughNativeHandlerWhenCaptureWindowsAreHidden() async throws {
        var handledCommands: [NativeWindowCommand] = []
        var model: AppModel!
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("finished-recording-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        try Data("mp4".utf8).write(to: outputURL)
        model = AppModel(
            stopRecording: {
                outputURL
            }
        )
        model.installNativeWindowCommandHandler { command in
            handledCommands.append(command)
            _ = model.consumeWindowCommand(command)
        }
        let source = makeSource()

        model.setCaptureStateForTesting(.recording(source))
        model.stopRecording()
        await waitForCondition {
            handledCommands.contains { $0.action == .showStudio }
        }

        XCTAssertTrue(handledCommands.contains { $0.action == .hideRecordingSetup })
        let editorCommand = try XCTUnwrap(handledCommands.last { $0.action == .showStudio })
        XCTAssertEqual(editorCommand.editorSession?.kind, .video)
        XCTAssertEqual(editorCommand.editorSession?.url, outputURL)
        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertNil(model.windowCommand)
    }

    func testRecordingStartWaitsForFacecamBeforeScreenCapture() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("facecam-ordered-recording-\(UUID().uuidString).mp4")
        let facecamURL = outputURL
            .deletingPathExtension()
            .appendingPathExtension("facecam.mov")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: facecamURL)
        }

        let facecamStartedAt = Date(timeIntervalSince1970: 10)
        let screenStartedAt = Date(timeIntervalSince1970: 10.5)
        var events: [String] = []
        var facecamContinuation: CheckedContinuation<Date, Error>?

        let model = AppModel(
            screenRecordingPermission: makeScreenRecordingPermission(isGranted: true),
            captureUIHideDelayNanoseconds: 0,
            startRecordingCapture: { _, outputURL, _ in
                events.append("screen-start")
                try Data("mp4".utf8).write(to: outputURL)
                return screenStartedAt
            },
            stopRecording: {
                outputURL
            },
            prepareCameraPermission: {
                true
            },
            prepareFacecamRecording: { _ in },
            startFacecamRecording: { _, _ in
                events.append("facecam-start")
                return try await withCheckedThrowingContinuation { continuation in
                    facecamContinuation = continuation
                }
            },
            stopFacecamRecording: {
                facecamURL
            },
            runRecordingCountdown: { _ in }
        )
        let source = makeSource()
        model.includeCamera = true
        model.setCaptureStateForTesting(.ready(.recording, source))

        model.captureMachine.send(.recordingFilePrepared(source, outputURL))
        await waitForCondition {
            facecamContinuation != nil
        }

        XCTAssertEqual(events, ["facecam-start"])
        let continuation = try XCTUnwrap(facecamContinuation)
        continuation.resume(returning: facecamStartedAt)

        await waitForCondition {
            events == ["facecam-start", "screen-start"] && model.hudState == .recording(source)
        }

        XCTAssertEqual(events, ["facecam-start", "screen-start"])

        model.stopRecording()
        await waitForCondition {
            model.windowCommand?.action == .showStudio
        }

        let editorSession = try XCTUnwrap(model.windowCommand?.editorSession)
        XCTAssertEqual(editorSession.recordingSession?.facecamVideoPath, facecamURL.path)
        XCTAssertEqual(editorSession.recordingSession?.facecamOffsetMs, -500)
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

    func testDeletingRecordingProjectTrashesProjectFileAndRemovesProject() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let projectURL = tempDir.appendingPathComponent("recording.openrecorder")
        try Data("project".utf8).write(to: projectURL)
        let project = makeDeleteProjectSummary(
            title: "Recording",
            projectPath: projectURL.path,
            recordingPath: "/tmp/recording.mp4",
            screenshotPath: nil
        )
        let other = makeDeleteProjectSummary(
            title: "Other",
            projectPath: tempDir.appendingPathComponent("other.openrecorder").path,
            recordingPath: "/tmp/other.mp4",
            screenshotPath: nil
        )
        let spy = ProjectDeleteSpy()
        let model = AppModel(
            trashProjectFile: { try spy.trash($0) },
            forgetProject: { try spy.forget($0) }
        )
        model.projects = [project, other]

        model.deleteProject(project)

        XCTAssertEqual(spy.trashedURLs, [projectURL])
        XCTAssertEqual(spy.forgottenPaths, [project.path])
        XCTAssertEqual(model.projects, [other])
        XCTAssertEqual(model.statusMessage, "Deleted Recording")
    }

    func testDeletingScreenshotProjectTrashesProjectFileAndRemovesProject() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let projectURL = tempDir.appendingPathComponent("screenshot.openrecorder")
        try Data("project".utf8).write(to: projectURL)
        let project = makeDeleteProjectSummary(
            title: "Screenshot",
            projectPath: projectURL.path,
            recordingPath: nil,
            screenshotPath: "/tmp/screenshot.png"
        )
        let spy = ProjectDeleteSpy()
        let model = AppModel(
            trashProjectFile: { try spy.trash($0) },
            forgetProject: { try spy.forget($0) }
        )
        model.projects = [project]

        model.deleteProject(project)

        XCTAssertEqual(spy.trashedURLs, [projectURL])
        XCTAssertEqual(spy.forgottenPaths, [project.path])
        XCTAssertTrue(model.projects.isEmpty)
        XCTAssertEqual(model.statusMessage, "Deleted Screenshot")
    }

    func testDeletingMissingProjectSkipsTrashAndForgetsProject() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let project = makeDeleteProjectSummary(
            title: "Missing",
            projectPath: tempDir.appendingPathComponent("missing.openrecorder").path,
            recordingPath: "/tmp/missing.mp4",
            screenshotPath: nil,
            missing: true
        )
        let spy = ProjectDeleteSpy()
        let model = AppModel(
            trashProjectFile: { try spy.trash($0) },
            forgetProject: { try spy.forget($0) }
        )
        model.projects = [project]

        model.deleteProject(project)

        XCTAssertTrue(spy.trashedURLs.isEmpty)
        XCTAssertEqual(spy.forgottenPaths, [project.path])
        XCTAssertTrue(model.projects.isEmpty)
        XCTAssertEqual(model.statusMessage, "Deleted Missing")
    }

    func testDeletingProjectFailureLeavesProjectInList() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let projectURL = tempDir.appendingPathComponent("blocked.openrecorder")
        try Data("project".utf8).write(to: projectURL)
        let project = makeDeleteProjectSummary(
            title: "Blocked",
            projectPath: projectURL.path,
            recordingPath: "/tmp/blocked.mp4",
            screenshotPath: nil
        )
        let spy = ProjectDeleteSpy(trashError: TestProjectDeleteError.trashFailed)
        let model = AppModel(
            trashProjectFile: { try spy.trash($0) },
            forgetProject: { try spy.forget($0) }
        )
        model.projects = [project]

        model.deleteProject(project)

        XCTAssertEqual(spy.trashedURLs, [projectURL])
        XCTAssertTrue(spy.forgottenPaths.isEmpty)
        XCTAssertEqual(model.projects, [project])
        XCTAssertEqual(model.statusMessage, "Could not delete Blocked: Trash failed")
    }

    func testForgettingProjectFailureLeavesProjectInList() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let project = makeDeleteProjectSummary(
            title: "Forget Blocked",
            projectPath: tempDir.appendingPathComponent("forget-blocked.openrecorder").path,
            recordingPath: "/tmp/forget-blocked.mp4",
            screenshotPath: nil,
            missing: true
        )
        let spy = ProjectDeleteSpy(forgetError: TestProjectDeleteError.forgetFailed)
        let model = AppModel(
            trashProjectFile: { try spy.trash($0) },
            forgetProject: { try spy.forget($0) }
        )
        model.projects = [project]

        model.deleteProject(project)

        XCTAssertTrue(spy.trashedURLs.isEmpty)
        XCTAssertEqual(spy.forgottenPaths, [project.path])
        XCTAssertEqual(model.projects, [project])
        XCTAssertEqual(model.statusMessage, "Could not delete Forget Blocked: Forget failed")
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

    func testInstallingNativeWindowCommandHandlerImmediatelyHandlesPendingCommand() {
        var handledCommand: NativeWindowCommand?
        let model = AppModel()

        model.requestWindow(.hideAppWindowsForCapture)
        model.installNativeWindowCommandHandler { command in
            handledCommand = command
            _ = model.consumeWindowCommand(command)
        }

        XCTAssertEqual(handledCommand?.action, .hideAppWindowsForCapture)
        XCTAssertNil(model.windowCommand)
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
        model.setCaptureStateForTesting(HUDState(phase: .countingDownRecording(source), presentation: .hidden))

        model.toggleRecordingShortcut()

        XCTAssertEqual(model.recordingPhase, .idle)
        XCTAssertEqual(model.hudState, .ready(.recording, source))
        XCTAssertEqual(model.hudState.presentation, .visible)
        XCTAssertEqual(model.statusMessage, "Recording canceled.")
        XCTAssertEqual(model.windowCommand?.action, .showScreenRecordingSetup)
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
        model.setCaptureStateForTesting(.startingRecording(source))

        model.toggleRecordingShortcut()

        XCTAssertEqual(model.recordingPhase, .starting)
        XCTAssertEqual(model.hudState, .startingRecording(source, stopRequested: true))
        XCTAssertEqual(model.statusMessage, "Recording will stop after it starts.")
    }

    func testTerminationIsCanceledWhileCaptureWorkIsActive() async {
        let model = AppModel()
        let source = makeSource()
        model.capture.setRecordingForTesting(true)
        model.setCaptureStateForTesting(.recording(source))

        let canTerminate = await model.prepareForTermination()

        XCTAssertFalse(canTerminate)
        XCTAssertEqual(model.hudState.phase, .recording(source))
        XCTAssertEqual(model.statusMessage, "Finish or cancel the current capture before quitting.")
    }

    func testTerminationGateRejectsNewCaptureAndFileImportWhileAutosaveFinishes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mediaURL = directory.appendingPathComponent("late-import.mp4")
        try Data("video".utf8).write(to: mediaURL)
        let model = AppModel(registerImportedMedia: { _, _ in
            throw AppModelTestError.importFailed
        })
        let workspace = model.appShell.workspace(for: nil)
        let saveGate = AppModelAutosaveGate()
        let saveStarted = expectation(description: "Autosave started before termination gate checks")
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                saveStarted.fulfill()
                await saveGate.wait()
                return makeImportedProjectSummary(path: snapshot.projectPath, screenshotPath: nil)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(
            ProjectAutosaveSnapshot(
                projectPath: directory.appendingPathComponent("pending.openrecorder").path,
                title: "Pending",
                recordingPath: mediaURL.path,
                screenshotPath: nil,
                sourceName: nil,
                editorState: .empty,
                recordingSession: nil
            )
        ))

        let termination = Task { @MainActor in await model.prepareForTermination() }
        await fulfillment(of: [saveStarted], timeout: 1)
        let phaseBeforeRejectedCapture = model.captureState.phase

        model.beginCapture(.recording)
        let importTask = model.openEditorFile(at: mediaURL)

        XCTAssertTrue(model.isTerminationPending)
        XCTAssertEqual(model.captureState.phase, phaseBeforeRejectedCapture)
        XCTAssertNil(importTask)
        XCTAssertEqual(model.statusMessage, "Open Recorder is finishing pending work before quitting.")

        await saveGate.open()
        let canTerminate = await termination.value
        XCTAssertTrue(canTerminate)
        XCTAssertTrue(model.isTerminationPending)
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
        var didUnhideApp = false

        actions.install(
            openWindow: { openedWindows.append($0) },
            openEditor: { openedEditorSession = $0 },
            dismissWindow: { dismissedWindows.append($0) },
            activateApp: {},
            unhideApp: { didUnhideApp = true }
        )
        actions.perform(NativeWindowCommand(action: .showStudio, editorSession: session))

        XCTAssertTrue(actions.isInstalled)
        XCTAssertEqual(openedEditorSession, session)
        XCTAssertTrue(openedWindows.isEmpty)
        XCTAssertTrue(dismissedWindows.isEmpty)
        XCTAssertTrue(didUnhideApp)
    }

    func testAppWindowActionsHideRecordingSetupDismissesCaptureWindows() {
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
        XCTAssertEqual(dismissedWindows, ["hud", "source-selector", "area-selector", "microphone-selector", "camera-selector"])
    }

    func testAppWindowActionsHideAppWindowsForCapturePreservesEditorWindows() {
        let actions = AppWindowActions()
        var openedWindows: [String] = []
        var dismissedWindows: [String] = []
        var didHideApp = false

        actions.install(
            openWindow: { openedWindows.append($0) },
            openEditor: { _ in },
            dismissWindow: { dismissedWindows.append($0) },
            activateApp: {},
            hideApp: { didHideApp = true }
        )
        actions.perform(NativeWindowCommand(action: .hideAppWindowsForCapture))

        XCTAssertTrue(openedWindows.isEmpty)
        XCTAssertEqual(dismissedWindows, [
            "hud",
            "source-selector",
            "area-selector",
            "microphone-selector",
            "camera-selector"
        ])
        XCTAssertTrue(didHideApp)
    }

    func testAppWindowActionsShowScreenRecordingSetupDoesNotOpenSourceSelector() {
        let actions = AppWindowActions()
        var openedWindows: [String] = []
        var dismissedWindows: [String] = []

        actions.install(
            openWindow: { openedWindows.append($0) },
            openEditor: { _ in },
            dismissWindow: { dismissedWindows.append($0) },
            activateApp: {}
        )
        actions.perform(NativeWindowCommand(action: .showScreenRecordingSetup))

        XCTAssertEqual(openedWindows, ["hud"])
        XCTAssertEqual(dismissedWindows, ["source-selector", "area-selector"])
        XCTAssertFalse(openedWindows.contains("source-selector"))
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
private func waitForCondition(
    timeout: Duration = .seconds(5),
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await clock.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "Timed out waiting for condition after \(timeout)", file: file, line: line)
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

private final class ProjectDeleteSpy: @unchecked Sendable {
    private let trashError: Error?
    private let forgetError: Error?
    private(set) var trashedURLs: [URL] = []
    private(set) var forgottenPaths: [String] = []

    init(trashError: Error? = nil, forgetError: Error? = nil) {
        self.trashError = trashError
        self.forgetError = forgetError
    }

    func trash(_ url: URL) throws {
        trashedURLs.append(url)
        if let trashError {
            throw trashError
        }
    }

    func forget(_ path: String) throws {
        forgottenPaths.append(path)
        if let forgetError {
            throw forgetError
        }
    }
}

private actor AppModelAutosaveGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private final class BlockingImportRegistration: @unchecked Sendable {
    private let condition = NSCondition()
    private let summary: ProjectSummary
    private var isReleased = false
    private var calls = 0

    init(summary: ProjectSummary) {
        self.summary = summary
    }

    var callCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return calls
    }

    func register() -> ProjectSummary {
        condition.lock()
        calls += 1
        condition.broadcast()
        while !isReleased {
            condition.wait()
        }
        condition.unlock()
        return summary
    }

    func waitForCallCount(_ expected: Int) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while callCount < expected {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    func release() {
        condition.lock()
        isReleased = true
        condition.broadcast()
        condition.unlock()
    }
}

private actor BackendSnapshotGate {
    private var nextCall = 0
    private var continuations: [Int: CheckedContinuation<BackendSnapshot, Error>] = [:]

    func load() async throws -> BackendSnapshot {
        nextCall += 1
        let call = nextCall
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    var callCount: Int {
        nextCall
    }

    func resume(call: Int, with snapshot: BackendSnapshot) {
        continuations.removeValue(forKey: call)?.resume(returning: snapshot)
    }
}

private actor AsyncPermissionGate {
    private var started = false
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !started, clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(5))
        }
        return started
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private func waitForBackendCallCount(_ expectedCount: Int, gate: BackendSnapshotGate) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while await gate.callCount < expectedCount, clock.now < deadline {
        try? await clock.sleep(for: .milliseconds(5))
    }
    let actualCount = await gate.callCount
    XCTAssertGreaterThanOrEqual(actualCount, expectedCount)
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("open-recorder-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeDeleteProjectSummary(
    title: String,
    projectPath: String,
    recordingPath: String?,
    screenshotPath: String?,
    missing: Bool = false
) -> ProjectSummary {
    ProjectSummary(
        id: projectPath,
        title: title,
        path: projectPath,
        recordingPath: recordingPath,
        screenshotPath: screenshotPath,
        sourceName: nil,
        createdAt: "2026-05-25T00:00:00Z",
        updatedAt: "2026-05-25T00:00:00Z",
        lastOpenedAt: "2026-05-25T00:00:00Z",
        missing: missing
    )
}

private func makeImportedProjectSummary(path: String, screenshotPath: String?) -> ProjectSummary {
    ProjectSummary(
        id: path,
        title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        path: path,
        recordingPath: screenshotPath == nil ? "/tmp/imported.mp4" : nil,
        screenshotPath: screenshotPath,
        sourceName: "Imported",
        createdAt: "2026-07-11T00:00:00Z",
        updatedAt: "2026-07-11T00:00:00Z",
        lastOpenedAt: "2026-07-11T00:00:00Z",
        missing: false
    )
}

private enum AppModelTestError: LocalizedError {
    case importFailed
    case backendRanOnMainThread
    case backendUnavailable
    case recordingFilePreparationRanOnMainThread

    var errorDescription: String? {
        switch self {
        case .importFailed: "Test import failed"
        case .backendRanOnMainThread: "Backend work ran on the main thread"
        case .backendUnavailable: "Test backend unavailable"
        case .recordingFilePreparationRanOnMainThread: "Recording file preparation ran on the main thread"
        }
    }
}

private enum TestProjectDeleteError: LocalizedError {
    case trashFailed
    case forgetFailed

    var errorDescription: String? {
        switch self {
        case .trashFailed:
            "Trash failed"
        case .forgetFailed:
            "Forget failed"
        }
    }
}

private enum TestScreenshotError: Error {
    case writeFailed
    case rememberFailed
}
