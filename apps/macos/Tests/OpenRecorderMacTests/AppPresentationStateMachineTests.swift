import CoreGraphics
import XCTest
@testable import OpenRecorderMac

@MainActor
final class AppShellStateMachineTests: XCTestCase {
    func testShellRoutesEditorSessionAndWindowCommand() {
        var state = AppShellState()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/demo.mp4"), title: "Demo")

        let effects = state.applying(.editorSessionShown(session))

        XCTAssertEqual(state.selectedSection, .editor)
        XCTAssertEqual(state.currentVideoURL, session.url)
        XCTAssertNil(state.currentScreenshotURL)
        XCTAssertEqual(state.lastEditorSession, session)
        XCTAssertEqual(state.windowCommand?.action, .showStudio)
        XCTAssertEqual(state.windowCommand?.editorSession, session)
        XCTAssertEqual(effects, [.openEditorSession(session), .emitWindowCommand(state.windowCommand!)])
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
