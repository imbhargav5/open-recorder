import CoreGraphics
import XCTest
@testable import OpenRecorderMac

@MainActor
final class AppShellStateMachineTests: XCTestCase {
    func testHealthPayloadDecodesServiceResponseFields() throws {
        let json: String = """
        {
          "service": "open-recorder",
          "version": "1.2.3",
          "platform": "macOS"
        }
        """

        let health = try JSONDecoder().decode(HealthPayload.self, from: Data(json.utf8))

        XCTAssertEqual(health, HealthPayload(service: "open-recorder", version: "1.2.3", platform: "macOS"))
    }

    func testShellRoutesEditorSessionAndWindowCommand() throws {
        var state = AppShellState()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/demo.mp4"), title: "Demo")

        let effects = state.applying(.editorSessionShown(session))

        XCTAssertEqual(state.selectedSection, .editor)
        XCTAssertEqual(state.currentVideoURL, session.url)
        XCTAssertNil(state.currentScreenshotURL)
        XCTAssertEqual(state.lastEditorSession, session)
        XCTAssertEqual(state.windowCommand?.action, .showStudio)
        XCTAssertEqual(state.windowCommand?.editorSession, session)
        let windowCommand = try XCTUnwrap(state.windowCommand)
        XCTAssertEqual(effects, [.openEditorSession(session), .emitWindowCommand(windowCommand)])
    }

    func testShellConsumesWindowCommandOnce() {
        var state = AppShellState()

        let effects = state.applying(.windowCommandRequested(.showHUD))
        let command = state.windowCommand
        XCTAssertEqual(effects, command.map { [.emitWindowCommand($0)] } ?? [])

        XCTAssertEqual(state.applying(.windowCommandConsumed(command?.id)), [])
        XCTAssertNil(state.windowCommand)
        XCTAssertEqual(state.applying(.windowCommandConsumed(command?.id)), [])
    }

    func testShellBackendRefreshOwnsServiceStateAndStatus() {
        var state = AppShellState()
        let paths = AppPaths(recordingsDir: "/r", screenshotsDir: "/s", projectsDir: "/p", supportDir: "/support")
        let project = makeProjectSummary(path: "/p/demo.openrecorder")
        let health = HealthPayload(service: "open-recorder", version: "1.0", platform: "macOS")

        let effects = state.applying(.backendRefreshed(paths: paths, projects: [project], health: health))

        XCTAssertEqual(state.paths, paths)
        XCTAssertEqual(state.projects, [project])
        XCTAssertEqual(state.serviceHealth, health)
        XCTAssertEqual(state.statusMessage, "Rust service ready")
        XCTAssertEqual(effects, [.setStatusMessage("Rust service ready")])
    }

    func testShellRemovesProjectSummaryByPath() {
        var state = AppShellState()
        let first = makeProjectSummary(path: "/p/first.openrecorder")
        let second = makeProjectSummary(path: "/p/second.openrecorder")
        state.projects = [first, second]

        let effects = state.applying(.projectSummaryRemoved(path: first.path))

        XCTAssertEqual(effects, [])
        XCTAssertEqual(state.projects, [second])
    }

    func testShellDriverOwnsLongLivedChildDrivers() {
        let shell = AppShellDriver()
        let workspace = shell.workspace
        let capture = shell.capture
        let captureOptions = shell.captureOptions
        let inlineSourceSelector = shell.inlineSourceSelector
        let floatingSourceSelector = shell.floatingSourceSelector
        let onboarding = shell.onboarding
        let settings = shell.settings
        let videoExport = shell.videoExport

        XCTAssertTrue(shell.workspace === workspace)
        XCTAssertTrue(shell.capture === capture)
        XCTAssertTrue(shell.captureOptions === captureOptions)
        XCTAssertTrue(shell.inlineSourceSelector === inlineSourceSelector)
        XCTAssertTrue(shell.floatingSourceSelector === floatingSourceSelector)
        XCTAssertTrue(shell.onboarding === onboarding)
        XCTAssertTrue(shell.settings === settings)
        XCTAssertTrue(shell.videoExport === videoExport)
    }

    func testShellDriverKeepsEditorWindowWorkspacesIndependentBySession() {
        let shell = AppShellDriver()
        let firstSession = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/first.png"))
        let secondSession = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/second.png"))

        let firstWorkspace = shell.workspace(for: firstSession)
        let secondWorkspace = shell.workspace(for: secondSession)

        XCTAssertTrue(shell.workspace(for: nil) === shell.workspace)
        XCTAssertTrue(shell.workspace(for: firstSession) === firstWorkspace)
        XCTAssertFalse(firstWorkspace === secondWorkspace)

        firstWorkspace.screenshot.update(\.padding, to: 96)
        secondWorkspace.screenshot.update(\.padding, to: 18)

        XCTAssertEqual(firstWorkspace.screenshot.state.screenshot.padding, 96)
        XCTAssertEqual(secondWorkspace.screenshot.state.screenshot.padding, 18)
    }

    func testAppModelFacadeMirrorsShellRouting() {
        let model = AppModel()
        let session = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/screen.png"), title: "Screen")

        model.selectedSection = .projects
        XCTAssertEqual(model.appShell.state.selectedSection, .projects)

        model.showEditor(for: session)

        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertEqual(model.currentScreenshotURL, session.url)
        XCTAssertNil(model.currentVideoURL)
        XCTAssertEqual(model.lastEditorSession, session)
        XCTAssertEqual(model.appShell.state.lastEditorSession, session)
        XCTAssertEqual(model.windowCommand?.action, .showStudio)
        XCTAssertEqual(model.windowCommand?.editorSession, session)
    }
}

@MainActor
final class CaptureDriverStateMachineTests: XCTestCase {
    func testDriverAppliesCaptureReducerAndEmitsEffects() {
        let driver = CaptureDriver()
        var transitions: [CaptureTransition] = []
        var effects: [[CaptureEffect]] = []
        var didDismissScreenSelection = false
        var didShowHUD = false
        driver.configure(
            transitionHandler: { transitions.append($0) },
            effectObserver: { effects.append($0) },
            effectHandlers: CaptureEffectHandlers(
                showHUD: {
                    didShowHUD = true
                },
                dismissScreenSelection: {
                    didDismissScreenSelection = true
                }
            )
        )

        let transition = driver.send(.beginCapture(.recording, runtimeIsRecording: false))

        XCTAssertEqual(driver.state.phase, .choosingSourceType(.recording))
        XCTAssertEqual(transition.statusMessage, "Choose a source type.")
        XCTAssertEqual(transitions.map(\.state.phase), [.choosingSourceType(.recording)])
        XCTAssertEqual(effects, [[.dismissScreenSelection, .showHUD]])
        XCTAssertTrue(didDismissScreenSelection)
        XCTAssertTrue(didShowHUD)
    }

    func testDriverOwnsRecordingStartTaskCancellation() async {
        let driver = CaptureDriver()
        let source = makeCaptureSource(id: "display-1", kind: .display)
        let outputURL = URL(fileURLWithPath: "/tmp/recording.mp4")
        var started = 0
        var canceled = false
        var cancelEffectRan = false

        driver.configure(
            effectHandlers: CaptureEffectHandlers(
                cancelRecordingStart: {
                    cancelEffectRan = true
                },
                runRecordingStart: { _, _ in
                    started += 1
                    await waitUntilCancelled()
                    canceled = true
                }
            )
        )

        _ = driver.send(.recordingFilePrepared(source, outputURL))
        await Task.yield()
        XCTAssertEqual(started, 1)

        _ = driver.send(.recordingStopRequested)
        await waitForCondition { canceled }

        XCTAssertTrue(cancelEffectRan)
        XCTAssertTrue(canceled)
    }

    func testDriverOwnsScreenshotCaptureTaskCancellation() async {
        let driver = CaptureDriver()
        let source = makeCaptureSource(id: "window-1", kind: .window)
        var started = 0
        var canceled = false
        var cancelEffectRan = false

        driver.configure(
            effectHandlers: CaptureEffectHandlers(
                cancelScreenshotCapture: {
                    cancelEffectRan = true
                },
                runScreenshotCapture: { _ in
                    started += 1
                    await waitUntilCancelled()
                    canceled = true
                }
            )
        )

        driver.setStateForTesting(CaptureState(
            phase: .ready(.screenshot, source),
            selectedSource: source,
            preferredSourceKind: source.kind
        ))
        _ = driver.send(.screenshotRequested)
        await Task.yield()
        XCTAssertEqual(started, 1)

        _ = driver.send(.cancelCapture)
        await waitForCondition { canceled }

        XCTAssertTrue(cancelEffectRan)
        XCTAssertTrue(canceled)
    }
}

private func waitUntilCancelled() async {
    for await _ in AsyncStream<Void>(Void.self, { _ in }) {}
}

@MainActor
private func waitForCondition(
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await clock.sleep(for: .milliseconds(1))
    }
    XCTAssertTrue(condition(), "Timed out waiting for condition after \(timeout)", file: file, line: line)
}

@MainActor
final class CaptureOptionsStateMachineTests: XCTestCase {
    func testDeviceSelectionAndLockedSystemAudioAreReducerDriven() {
        var state = CaptureOptionsState(
            microphoneDevices: [CaptureDeviceInfo(id: "mic-1", name: "Studio Mic", isDefault: false)],
            cameraDevices: [CaptureDeviceInfo(id: "cam-1", name: "Desk Camera", isDefault: false)]
        )

        var effects = state.applying(.microphoneSelected("mic-1"))
        XCTAssertTrue(state.includeMicrophone)
        XCTAssertEqual(state.selectedMicrophoneDeviceName, "Studio Mic")
        XCTAssertEqual(effects, [.setStatusMessage("Microphone set to Studio Mic"), .closeMicrophoneSelector])

        state.includeSystemAudio = true
        state.canChangeOptions = false
        effects = state.applying(.systemAudioToggled)

        XCTAssertTrue(state.includeSystemAudio)
        XCTAssertEqual(state.statusMessage, "System audio is on for this recording.")
        XCTAssertEqual(effects, [.setStatusMessage("System audio is on for this recording.")])
    }
}

@MainActor
final class SourceSelectorStateMachineTests: XCTestCase {
    func testPreferredTabHeightAndEffectsAreReducerDriven() {
        var state = SourceSelectorState(sourceTab: .windows, visibleTabs: [.windows, .area])

        XCTAssertEqual(state.applying(.preferredSourceKindSynced(.area)), [])
        XCTAssertEqual(state.sourceTab, .area)

        XCTAssertEqual(state.applying(.heightMeasured(500)), [])
        XCTAssertEqual(state.preferredHeight, 532)

        XCTAssertEqual(state.applying(.refreshRequested), [.refreshSources])
        XCTAssertEqual(state.applying(.shareRequested), [.share])
        XCTAssertEqual(state.applying(.drawAreaRequested), [.drawArea])
    }

    func testPreferredSourceKindDoesNotSelectHiddenTab() {
        var state = SourceSelectorState(sourceTab: .windows, visibleTabs: [.windows, .area])

        XCTAssertEqual(state.applying(.preferredSourceKindSynced(.display)), [])

        XCTAssertEqual(state.sourceTab, .windows)
    }
}

@MainActor
final class OnboardingAndSettingsStateMachineTests: XCTestCase {
    func testOnboardingPermissionAndContinueLifecycle() {
        var state = OnboardingMachineState(
            screenRecordingPermissionState: .requestAvailable,
            accessibilityPermissionState: .requestAvailable
        )

        XCTAssertEqual(state.applying(.continueRequested), [])
        XCTAssertEqual(state.statusMessage, "Screen Recording permission is required before continuing.")

        let effects = state.applying(.screenPermissionRequested(.granted))
        XCTAssertEqual(state.screenRecordingPermissionState, .granted)
        XCTAssertEqual(state.statusMessage, "Screen Recording is enabled.")
        XCTAssertEqual(effects, [.refreshPermissions])

        XCTAssertEqual(state.applying(.continueRequested), [.completeOnboarding])
    }

    func testSettingsPreferenceAndFolderEffects() {
        var state = SettingsMachineState(createZoomsAutomatically: false)

        XCTAssertEqual(state.applying(.autoZoomPreferenceChanged(true)), [.persistAutoZoomPreference(true)])
        XCTAssertTrue(state.createZoomsAutomatically)
        XCTAssertEqual(state.applying(.autoZoomPreferenceChanged(true)), [])
        XCTAssertEqual(state.applying(.autoZoomAnimationPresetChanged(.cinematic)), [.persistAutoZoomAnimationPreset(.cinematic)])
        XCTAssertEqual(state.autoZoomAnimationPreset, .cinematic)
        XCTAssertEqual(state.applying(.autoZoomAnimationPresetChanged(.cinematic)), [])
        XCTAssertEqual(state.applying(.autoZoomAnimationPresetSynced(.guided)), [])
        XCTAssertEqual(state.autoZoomAnimationPreset, .guided)
        XCTAssertEqual(state.applying(.folderOpenRequested("/tmp")), [.openFolder("/tmp")])

        let health = HealthPayload(service: "open-recorder", version: "1", platform: "macOS")
        let paths = AppPaths(recordingsDir: "/r", screenshotsDir: "/s", projectsDir: "/p", supportDir: "/support")
        XCTAssertEqual(state.applying(.serviceRefreshSucceeded(serviceHealth: health, paths: paths)), [])
        XCTAssertEqual(state.serviceHealth, health)
        XCTAssertEqual(state.paths, paths)
        XCTAssertFalse(state.isRefreshingService)
    }
}

@MainActor
final class VideoRuntimeStateMachineTests: XCTestCase {
    func testPlaybackReducerResetsLoadsAndAppliesSpeed() {
        var state = VideoPlaybackState()
        let url = URL(fileURLWithPath: "/tmp/demo.mov")

        XCTAssertEqual(state.applying(.load(url)), [.clearPlayer, .loadPlayer(url), .loadMetadata(url)])
        XCTAssertEqual(state.currentURL, url)
        XCTAssertEqual(state.previewPlaybackSpeed, 1)

        state.duration = 8
        state.previewPlaybackSpeed = 2
        state.timelineEdits = TimelineEditSnapshot(clipSplitTimes: [4], clipSpeeds: [1: 1.5])

        XCTAssertEqual(state.effectivePlaybackRate(at: 5), 3)
        XCTAssertEqual(state.applying(.previewSpeedCycled), [])
        XCTAssertEqual(state.previewPlaybackSpeed, 4)
    }

    func testPlaybackSeekWithoutDurationClampsLowerBoundOnly() {
        var state = VideoPlaybackState()

        XCTAssertEqual(state.applying(.seekRequested(-2)), [.seek(0)])
        XCTAssertEqual(state.currentTime, 0)

        XCTAssertEqual(state.applying(.seekRequested(12)), [.seek(12)])
        XCTAssertEqual(state.currentTime, 12)
    }

    func testCropReducerHandlesKeyboardAspectAndConfirm() {
        var state = VideoCropState(
            draftSelection: VideoCropSelection().withPixelRect(CGRect(x: 100, y: 100, width: 800, height: 600), in: CGSize(width: 1920, height: 1080)),
            sourceSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(state.applying(.keyboardAdjusted(.move(dx: 10, dy: -5))), [])
        XCTAssertEqual(state.currentPixelRect.minX, 110, accuracy: 0.001)
        XCTAssertEqual(state.currentPixelRect.minY, 95, accuracy: 0.001)

        XCTAssertEqual(state.applying(.aspectSelected(.square)), [])
        XCTAssertEqual(state.aspect, .square)
        XCTAssertEqual(state.currentPixelRect.width, state.currentPixelRect.height, accuracy: 0.001)

        XCTAssertEqual(state.applying(.confirmRequested), [.confirm(state.draftSelection)])
    }
}

private func makeProjectSummary(path: String) -> ProjectSummary {
    ProjectSummary(
        id: path,
        title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        path: path,
        recordingPath: "/tmp/demo.mp4",
        screenshotPath: nil,
        sourceName: "Display",
        createdAt: "2026-05-19T00:00:00Z",
        updatedAt: "2026-05-19T00:00:00Z",
        lastOpenedAt: "2026-05-19T00:00:00Z",
        missing: false
    )
}

private func makeCaptureSource(id: String, kind: CaptureSourceKind) -> CaptureSource {
    CaptureSource(
        id: id,
        kind: kind,
        name: kind == .display ? "Display" : "Window",
        subtitle: "",
        displayIndex: kind == .display ? 1 : nil,
        displayID: kind == .display ? 1 : nil,
        windowID: kind == .window ? 42 : nil,
        area: nil,
        thumbnailData: nil
    )
}
