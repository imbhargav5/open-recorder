import AVFoundation
import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BackendSnapshot: Sendable {
    var health: HealthPayload
    var paths: AppPaths
    var projects: [ProjectSummary]
}

private enum BackendLoadOutcome: Sendable {
    case success(BackendSnapshot)
    case failure(String)
}

private enum ImportedMediaRegistrationOutcome: Sendable {
    case success(ProjectSummary, projectData: Data?)
    case failure(String)
}

private enum RecordingFilePreparationOutcome: Sendable {
    case success(URL)
    case failure(String)
}

private enum ProjectFileLoadOutcome: Sendable {
    case success(Data)
    case failure(String)
}

private struct ProjectRegistrationFailure: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? { message }
}

private enum LocalProjectPersistenceOutcome: Sendable {
    case success(projectURL: URL, projectData: Data)
    case failure(String)
}

private enum CapturedProjectRegistrationOutcome: Sendable {
    case indexed(ProjectSummary)
    case locallyPersisted(ProjectSummary)
    case failed(String)

    var summary: ProjectSummary? {
        switch self {
        case .indexed(let summary), .locallyPersisted(let summary):
            summary
        case .failed:
            nil
        }
    }

    var needsScreenshotIndexRetry: Bool {
        if case .locallyPersisted = self { return true }
        return false
    }
}

private nonisolated func serviceJSONObject<T: Encodable>(for value: T) -> Any? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
}

private nonisolated func canonicalMediaIdentity(for url: URL) -> String {
    let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
    if let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path),
       let volumeNumber = attributes[.systemNumber] as? NSNumber,
       let fileNumber = attributes[.systemFileNumber] as? NSNumber {
        return "file:\(volumeNumber.uint64Value):\(fileNumber.uint64Value)"
    }
    let isCaseSensitive = try? resolvedURL.resourceValues(
        forKeys: [.volumeSupportsCaseSensitiveNamesKey]
    ).volumeSupportsCaseSensitiveNames
    let path = isCaseSensitive == false ? resolvedURL.path.lowercased() : resolvedURL.path
    return "path:\(path)"
}

@MainActor
final class AppModel: ObservableObject {
    var selectedSection: AppSection {
        get { appShell.state.selectedSection }
        set { sendAppShell(.sectionSelected(newValue)) }
    }
    @Published private(set) var captureState: CaptureState = .setup(.recording)
    var paths: AppPaths? {
        get { appShell.state.paths }
        set { sendAppShell(.pathsChanged(newValue)) }
    }
    var projects: [ProjectSummary] {
        get { appShell.state.projects }
        set {
            noteLocalProjectReplacement(from: appShell.state.projects, to: newValue)
            sendAppShell(.projectsReplaced(newValue))
        }
    }
    var currentVideoURL: URL? {
        get { appShell.state.currentVideoURL }
        set { sendAppShell(.currentVideoURLChanged(newValue)) }
    }
    var currentScreenshotURL: URL? {
        get { appShell.state.currentScreenshotURL }
        set { sendAppShell(.currentScreenshotURLChanged(newValue)) }
    }
    var lastEditorSession: EditorSession? {
        appShell.state.lastEditorSession
    }
    var statusMessage: String {
        get { appShell.state.statusMessage }
        set { sendAppShell(.statusChanged(newValue)) }
    }
    var serviceHealth: HealthPayload? {
        appShell.state.serviceHealth
    }
    var backendLoadPhase: LoadPhase {
        appShell.state.backendLoadPhase
    }
    var includeMicrophone: Bool {
        get { captureOptions.state.includeMicrophone }
        set { captureOptions.send(.microphoneEnabledChanged(newValue)) }
    }
    var includeSystemAudio: Bool {
        get { captureOptions.state.includeSystemAudio }
        set { captureOptions.send(.systemAudioChanged(newValue)) }
    }
    var includeCamera: Bool {
        get { captureOptions.state.includeCamera }
        set { captureOptions.send(.cameraEnabledChanged(newValue)) }
    }
    var showCursor: Bool {
        get { captureOptions.state.showCursor }
        set { captureOptions.send(.cursorVisibilityChanged(newValue)) }
    }
    var showClicks: Bool {
        get { captureOptions.state.showClicks }
        set { captureOptions.send(.clickVisibilityChanged(newValue)) }
    }
    var createZoomsAutomatically: Bool {
        get { appShell.settings.state.createZoomsAutomatically }
        set { appShell.settings.send(.autoZoomPreferenceChanged(newValue)) }
    }
    var autoZoomAnimationPreset: TimelineZoomAnimationPreset {
        get { appShell.settings.state.autoZoomAnimationPreset }
        set { appShell.settings.send(.autoZoomAnimationPresetChanged(newValue)) }
    }
    var microphoneDevices: [CaptureDeviceInfo] {
        get { captureOptions.state.microphoneDevices }
        set {
            captureOptions.send(.devicesRefreshed(
                microphones: newValue,
                cameras: captureOptions.state.cameraDevices
            ))
        }
    }
    var cameraDevices: [CaptureDeviceInfo] {
        get { captureOptions.state.cameraDevices }
        set {
            captureOptions.send(.devicesRefreshed(
                microphones: captureOptions.state.microphoneDevices,
                cameras: newValue
            ))
        }
    }
    var selectedMicrophoneDeviceID: String? { captureOptions.state.selectedMicrophoneDeviceID }
    var selectedCameraDeviceID: String? { captureOptions.state.selectedCameraDeviceID }
    var screenRecordingPermissionState: ScreenRecordingPermissionState {
        appShell.onboarding.state.screenRecordingPermissionState
    }
    var accessibilityPermissionState: AccessibilityPermissionState {
        appShell.onboarding.state.accessibilityPermissionState
    }
    var microphoneCaptureAuthorization: CaptureMediaAuthorizationState {
        captureMediaAuthorizationState(for: .audio)
    }
    var cameraCaptureAuthorization: CaptureMediaAuthorizationState {
        captureMediaAuthorizationState(for: .video)
    }
    var onboardingStatusMessage: String {
        appShell.onboarding.state.statusMessage
    }

    private var activeScreenStartedAt: Date?
    private var activeFacecamStartedAt: Date?
    private var activeFacecamURL: URL?
    private var facecamPrewarmTask: Task<Void, Never>?
    private var backendRefreshTask: Task<Bool, Never>?
    private var backendRefreshGeneration = 0
    private var projectMutationVersion = 0
    private var projectMutationVersionsByPath: [String: Int] = [:]
    private var locallyPersistedProjectPaths: Set<String> = []
    private var capturePreflightTask: Task<Void, Never>?
    private var capturePreflightGeneration = 0
    private var pendingRecordingOptions: RecordingCaptureOptions?
    private var recordingFilePreparationTask: Task<Void, Never>?
    private var captureDeviceRefreshTask: Task<Void, Never>?
    private var captureDeviceRefreshGeneration = 0
    private var sourceRefreshGeneration = 0
    private var mediaImportTasksByPath: [String: Task<Void, Never>] = [:]
    private var mediaImportRequestIDsByPath: [String: UUID] = [:]
    @Published private(set) var isCapturePreflightRunning = false
    @Published private(set) var isTerminationPending = false
    private var displayFlashWindows: [NSWindow] = []
    private let countdownOverlayController = RecordingCountdownOverlayController()
    private let captureUIHideDelayNanoseconds: UInt64

    let service: RustServiceClient
    let capture: CaptureController
    let appShell = AppShellDriver()
    var captureMachine: CaptureDriver { appShell.capture }
    var captureOptions: CaptureOptionsDriver { appShell.captureOptions }
    var videoExport: VideoExportDriver { appShell.workspace(for: nil).videoExport }
    private let screenRecordingPermission: ScreenRecordingPermission
    private let accessibilityPermission: AccessibilityPermission
    private let onboardingStore: OnboardingStateStore
    private let recordingPreferences: RecordingPreferencesStore
    private let captureSetupPreferencesStore: CaptureSetupPreferencesStore
    private let screenSelectionPresenter: ScreenSelectionPresenting
    private let screenshotCapture: @MainActor (CaptureSource, URL) throws -> Void
    private let startRecordingCapture: @MainActor (CaptureSource, URL, RecordingCaptureOptions) async throws -> Date
    private let stopRecordingCapture: @MainActor () async throws -> URL
    private let rememberScreenshot: @Sendable (URL) throws -> Void
    private let trashProjectFile: @MainActor (URL) throws -> Void
    private let forgetProject: @Sendable (String) throws -> Void
    private let loadBackendSnapshot: @Sendable () async throws -> BackendSnapshot
    private let registerImportedMedia: @Sendable (EditorMediaKind, String) throws -> ProjectSummary
    private let registerCapturedMedia: @Sendable (String, Data) throws -> ProjectSummary
    private let prepareRecordingFilePath: @Sendable (String) throws -> PreparedFile
    private let prepareCameraPermission: (@MainActor () async -> Bool)?
    private let prepareFacecamRecording: (@MainActor (String?) async throws -> Void)?
    private let startFacecamRecording: (@MainActor (URL, String?) async throws -> Date)?
    private let stopFacecamRecording: (@MainActor () async throws -> URL?)?
    private let cancelFacecamRecording: (@MainActor () -> Void)?
    private let facecamRecorder = FacecamRecorder()
    private let cursorTelemetryRecorder = CursorTelemetryRecorder()
    private let captureDeviceProvider = CaptureDeviceProvider()
    private var nativeWindowCommandHandler: (NativeWindowCommand) -> Void = { _ in }
    private var runRecordingCountdown: @MainActor (CaptureSource) async throws -> Void = { _ in }
    private var storedCaptureSetup = CaptureSetupPreferences.default
    private var hasAttemptedStoredCaptureSetupRestore = false
    init(
        screenRecordingPermission: ScreenRecordingPermission = ScreenRecordingPermission(),
        accessibilityPermission: AccessibilityPermission = AccessibilityPermission(),
        onboardingStore: OnboardingStateStore = .live,
        recordingPreferences: RecordingPreferencesStore = RecordingPreferencesStore(),
        captureSetupPreferencesStore: CaptureSetupPreferencesStore = .ephemeral(),
        screenSelectionPresenter: ScreenSelectionPresenting = ScreenSelectionOverlayController(),
        captureUIHideDelayNanoseconds: UInt64 = 180_000_000,
        screenshotCapture: (@MainActor (CaptureSource, URL) throws -> Void)? = nil,
        startRecordingCapture: (@MainActor (CaptureSource, URL, RecordingCaptureOptions) async throws -> Date)? = nil,
        stopRecording: (@MainActor () async throws -> URL)? = nil,
        prepareCameraPermission: (@MainActor () async -> Bool)? = nil,
        prepareFacecamRecording: (@MainActor (String?) async throws -> Void)? = nil,
        startFacecamRecording: (@MainActor (URL, String?) async throws -> Date)? = nil,
        stopFacecamRecording: (@MainActor () async throws -> URL?)? = nil,
        cancelFacecamRecording: (@MainActor () -> Void)? = nil,
        runRecordingCountdown: (@MainActor (CaptureSource) async throws -> Void)? = nil,
        rememberScreenshot: (@Sendable (URL) throws -> Void)? = nil,
        trashProjectFile: (@MainActor (URL) throws -> Void)? = nil,
        forgetProject: (@Sendable (String) throws -> Void)? = nil,
        loadBackendSnapshot: (@Sendable () async throws -> BackendSnapshot)? = nil,
        registerImportedMedia: (@Sendable (EditorMediaKind, String) throws -> ProjectSummary)? = nil,
        registerCapturedMedia: (@Sendable (String, Data) throws -> ProjectSummary)? = nil,
        prepareRecordingFilePath: (@Sendable (String) throws -> PreparedFile)? = nil
    ) {
        let service = RustServiceClient()
        let capture = CaptureController(screenRecordingPermission: screenRecordingPermission)
        let preferences = recordingPreferences.load()
        self.service = service
        self.screenRecordingPermission = screenRecordingPermission
        self.accessibilityPermission = accessibilityPermission
        self.onboardingStore = onboardingStore
        self.recordingPreferences = recordingPreferences
        self.captureSetupPreferencesStore = captureSetupPreferencesStore
        self.storedCaptureSetup = captureSetupPreferencesStore.load()
        self.screenSelectionPresenter = screenSelectionPresenter
        self.captureUIHideDelayNanoseconds = captureUIHideDelayNanoseconds
        self.capture = capture
        self.screenshotCapture = screenshotCapture ?? { source, outputURL in
            try capture.takeScreenshot(source: source, outputURL: outputURL)
        }
        self.startRecordingCapture = startRecordingCapture ?? { source, outputURL, options in
            try await capture.startRecording(source: source, outputURL: outputURL, options: options)
        }
        self.stopRecordingCapture = stopRecording ?? {
            try await capture.stopRecording()
        }
        self.prepareCameraPermission = prepareCameraPermission
        self.prepareFacecamRecording = prepareFacecamRecording
        self.startFacecamRecording = startFacecamRecording
        self.stopFacecamRecording = stopFacecamRecording
        self.cancelFacecamRecording = cancelFacecamRecording
        self.rememberScreenshot = rememberScreenshot ?? { outputURL in
            let _: PreparedFile = try service.call(
                "rememberScreenshot",
                params: ["path": outputURL.path],
                as: PreparedFile.self
            )
        }
        self.trashProjectFile = trashProjectFile ?? { projectURL in
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: projectURL, resultingItemURL: &trashedURL)
        }
        self.forgetProject = forgetProject ?? { path in
            let _: ForgetProjectResult = try service.call(
                "forgetProject",
                params: ["path": path],
                as: ForgetProjectResult.self
            )
        }
        self.loadBackendSnapshot = loadBackendSnapshot ?? {
            async let health: HealthPayload = Task.detached(priority: .userInitiated) {
                try service.call("health", as: HealthPayload.self)
            }.value
            async let paths: AppPaths = Task.detached(priority: .userInitiated) {
                try service.call("paths", as: AppPaths.self)
            }.value
            async let projects: [ProjectSummary] = Task.detached(priority: .userInitiated) {
                try service.call("listProjects", as: [ProjectSummary].self)
            }.value
            return try await BackendSnapshot(
                health: health,
                paths: paths,
                projects: projects
            )
        }
        self.registerImportedMedia = registerImportedMedia ?? { kind, path in
            let title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let projects = try? service.call("listProjects", as: [ProjectSummary].self),
               let existing = projects.first(where: { project in
                   guard let mediaPath = project.mediaPath,
                         FileManager.default.fileExists(atPath: project.path) else {
                       return false
                   }
                   return canonicalMediaIdentity(for: URL(fileURLWithPath: mediaPath))
                       == canonicalMediaIdentity(for: URL(fileURLWithPath: path))
               }) {
                return existing
            }
            switch kind {
            case .video:
                return try service.call(
                    "registerRecording",
                    params: [
                        "path": path,
                        "sourceName": "Imported Recording",
                        "title": title,
                        "editorState": serviceJSONObject(for: ProjectEditorState.empty) ?? [:]
                    ],
                    as: ProjectSummary.self
                )
            case .screenshot:
                return try service.call(
                    "registerScreenshot",
                    params: [
                        "path": path,
                        "sourceName": "Imported Screenshot",
                        "title": title,
                        "editorState": serviceJSONObject(
                            for: ProjectEditorState(screenshot: ScreenshotEditorState.default)
                        ) ?? [:]
                    ],
                    as: ProjectSummary.self
                )
            }
        }
        self.registerCapturedMedia = registerCapturedMedia ?? { method, paramsData in
            try service.call(method, paramsData: paramsData, as: ProjectSummary.self)
        }
        self.prepareRecordingFilePath = prepareRecordingFilePath ?? { fileName in
            try service.call(
                "prepareRecordingFile",
                params: ["fileName": fileName],
                as: PreparedFile.self
            )
        }
        self.runRecordingCountdown = runRecordingCountdown ?? { [countdownOverlayController] source in
            try await countdownOverlayController.run(for: source)
        }
        appShell.configure(
            refreshBackend: { [weak self] in
                self?.refreshBackendState()
            },
            emitWindowCommand: { _ in },
            configureWorkspace: { [weak self] workspace in
                self?.configureEditorWorkspace(workspace)
            }
        )
        captureMachine.configure(
            transitionHandler: { [weak self] transition in
                guard let self else { return }
                self.captureState = transition.state
                self.captureOptions.send(.availabilityChanged(self.canChangeRecordingOptions))
                if let message = transition.statusMessage {
                    self.statusMessage = message
                }
            },
            effectHandlers: CaptureEffectHandlers(
                showHUD: { [weak self] in
                    self?.requestWindow(.showHUD)
                },
                hideHUD: { [weak self] in
                    self?.requestWindow(.hideHUD)
                },
                closeCaptureSetup: { [weak self] in
                    self?.requestWindow(.closeCaptureSetup)
                },
                showSourceSelector: { [weak self] in
                    self?.requestWindow(.showSourceSelector)
                },
                showAreaSelector: { [weak self] in
                    self?.requestWindow(.showAreaSelector)
                },
                showRecordingSetup: { [weak self] kind in
                    self?.requestWindow(kind == .display ? .showScreenRecordingSetup : .showRecordingSetup)
                },
                dismissScreenSelection: { [weak self] in
                    self?.screenSelectionPresenter.dismiss()
                },
                dismissCaptureWindows: { [weak self] in
                    self?.requestWindow(.hideRecordingSetup)
                },
                hideAppWindowsForCapture: { [weak self] in
                    self?.requestWindow(.hideAppWindowsForCapture)
                },
                focusActiveCaptureWindow: { [weak self] in
                    self?.focusActiveCaptureWindow()
                },
                flashDisplay: { [weak self] source in
                    self?.flashDisplay(for: source)
                },
                cancelRecordingStart: { [weak self] in
                    self?.countdownOverlayController.dismiss()
                },
                cancelScreenshotCapture: {},
                prepareRecordingFile: { [weak self] source in
                    self?.prepareRecordingFile(for: source)
                },
                runRecordingStart: { [weak self] source, outputURL in
                    await self?.runRecordingStartFlow(source: source, outputURL: outputURL)
                },
                stopRecording: { [weak self] source in
                    await self?.runRecordingStopFlow(source: source)
                },
                runScreenshotCapture: { [weak self] source in
                    await self?.runScreenshotCapture(source: source)
                }
            )
        )
        captureOptions.configure(
            refreshDevices: { [weak self] in
                guard let self else { return ([], []) }
                let microphones = self.captureDeviceProvider.devices(for: .audio)
                let cameras = self.captureDeviceProvider.devices(for: .video)
                return (microphones, cameras)
            },
            requestWindow: { [weak self] action in
                self?.requestWindow(action)
            },
            setStatusMessage: { [weak self] message in
                self?.statusMessage = message
            },
            stateWillChange: { [weak self] in
                self?.objectWillChange.send()
            }
        )
        appShell.onboarding.configure(
            currentPermissions: { [weak self] in
                guard let self else { return (.requestAvailable, .requestAvailable) }
                return (
                    self.screenRecordingPermission.currentState(),
                    self.accessibilityPermission.currentState()
                )
            },
            requestScreenPermission: { [weak self] in
                self?.requestScreenRecordingPermission() ?? .promptAlreadyShown
            },
            requestAccessibilityPermission: { [weak self] in
                self?.requestAccessibilityPermission() ?? .promptAlreadyShown
            },
            openScreenRecordingSettings: { [weak self] in
                self?.openPrivacySettings()
            },
            openAccessibilitySettings: { [weak self] in
                self?.openAccessibilitySettings()
            },
            completeOnboarding: { [weak self] in
                self?.persistCompletedOnboarding() ?? false
            },
            stateWillChange: { [weak self] in
                self?.objectWillChange.send()
            }
        )
        appShell.settings.configure(
            refreshService: { [weak self] in
                self?.refreshBackendState()
            },
            persistAutoZoomPreference: { [weak self] value in
                self?.recordingPreferences.setCreatesZoomsAutomatically(value)
            },
            persistAutoZoomAnimationPreset: { [weak self] preset in
                self?.recordingPreferences.setAutoZoomAnimationPreset(preset)
            },
            openFolder: { [weak self] path in
                self?.openPath(path)
            },
            openScreenRecordingSettings: { [weak self] in
                self?.openPrivacySettings()
            },
            openAccessibilitySettings: { [weak self] in
                self?.openAccessibilitySettings()
            },
            showOnboarding: { [weak self] in
                self?.showOnboarding()
            },
            stateWillChange: { [weak self] in
                self?.objectWillChange.send()
            }
        )
        appShell.settings.send(.autoZoomPreferenceSynced(preferences.createsZoomsAutomatically))
        appShell.settings.send(.autoZoomAnimationPresetSynced(preferences.autoZoomAnimationPreset))
        refreshOnboardingPermissionStates()
        syncAppShellMirror()
        dispatch(.restoreSetup(
            storedCaptureSetup.mode,
            nil,
            preferredSourceKind: storedCaptureSetup.preferredSourceKind
        ))
    }

    private func configureEditorWorkspace(_ workspace: EditorWorkspaceDriver) {
        workspace.configure(
            setAppSection: { [weak self] section in
                self?.selectedSection = section
            },
            setStatusMessage: { [weak self] message in
                self?.statusMessage = message
            }
        )
        workspace.videoExport.configure(
            renderVideo: { sourceURL, targetURL, options, cancellationToken, edits, progressHandler in
                try await VideoExportRenderer.export(
                    sourceURL: sourceURL,
                    targetURL: targetURL,
                    options: options,
                    cancellationToken: cancellationToken,
                    edits: edits,
                    progressHandler: progressHandler
                )
            },
            temporaryURL: { [weak self] options in
                self?.temporaryVideoExportURL(options: options)
                    ?? FileManager.default.temporaryDirectory
                        .appendingPathComponent("open-recorder-export-\(UUID().uuidString)")
                        .appendingPathExtension(options.format.fileExtension)
            },
            saveDestination: { [weak self] sourceURL, options in
                self?.videoExportSaveDestination(sourceURL: sourceURL, options: options)
            },
            copyFile: { sourceURL, targetURL in
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            },
            deleteFile: { url in
                try? FileManager.default.removeItem(at: url)
            },
            revealFile: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            setStatusMessage: { [weak workspace] message in
                guard let workspace else { return }
                workspace.send(.statusUpdated(EditorWorkspaceStatus(
                    message: message,
                    severity: workspace.videoExport.state.phase.editorWorkspaceStatusSeverity
                )))
            }
        )
    }

    func prepareForTermination() async -> Bool {
        guard !isTerminationPending else { return false }
        guard !hasActiveCaptureWork else {
            statusMessage = "Finish or cancel the current capture before quitting."
            focusActiveCaptureWindow()
            return false
        }
        isTerminationPending = true

        while !mediaImportTasksByPath.isEmpty {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                isTerminationPending = false
                return false
            }
            guard !hasActiveCaptureWork else {
                isTerminationPending = false
                statusMessage = "Finish or cancel the current capture before quitting."
                focusActiveCaptureWindow()
                return false
            }
        }

        let canTerminate = await appShell.prepareForTermination()
        guard canTerminate else {
            isTerminationPending = false
            requestWindow(
                .showStudio,
                editorSession: appShell.terminationBlockingEditorSession
            )
            return false
        }
        guard !hasActiveCaptureWork,
              mediaImportTasksByPath.isEmpty else {
            isTerminationPending = false
            statusMessage = "Finish or cancel the current capture before quitting."
            focusActiveCaptureWindow()
            return false
        }
        // Keep mutations gated after the final fixed-point check. The app delegate
        // immediately replies to AppKit and the process terminates from this state.
        return true
    }

    private var hasActiveCaptureWork: Bool {
        if capture.isRecording || isCapturePreflightRunning {
            return true
        }
        switch captureState.phase {
        case .countingDownRecording, .startingRecording, .recording, .stoppingRecording, .capturingScreenshot:
            return true
        case .idle, .setup, .sourceSelecting, .choosingMode, .choosingSourceType, .screenSelecting, .selectingSource, .ready, .areaSelecting:
            return false
        }
    }

    private func rejectActionWhileTerminationIsPending() -> Bool {
        guard isTerminationPending else { return false }
        statusMessage = "Open Recorder is finishing pending work before quitting."
        return true
    }

    var captureMode: CaptureMode {
        captureState.mode ?? .recording
    }

    var hudState: HUDState {
        captureState
    }

    var selectedSource: CaptureSource? {
        captureState.source
    }

    var preferredSourceSelectorKind: CaptureSourceKind? {
        captureState.preferredSourceKind ?? captureState.source?.kind
    }

    var recordingPhase: RecordingPhase {
        captureState.recordingPhase
    }

    var isAreaSelectionActive: Bool {
        captureState.isAreaSelectionActive
    }

    func setCaptureStateForTesting(_ state: CaptureState) {
        setCaptureStateMirror(state)
    }

    private func setCaptureStateMirror(_ state: CaptureState) {
        captureMachine.setStateForTesting(state)
        captureState = state
        captureOptions.send(.availabilityChanged(canChangeRecordingOptions))
    }

    private func sendAppShell(_ event: AppShellEvent) {
        let previousCommandID = appShell.state.windowCommand?.id
        appShell.send(event)
        syncAppShellMirror()
        if let command = appShell.state.windowCommand,
           command.id != previousCommandID {
            nativeWindowCommandHandler(command)
        }
    }

    private func syncAppShellMirror() {
        objectWillChange.send()
    }

    var captureFlow: CaptureFlow {
        captureState.captureFlow
    }

    var isHUDVisible: Bool {
        captureState.presentation.isVisible
    }

    var canShowCaptureUI: Bool {
        captureState.canShowCaptureUI
    }

    var canChangeRecordingOptions: Bool {
        !isCapturePreflightRunning &&
            captureState.canChangeRecordingOptions(runtimeIsRecording: capture.isRecording)
    }

    func bootstrap() {
        presentOnboardingIfNeeded()
        Task {
            await refreshSources()
            refreshCaptureDevices()
        }
        sendAppShell(.bootstrapRequested)
    }

    var canContinueOnboarding: Bool {
        appShell.onboarding.state.canContinue
    }

    func refreshOnboardingPermissionStates() {
        appShell.onboarding.send(.permissionsRefreshed(
            screen: screenRecordingPermission.currentState(),
            accessibility: accessibilityPermission.currentState()
        ))
    }

    func presentOnboardingIfNeeded() {
        guard !onboardingStore.isCompleted() else {
            return
        }
        showOnboarding()
    }

    func showOnboarding() {
        refreshOnboardingPermissionStates()
        setCaptureStateMirror(captureState.withPresentation(.hidden))
        requestWindow(.showOnboarding)
    }

    @discardableResult
    func requestOnboardingScreenRecordingPermission() -> ScreenRecordingPermissionRequestOutcome {
        let outcome = requestScreenRecordingPermission()
        appShell.onboarding.send(.screenPermissionRequested(outcome))
        return outcome
    }

    private func requestScreenRecordingPermission() -> ScreenRecordingPermissionRequestOutcome {
        switch screenRecordingPermission.currentState() {
        case .granted:
            return .granted
        case .requestAvailable:
            return screenRecordingPermission.requestGrant()
        case .requestAlreadyShown:
            return .promptAlreadyShown
        }
    }

    @discardableResult
    func requestOnboardingAccessibilityPermission() -> AccessibilityPermissionRequestOutcome {
        let outcome = requestAccessibilityPermission()
        appShell.onboarding.send(.accessibilityPermissionRequested(outcome))
        return outcome
    }

    private func requestAccessibilityPermission() -> AccessibilityPermissionRequestOutcome {
        switch accessibilityPermission.currentState() {
        case .granted:
            return .granted
        case .requestAvailable:
            return accessibilityPermission.requestGrant()
        case .requestAlreadyShown:
            return .promptAlreadyShown
        }
    }

    @discardableResult
    func completeOnboarding() -> Bool {
        refreshOnboardingPermissionStates()
        let canComplete = canContinueOnboarding
        appShell.onboarding.send(.continueRequested)
        return canComplete
    }

    private func persistCompletedOnboarding() -> Bool {
        onboardingStore.setCompleted(true)
        statusMessage = "Ready"
        setCaptureStateMirror(captureState.withPresentation(.visible))
        requestWindow(.finishOnboarding)
        return true
    }

    @discardableResult
    func refreshBackendState() -> Task<Bool, Never> {
        backendRefreshGeneration += 1
        let generation = backendRefreshGeneration
        let projectVersionAtStart = projectMutationVersion
        backendRefreshTask?.cancel()
        sendAppShell(.backendRefreshStarted)
        appShell.settings.send(.serviceRefreshStarted)

        let loadBackendSnapshot = loadBackendSnapshot
        let task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return BackendLoadOutcome.success(try await loadBackendSnapshot())
                } catch {
                    return BackendLoadOutcome.failure(error.localizedDescription)
                }
            }.value

            guard !Task.isCancelled,
                  let self,
                  generation == self.backendRefreshGeneration else {
                return false
            }

            switch outcome {
            case .success(let snapshot):
                self.locallyPersistedProjectPaths.subtract(snapshot.projects.map(\.path))
                let projects = self.projectsMergingConcurrentMutations(
                    into: snapshot.projects,
                    since: projectVersionAtStart
                )
                self.sendAppShell(.backendRefreshed(
                    paths: snapshot.paths,
                    projects: projects,
                    health: snapshot.health
                ))
                self.projectMutationVersionsByPath = self.projectMutationVersionsByPath.filter {
                    $0.value > projectVersionAtStart
                }
                self.appShell.settings.send(.serviceRefreshSucceeded)
                return true
            case .failure(let message):
                self.sendAppShell(.backendRefreshFailed(message))
                self.appShell.settings.send(.serviceRefreshFailed(message))
                return false
            }
        }
        backendRefreshTask = task
        return task
    }

    func reloadSources() {
        Task {
            await refreshSources()
        }
    }

    func reloadSourcesForPreview() {
        Task {
            await refreshSources(requestScreenRecordingPermission: true)
        }
    }

    func refreshSources(requestScreenRecordingPermission: Bool = false) async {
        sourceRefreshGeneration += 1
        let generation = sourceRefreshGeneration
        await capture.reloadSources(requestScreenRecordingPermission: requestScreenRecordingPermission)
        guard !Task.isCancelled, generation == sourceRefreshGeneration else { return }

        if let selectedSource {
            let resolved = resolveSelection(previous: selectedSource, in: capture.sources)
            dispatch(.refreshSelectedSource(resolved))
        } else if !hasAttemptedStoredCaptureSetupRestore {
            hasAttemptedStoredCaptureSetupRestore = true
            let restoredSource = storedCaptureSetup.sourceReference?.resolve(
                in: capture.sources,
                displayFrames: NSScreen.captureDisplayFramesByID
            )
            dispatch(.restoreSetup(
                storedCaptureSetup.mode,
                restoredSource,
                preferredSourceKind: storedCaptureSetup.preferredSourceKind
            ))
        }
    }

    private func resolveSelection(previous: CaptureSource?, in sources: [CaptureSource]) -> CaptureSource? {
        guard let previous else {
            return nil
        }
        if previous.kind == .area {
            return previous
        }
        if let match = sources.first(where: { matchesIdentity($0, previous) }) {
            return match
        }
        return nil
    }

    private func matchesIdentity(_ candidate: CaptureSource, _ reference: CaptureSource) -> Bool {
        guard candidate.kind == reference.kind else {
            return false
        }
        switch candidate.kind {
        case .display:
            if let candidateID = candidate.displayID, let referenceID = reference.displayID {
                return candidateID == referenceID
            }
            return candidate.id == reference.id
        case .window:
            if candidate.windowID != nil || reference.windowID != nil {
                return candidate.windowID == reference.windowID
                    && candidate.ownerBundleID == reference.ownerBundleID
            }
            if let bundleID = reference.ownerBundleID,
               candidate.ownerBundleID == bundleID,
               candidate.name == reference.name,
               !candidate.name.isEmpty {
                return true
            }
            return false
        case .area:
            return candidate.id == reference.id
        }
    }

    private func persistCaptureSetup(source: CaptureSource) {
        storedCaptureSetup.mode = captureMode
        storedCaptureSetup.preferredSourceKind = source.kind
        storedCaptureSetup.sourceReference = CaptureSourceReference(source: source)
        saveCaptureSetupPreferences()
    }

    private func saveCaptureSetupPreferences() {
        captureSetupPreferencesStore.save(storedCaptureSetup)
    }

    private func isRecordingSetup(for source: CaptureSource? = nil) -> Bool {
        let isSetupPhase: Bool
        switch captureState.phase {
        case .setup(.recording), .ready(.recording, _):
            isSetupPhase = true
        default:
            isSetupPhase = false
        }
        guard isSetupPhase, let currentSource = captureState.source else { return false }
        return source == nil || currentSource.id == source?.id
    }

    @discardableResult
    private func dispatch(_ event: CaptureEvent) -> CaptureTransition {
        captureMachine.send(event)
    }

    private func prepareRecordingFile(for source: CaptureSource) {
        recordingFilePreparationTask?.cancel()
        statusMessage = "Preparing recording…"
        let fileName = timestampedFileName(prefix: "recording", extension: "mp4")
        let prepareRecordingFilePath = prepareRecordingFilePath
        recordingFilePreparationTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    let prepared = try prepareRecordingFilePath(fileName)
                    return RecordingFilePreparationOutcome.success(URL(fileURLWithPath: prepared.path))
                } catch {
                    return RecordingFilePreparationOutcome.failure(error.localizedDescription)
                }
            }.value

            guard !Task.isCancelled, let self else { return }
            self.recordingFilePreparationTask = nil
            self.isCapturePreflightRunning = false
            self.captureOptions.send(.availabilityChanged(self.canChangeRecordingOptions))
            guard self.isRecordingSetup(for: source) else {
                self.pendingRecordingOptions = nil
                return
            }
            switch outcome {
            case .success(let outputURL):
                self.dispatch(.recordingFilePrepared(source, outputURL))
            case .failure(let message):
                self.pendingRecordingOptions = nil
                self.dispatch(.recordingFilePreparationFailed(source, message: message))
            }
        }
    }

    var canStartNewCapture: Bool {
        captureState.canStartNewCapture(runtimeIsRecording: capture.isRecording)
    }

    func beginCapture(_ mode: CaptureMode) {
        guard !rejectActionWhileTerminationIsPending() else { return }
        let transition = dispatch(.beginCapture(mode, runtimeIsRecording: capture.isRecording))
        guard transition.state.mode == mode else { return }
        storedCaptureSetup.mode = mode
        saveCaptureSetupPreferences()
    }

    func selectSource(_ source: CaptureSource) {
        let shouldCaptureImmediately = captureMode == .screenshot
        dispatch(.selectSource(source))
        persistCaptureSetup(source: source)
        if shouldCaptureImmediately {
            takeScreenshot()
        }
    }

    func selectInteractiveAreaSource(area: CaptureArea? = nil) {
        dispatch(.selectSource(interactiveAreaSource(area: area)))
    }

    private func interactiveAreaSource(area: CaptureArea? = nil) -> CaptureSource {
        CaptureSource(
            id: "area:interactive",
            kind: .area,
            name: "Selected Area",
            subtitle: area.map { "\($0.width) x \($0.height)" } ?? "Draw area when capture starts",
            displayIndex: nil,
            displayID: area?.displayID,
            windowID: nil,
            area: area,
            thumbnailData: nil
        )
    }

    func chooseSourceType(_ sourceType: CaptureSourceType) {
        switch sourceType {
        case .screen:
            requestSourceSelector(kind: .display)
        case .window:
            requestSourceSelector(kind: .window)
        case .area:
            requestSourceSelector(kind: .area)
        }
    }

    func requestSourceSelector(kind: CaptureSourceKind? = nil) {
        dispatch(.requestSourceSelector(kind))
    }

    func cancelSourceSelection() {
        dispatch(.cancelSourceSelection)
        requestWindow(.closeSourceSelector)
    }

    func requestScreenSelection() {
        dispatch(.requestScreenSelection)
        presentCurrentScreenSelection()
    }

    func completeScreenSelection(_ source: CaptureSource) {
        dispatch(.completeScreenSelection(source))
    }

    func cancelScreenSelection(message: String? = nil) {
        dispatch(.cancelScreenSelection(message: message))
    }

    private func presentCurrentScreenSelection() {
        guard case .screenSelecting(let mode) = captureState.phase else {
            return
        }

        let currentDisplaySources = capture.sources.filter { $0.kind == .display }
        guard currentDisplaySources.isEmpty else {
            presentScreenSelection(displaySources: currentDisplaySources, mode: mode)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.refreshSources(requestScreenRecordingPermission: true)
            let displaySources = self.capture.sources.filter { $0.kind == .display }
            self.presentScreenSelection(displaySources: displaySources, mode: mode)
        }
    }

    private func presentScreenSelection(displaySources: [CaptureSource], mode: CaptureMode) {
        guard case .screenSelecting(let activeMode) = captureState.phase,
              activeMode == mode else {
            return
        }

        guard !displaySources.isEmpty else {
            cancelScreenSelection(message: "No screens available.")
            return
        }

        screenSelectionPresenter.present(
            displaySources: displaySources,
            onSelect: { [weak self] source in
                self?.completeScreenSelection(source)
            },
            onCancel: { [weak self] in
                self?.cancelScreenSelection()
            }
        )
    }

    func requestInteractiveAreaSelection() {
        guard !rejectActionWhileTerminationIsPending() else { return }
        if captureMode == .screenshot,
           !ensureScreenRecordingPermissionForCapture() {
            showHUD()
            return
        }
        dispatch(.requestInteractiveAreaSelection)
    }

    func completeInteractiveAreaSelection(_ area: CaptureArea) {
        guard !rejectActionWhileTerminationIsPending() else { return }
        let source = interactiveAreaSource(area: area)
        let shouldCaptureImmediately = captureMode == .screenshot
        if captureMode == .screenshot,
           capture.screenRecordingPermissionState != .granted {
            dispatch(.completeInteractiveAreaSelection(source))
            persistCaptureSetup(source: source)
            showHUD()
            reportCaptureBlocker(.screenRecordingPermissionNeedsRestart)
            return
        }
        dispatch(.completeInteractiveAreaSelection(source))
        persistCaptureSetup(source: source)
        if shouldCaptureImmediately {
            takeScreenshot()
        }
    }

    func cancelInteractiveAreaSelection() {
        dispatch(.cancelInteractiveAreaSelection)
    }

    func cancelCapture() {
        capturePreflightGeneration += 1
        capturePreflightTask?.cancel()
        capturePreflightTask = nil
        recordingFilePreparationTask?.cancel()
        recordingFilePreparationTask = nil
        pendingRecordingOptions = nil
        isCapturePreflightRunning = false
        captureOptions.send(.availabilityChanged(canChangeRecordingOptions))
        dispatch(.cancelCapture)
    }

    func requestWindow(_ action: NativeWindowCommandAction, editorSession: EditorSession? = nil) {
        sendAppShell(.windowCommandRequested(action, editorSession: editorSession))
    }

    func installNativeWindowCommandHandler(_ handler: @escaping (NativeWindowCommand) -> Void) {
        nativeWindowCommandHandler = handler
        if let command = appShell.state.windowCommand {
            nativeWindowCommandHandler(command)
        }
    }

    func showHUD() {
        dispatch(.showHUD)
    }

    func hideHUD() {
        dispatch(.hideHUD)
    }

    func toggleHUDPresentation() {
        if hudState.presentation == .visible {
            hideHUD()
        } else {
            showHUD()
        }
    }

    func showEditor(for session: EditorSession) {
        dispatch(.showEditor)
        sendAppShell(.editorSessionShown(session))
    }

    var windowCommand: NativeWindowCommand? {
        appShell.state.windowCommand
    }

    func consumeWindowCommand(_ command: NativeWindowCommand?) -> NativeWindowCommand? {
        guard let command, appShell.state.windowCommand?.id == command.id else {
            return nil
        }
        sendAppShell(.windowCommandConsumed(command.id))
        return command
    }

    private func focusActiveCaptureWindow() {
        switch captureState.phase {
        case .sourceSelecting, .selectingSource:
            requestWindow(.showSourceSelector)
        case .ready(_, let source):
            if source.kind == .display {
                requestWindow(.showHUD)
            } else {
                requestWindow(.showSourceSelector)
            }
        case .areaSelecting:
            requestWindow(.showAreaSelector)
        case .choosingSourceType:
            showHUD()
        case .screenSelecting:
            requestWindow(.showHUD)
        case .countingDownRecording, .startingRecording, .recording, .stoppingRecording, .capturingScreenshot:
            setCaptureStateMirror(captureState.withPresentation(.hidden))
        case .idle, .setup, .choosingMode:
            showHUD()
        }
    }

    func toggleRecordingShortcut() {
        guard !rejectActionWhileTerminationIsPending() else { return }
        switch captureState.phase {
        case .setup(.recording):
            startRecording()
        case .ready(.recording, _):
            startRecording()
        case .countingDownRecording:
            cancelCountdownRecording()
        case .startingRecording:
            dispatch(.recordingStopRequested)
        case .recording:
            stopRecording()
        case .stoppingRecording:
            return
        case .idle,
             .setup,
             .sourceSelecting,
             .choosingMode,
             .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .ready,
             .areaSelecting,
             .capturingScreenshot:
            return
        }
    }

    func startRecording() {
        guard !rejectActionWhileTerminationIsPending() else { return }
        guard !isCapturePreflightRunning,
              isRecordingSetup() else {
            return
        }

        capturePreflightTask?.cancel()
        capturePreflightGeneration += 1
        let generation = capturePreflightGeneration
        let options = currentCaptureOptions
        pendingRecordingOptions = options
        isCapturePreflightRunning = true
        captureOptions.send(.availabilityChanged(false))
        statusMessage = "Checking capture readiness…"
        capturePreflightTask = Task { [weak self] in
            guard let self else { return }
            guard self.ensureScreenRecordingPermissionForCapture() else {
                self.finishCapturePreflight(generation: generation)
                return
            }

            if self.captureState.source?.kind != .area {
                await self.refreshSources()
            }
            guard !Task.isCancelled, generation == self.capturePreflightGeneration else {
                self.finishCapturePreflight(generation: generation)
                return
            }

            guard await self.preparePermissions(for: options) else {
                self.finishCapturePreflight(generation: generation)
                return
            }
            guard !Task.isCancelled, generation == self.capturePreflightGeneration else {
                self.finishCapturePreflight(generation: generation)
                return
            }
            if options.includeMicrophone || options.includeCamera {
                await self.refreshCaptureDevicesForPreflight()
            }
            guard !Task.isCancelled, generation == self.capturePreflightGeneration else {
                self.finishCapturePreflight(generation: generation)
                return
            }

            let readiness = self.captureState.readiness(
                availableSources: self.sourcesForReadiness,
                screenRecordingPermissionState: self.capture.screenRecordingPermissionState,
                options: self.captureOptions.state,
                runtimeIsRecording: self.capture.isRecording,
                microphoneAuthorization: self.microphoneCaptureAuthorization,
                cameraAuthorization: self.cameraCaptureAuthorization
            )
            guard readiness.canCapture else {
                if let blocker = readiness.primaryBlocker {
                    self.reportCaptureBlocker(blocker)
                }
                self.finishCapturePreflight(generation: generation)
                return
            }

            guard generation == self.capturePreflightGeneration else { return }
            self.capturePreflightTask = nil
            self.dispatch(.recordingStartRequested)
        }
    }

    private func runRecordingStartFlow(source selectedSource: CaptureSource, outputURL: URL) async {
        do {
            var options = pendingRecordingOptions ?? currentCaptureOptions
            pendingRecordingOptions = nil

            if options.includeCamera {
                do {
                    try await prepareFacecam(cameraDeviceID: options.cameraDeviceID)
                } catch {
                    captureOptions.send(.cameraDisabledForCaptureFailure)
                    options.includeCamera = false
                    options.cameraDeviceID = nil
                    statusMessage = "Recording without facecam: \(error.localizedDescription)"
                }
            }

            try await runRecordingCountdown(selectedSource)
            guard !Task.isCancelled else { return }

            dispatch(.recordingStarting(selectedSource))

            activeFacecamURL = nil
            activeFacecamStartedAt = nil
            if options.includeCamera {
                let url = facecamOutputURL(for: outputURL)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                let cameraDeviceID = options.cameraDeviceID
                do {
                    activeFacecamStartedAt = try await startFacecam(outputURL: url, cameraDeviceID: cameraDeviceID)
                    activeFacecamURL = url
                } catch {
                    captureOptions.send(.cameraDisabledForCaptureFailure)
                    options.includeCamera = false
                    options.cameraDeviceID = nil
                    try? FileManager.default.removeItem(at: url)
                    activeFacecamURL = nil
                    activeFacecamStartedAt = nil
                    statusMessage = "Recording without facecam: \(error.localizedDescription)"
                }
            }

            cursorTelemetryRecorder.start(for: selectedSource)
            let screenStartedAt = try await startRecordingCapture(selectedSource, outputURL, options)
            cursorTelemetryRecorder.alignStart(to: screenStartedAt)
            activeScreenStartedAt = screenStartedAt

            currentVideoURL = outputURL
            currentScreenshotURL = nil
            let shouldStopAfterStart: Bool
            if case .startingRecording(_, let stopRequested) = captureState.phase {
                shouldStopAfterStart = stopRequested
            } else {
                shouldStopAfterStart = false
            }
            let facecamStatusMessage = statusMessage.hasPrefix("Recording without facecam") ? statusMessage : nil
            dispatch(.recordingStarted(selectedSource))
            if let facecamStatusMessage {
                statusMessage = facecamStatusMessage
            }
            if shouldStopAfterStart {
                stopRecording()
            }
        } catch is CancellationError {
            countdownOverlayController.dismiss()
            if recordingPhase == .countingDown {
                restoreRecordingSetup(source: selectedSource, message: "Recording canceled.")
            }
        } catch {
            cancelFacecam()
            if let partialURL = activeFacecamURL {
                try? FileManager.default.removeItem(at: partialURL)
            } else {
                try? FileManager.default.removeItem(at: facecamOutputURL(for: outputURL))
            }
            _ = cursorTelemetryRecorder.stop(videoURL: nil)
            activeScreenStartedAt = nil
            activeFacecamStartedAt = nil
            activeFacecamURL = nil
            restoreRecordingSetup(source: selectedSource, message: error.localizedDescription)
        }
    }

    private func cancelCountdownRecording() {
        guard case .countingDownRecording = captureState.phase else { return }
        dispatch(.recordingStopRequested)
    }

    private func restoreRecordingSetup(source: CaptureSource, message: String? = nil) {
        countdownOverlayController.dismiss()
        dispatch(.recordingRestored(source, message: message ?? statusMessage))
    }

    func stopRecording() {
        guard recordingPhase != .idle || capture.isRecording else {
            return
        }
        if recordingPhase == .idle, capture.isRecording {
            dispatch(.recordingStopping(captureState.source))
        } else {
            dispatch(.recordingStopRequested)
        }
    }

    private func runRecordingStopFlow(source: CaptureSource?) async {
        do {
            let outputURL = try await stopRecordingCapture()
            let stoppedFacecamURL = try? await stopFacecam()
            let cursorTelemetryURL = cursorTelemetryRecorder.stop(videoURL: outputURL)
            currentVideoURL = outputURL
            currentScreenshotURL = nil

            if FileManager.default.fileExists(atPath: outputURL.path) {
                let timelineEdits = await initialTimelineEdits(
                    videoURL: outputURL,
                    cursorTelemetryURL: cursorTelemetryURL
                )
                let sourceName = source?.name ?? selectedSource?.name
                let recordingSession = RecordingSessionBuilder.build(
                    screenVideoURL: outputURL,
                    facecamURL: stoppedFacecamURL ?? activeFacecamURL,
                    sourceName: sourceName,
                    showCursor: showCursor,
                    cursorTelemetryURL: cursorTelemetryURL,
                    screenStartedAt: activeScreenStartedAt,
                    facecamStartedAt: activeFacecamStartedAt
                )
                let summary = await registerRecordingProject(
                    outputURL,
                    sourceName: sourceName,
                    timelineEdits: timelineEdits,
                    recordingSession: recordingSession
                )
                let title = summary.summary?.title ?? outputURL.deletingPathExtension().lastPathComponent
                showEditor(for: EditorSession(
                    kind: .video,
                    url: outputURL,
                    title: title,
                    projectPath: summary.summary?.path,
                    recordingSession: recordingSession,
                    timelineEditSnapshot: timelineEdits
                ))
                if case .failed(let message) = summary {
                    statusMessage = "Saved \(title), but the editable project could not be created: \(message)"
                } else {
                    statusMessage = "Saved \(title)"
                }
            } else {
                dispatch(.recordingStopped(message: "Recording stopped before a file was written."))
            }
        } catch {
            _ = cursorTelemetryRecorder.stop(videoURL: nil)
            if let source {
                dispatch(.recordingFailed(source, message: error.localizedDescription))
            } else {
                dispatch(.recordingFailed(nil, message: error.localizedDescription))
            }
        }
        activeScreenStartedAt = nil
        activeFacecamStartedAt = nil
        activeFacecamURL = nil
    }

    func takeScreenshot() {
        guard !rejectActionWhileTerminationIsPending() else { return }
        guard !capture.isRecording else {
            statusMessage = "Finish or cancel the current capture before starting another."
            focusActiveCaptureWindow()
            return
        }
        guard ensureScreenRecordingPermissionForCapture() else { return }
        let readiness = captureState.readiness(
            availableSources: sourcesForReadiness,
            screenRecordingPermissionState: capture.screenRecordingPermissionState,
            options: captureOptions.state,
            runtimeIsRecording: capture.isRecording,
            microphoneAuthorization: microphoneCaptureAuthorization,
            cameraAuthorization: cameraCaptureAuthorization,
            isChecking: capture.sourceCatalogState == .loading
        )
        guard readiness.canCapture else {
            if let blocker = readiness.primaryBlocker {
                reportCaptureBlocker(blocker)
            } else if readiness.isChecking {
                statusMessage = "Refreshing capture sources…"
            }
            return
        }
        dispatch(.screenshotRequested)
    }

    private func runScreenshotCapture(source selectedSource: CaptureSource) async {
        do {
            if captureUIHideDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: captureUIHideDelayNanoseconds)
            } else {
                await Task.yield()
            }
            try Task.checkCancellation()
            guard isActiveScreenshotCapture(for: selectedSource) else {
                throw CancellationError()
            }

            let ensuredPaths: AppPaths
            if let paths {
                ensuredPaths = paths
            } else {
                ensuredPaths = try await loadAppPaths()
            }
            try Task.checkCancellation()
            guard isActiveScreenshotCapture(for: selectedSource) else {
                throw CancellationError()
            }
            let outputURL = URL(fileURLWithPath: ensuredPaths.screenshotsDir)
                .appendingPathComponent(timestampedFileName(prefix: "screenshot", extension: "png"))
            try screenshotCapture(selectedSource, outputURL)
            try Task.checkCancellation()
            guard isActiveScreenshotCapture(for: selectedSource) else {
                throw CancellationError()
            }
            let registration = await registerScreenshotProject(outputURL, sourceName: selectedSource.name)
            try Task.checkCancellation()
            guard isActiveScreenshotCapture(for: selectedSource) else {
                throw CancellationError()
            }
            currentScreenshotURL = outputURL
            currentVideoURL = nil
            showEditor(for: EditorSession(
                kind: .screenshot,
                url: outputURL,
                title: registration.summary?.title,
                projectPath: registration.summary?.path,
                screenshotEditorState: .default
            ))
            if case .failed(let message) = registration {
                statusMessage = "Captured \(outputURL.lastPathComponent), but the editable project could not be created: \(message)"
            } else {
                statusMessage = "Captured \(outputURL.lastPathComponent)"
            }
            if registration.needsScreenshotIndexRetry {
                rememberScreenshotInBackground(outputURL)
            }
        } catch is CancellationError {
            if case .capturingScreenshot(let activeSource) = captureState.phase,
               activeSource.id == selectedSource.id {
                restoreScreenshotSetup(source: selectedSource, message: "Screenshot canceled.")
            }
        } catch {
            restoreScreenshotSetup(source: selectedSource, message: error.localizedDescription)
        }
    }

    private func restoreScreenshotSetup(source: CaptureSource, message: String) {
        dispatch(.screenshotRestored(source, message: message))
    }

    private func isActiveScreenshotCapture(for source: CaptureSource) -> Bool {
        if case .capturingScreenshot(let activeSource) = captureState.phase {
            return activeSource.id == source.id
        }
        return false
    }

    private func rememberScreenshotInBackground(_ outputURL: URL) {
        let rememberScreenshot = rememberScreenshot
        DispatchQueue.global(qos: .utility).async {
            try? rememberScreenshot(outputURL)
        }
    }

    private func loadAppPaths() async throws -> AppPaths {
        let service = service
        return try await Task.detached(priority: .utility) {
            try service.call("paths", as: AppPaths.self)
        }.value
    }

    private func registerScreenshotProject(
        _ outputURL: URL,
        sourceName: String?
    ) async -> CapturedProjectRegistrationOutcome {
        let title = outputURL.deletingPathExtension().lastPathComponent
        let editorState = ProjectEditorState(screenshot: ScreenshotEditorState.default)
        do {
            let params: [String: Any] = [
                "path": outputURL.path,
                "sourceName": sourceName ?? "Screenshot",
                "title": title,
                "editorState": jsonObject(for: editorState) ?? [:]
            ]
            let paramsData = try JSONSerialization.data(withJSONObject: params)
            let registerCapturedMedia = registerCapturedMedia
            let summary: ProjectSummary = try await Task.detached(priority: .utility) {
                try registerCapturedMedia("registerScreenshot", paramsData)
            }.value
            upsertProjectSummary(summary)
            return .indexed(summary)
        } catch let registrationError {
            return await persistCapturedProjectLocally(
                title: title,
                recordingURL: nil,
                screenshotURL: outputURL,
                sourceName: sourceName,
                editorState: editorState,
                recordingSession: nil,
                registrationError: registrationError
            )
        }
    }

    private func registerRecordingProject(
        _ outputURL: URL,
        sourceName: String?,
        timelineEdits: TimelineEditSnapshot,
        recordingSession: RecordingSession
    ) async -> CapturedProjectRegistrationOutcome {
        let title = outputURL.deletingPathExtension().lastPathComponent
        let editorState = ProjectEditorState(timelineEdits: timelineEdits)
        do {
            let params: [String: Any] = [
                "path": outputURL.path,
                "sourceName": sourceName ?? "Screen Recording",
                "title": title,
                "editorState": jsonObject(for: editorState) ?? [:],
                "recordingSession": jsonObject(for: recordingSession) ?? [:]
            ]
            let paramsData = try JSONSerialization.data(withJSONObject: params)
            let registerCapturedMedia = registerCapturedMedia
            let summary: ProjectSummary = try await Task.detached(priority: .utility) {
                try registerCapturedMedia("registerRecording", paramsData)
            }.value
            upsertProjectSummary(summary)
            return .indexed(summary)
        } catch let registrationError {
            return await persistCapturedProjectLocally(
                title: title,
                recordingURL: outputURL,
                screenshotURL: nil,
                sourceName: sourceName,
                editorState: editorState,
                recordingSession: recordingSession,
                registrationError: registrationError
            )
        }
    }

    private func persistCapturedProjectLocally(
        title: String,
        recordingURL: URL?,
        screenshotURL: URL?,
        sourceName: String?,
        editorState: ProjectEditorState,
        recordingSession: RecordingSession?,
        registrationError: Error
    ) async -> CapturedProjectRegistrationOutcome {
        let now = ISO8601DateFormatter().string(from: Date())
        let projectsDirectory: URL
        if let paths {
            projectsDirectory = URL(fileURLWithPath: paths.projectsDir, isDirectory: true)
        } else if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            projectsDirectory = applicationSupport
                .appendingPathComponent("Open Recorder", isDirectory: true)
                .appendingPathComponent("Projects", isDirectory: true)
        } else if let mediaURL = screenshotURL ?? recordingURL {
            projectsDirectory = mediaURL.deletingLastPathComponent()
        } else {
            return .failed(registrationError.localizedDescription)
        }
        let newProjectURL = projectsDirectory
            .appendingPathComponent("recovered-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("openrecorder")
        let newRecoveryMarkerURL = newProjectURL.appendingPathExtension("recovery")
        let document = ProjectDocument(
            schemaVersion: 2,
            title: title,
            recordingPath: recordingURL?.path,
            screenshotPath: screenshotURL?.path,
            sourceName: sourceName,
            createdAt: now,
            updatedAt: now,
            editorState: editorState,
            recordingSession: recordingSession
        )

        let documentData: Data
        do {
            documentData = try JSONEncoder().encode(document)
        } catch {
            return .failed("\(registrationError.localizedDescription); local recovery failed: \(error.localizedDescription)")
        }

        let mediaURL = screenshotURL ?? recordingURL
        let targetMediaIdentity = mediaURL.map { canonicalMediaIdentity(for: $0) }
        let persistence = await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: projectsDirectory,
                    withIntermediateDirectories: true
                )
                if let targetMediaIdentity,
                   let candidates = try? FileManager.default.contentsOfDirectory(
                       at: projectsDirectory,
                       includingPropertiesForKeys: nil,
                       options: [.skipsHiddenFiles]
                   ) {
                    for candidateURL in candidates {
                        guard candidateURL.pathExtension == "recovery" else { continue }
                        let candidateProjectURL = candidateURL.deletingPathExtension()
                        guard candidateProjectURL.pathExtension == "openrecorder",
                              let candidateData = try? Data(contentsOf: candidateProjectURL),
                              let candidateDocument = try? JSONDecoder().decode(
                                  ProjectDocument.self,
                                  from: candidateData
                              ),
                              let candidateMediaPath = candidateDocument.screenshotPath
                                  ?? candidateDocument.recordingPath,
                              canonicalMediaIdentity(for: URL(fileURLWithPath: candidateMediaPath))
                                  == targetMediaIdentity else {
                            continue
                        }
                        return LocalProjectPersistenceOutcome.success(
                            projectURL: candidateProjectURL.resolvingSymlinksInPath().standardizedFileURL,
                            projectData: candidateData
                        )
                    }
                }

                try Data().write(to: newRecoveryMarkerURL, options: .atomic)
                do {
                    try documentData.write(to: newProjectURL, options: .atomic)
                } catch {
                    try? FileManager.default.removeItem(at: newRecoveryMarkerURL)
                    throw error
                }
                return LocalProjectPersistenceOutcome.success(
                    projectURL: newProjectURL.resolvingSymlinksInPath().standardizedFileURL,
                    projectData: documentData
                )
            } catch {
                return LocalProjectPersistenceOutcome.failure(error.localizedDescription)
            }
        }.value

        switch persistence {
        case .success(let projectURL, let persistedData):
            guard let persistedDocument = try? JSONDecoder().decode(
                ProjectDocument.self,
                from: persistedData
            ) else {
                return .failed("\(registrationError.localizedDescription); local recovery project is invalid")
            }
            let summary = ProjectSummary(
                id: "project-local-\(projectURL.deletingPathExtension().lastPathComponent)",
                title: persistedDocument.title,
                path: projectURL.path,
                recordingPath: persistedDocument.recordingPath,
                screenshotPath: persistedDocument.screenshotPath,
                sourceName: persistedDocument.sourceName,
                createdAt: persistedDocument.createdAt,
                updatedAt: persistedDocument.updatedAt,
                lastOpenedAt: persistedDocument.updatedAt,
                missing: false,
                availability: .available
            )
            locallyPersistedProjectPaths.insert(summary.path)
            upsertProjectSummary(summary)
            return .locallyPersisted(summary)
        case .failure(let message):
            return .failed("\(registrationError.localizedDescription); local recovery failed: \(message)")
        }
    }

    @discardableResult
    func openProject(_ project: ProjectSummary) -> Task<Void, Never> {
        guard !rejectActionWhileTerminationIsPending() else { return Task {} }
        return openProjectFile(at: URL(fileURLWithPath: project.path))
    }

    func deleteProject(_ project: ProjectSummary) {
        let projectURL = URL(fileURLWithPath: project.path)
        do {
            if FileManager.default.fileExists(atPath: project.path) {
                try trashProjectFile(projectURL)
            }
            try forgetProject(project.path)
            locallyPersistedProjectPaths.remove(project.path)
            noteLocalProjectMutation(path: project.path)
            sendAppShell(.projectSummaryRemoved(path: project.path))
            statusMessage = "Deleted \(project.title)"
        } catch {
            statusMessage = "Could not delete \(project.title): \(error.localizedDescription)"
        }
    }

    func openProjectFile() {
        guard !rejectActionWhileTerminationIsPending() else { return }
        let panel = NSOpenPanel()
        if let projectType = UTType(filenameExtension: "openrecorder") {
            panel.allowedContentTypes = [projectType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let projectURL = panel.url else {
            return
        }

        openProjectFile(at: projectURL)
    }

    @discardableResult
    func openEditorFile(at url: URL) -> Task<Void, Never>? {
        guard !rejectActionWhileTerminationIsPending() else { return nil }
        if url.pathExtension.lowercased() == "openrecorder" {
            return openProjectFile(at: url)
        }

        let kind: EditorMediaKind
        if EditorMediaKind.screenshot.supports(url) {
            kind = .screenshot
        } else if EditorMediaKind.video.supports(url) {
            kind = .video
        } else {
            statusMessage = "Unsupported file: \(url.lastPathComponent)"
            return nil
        }

        let resolvedMediaURL = url.resolvingSymlinksInPath().standardizedFileURL
        let standardizedMediaPath = resolvedMediaURL.path
        let mediaIdentity = canonicalMediaIdentity(for: resolvedMediaURL)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedMediaPath, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: standardizedMediaPath) else {
            statusMessage = "Could not import \(url.lastPathComponent): the file is missing or unreadable."
            return nil
        }

        if let pendingImport = mediaImportTasksByPath[mediaIdentity] {
            return pendingImport
        }

        if let existingProject = projects.first(where: { project in
            guard let mediaPath = project.mediaPath else { return false }
            return canonicalMediaIdentity(for: URL(fileURLWithPath: mediaPath)) == mediaIdentity
                && FileManager.default.fileExists(atPath: project.path)
        }) {
            return openProject(existingProject)
        }

        statusMessage = "Importing \(url.lastPathComponent)…"
        let registerImportedMedia = registerImportedMedia
        let requestID = UUID()
        mediaImportRequestIDsByPath[mediaIdentity] = requestID
        let task = Task { [weak self] in
            defer {
                self?.finishMediaImport(path: mediaIdentity, requestID: requestID)
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    let summary = try registerImportedMedia(kind, standardizedMediaPath)
                    let projectData = try? Data(contentsOf: URL(fileURLWithPath: summary.path))
                    return ImportedMediaRegistrationOutcome.success(summary, projectData: projectData)
                } catch {
                    return ImportedMediaRegistrationOutcome.failure(error.localizedDescription)
                }
            }.value

            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case .success(let summary, let projectData):
                self.upsertProjectSummary(summary)
                switch kind {
                case .screenshot:
                    self.currentScreenshotURL = url
                    self.currentVideoURL = nil
                case .video:
                    self.currentVideoURL = url
                    self.currentScreenshotURL = nil
                }
                let document = projectData.flatMap { try? JSONDecoder().decode(ProjectDocument.self, from: $0) }
                self.showEditor(for: self.importedEditorSession(
                    kind: kind,
                    url: url,
                    summary: summary,
                    document: document
                ))
                self.statusMessage = "Opened \(url.lastPathComponent)"
            case .failure(let message):
                let editorState: ProjectEditorState = kind == .screenshot
                    ? ProjectEditorState(screenshot: .default)
                    : .empty
                let fallback = await self.persistCapturedProjectLocally(
                    title: url.deletingPathExtension().lastPathComponent,
                    recordingURL: kind == .video ? url : nil,
                    screenshotURL: kind == .screenshot ? url : nil,
                    sourceName: kind == .video ? "Imported Recording" : "Imported Screenshot",
                    editorState: editorState,
                    recordingSession: nil,
                    registrationError: ProjectRegistrationFailure(message: message)
                )
                guard let summary = fallback.summary else {
                    if case .failed(let fallbackMessage) = fallback {
                        self.statusMessage = "Could not import \(url.lastPathComponent): \(fallbackMessage)"
                    }
                    return
                }
                let persistedData = await Task.detached(priority: .utility) {
                    try? Data(contentsOf: URL(fileURLWithPath: summary.path))
                }.value
                let document = persistedData
                    .flatMap { try? JSONDecoder().decode(ProjectDocument.self, from: $0) }
                    ?? ProjectDocument(
                    schemaVersion: 2,
                    title: summary.title,
                    recordingPath: summary.recordingPath,
                    screenshotPath: summary.screenshotPath,
                    sourceName: summary.sourceName,
                    createdAt: summary.createdAt,
                    updatedAt: summary.updatedAt,
                    editorState: editorState,
                    recordingSession: nil
                    )
                switch kind {
                case .screenshot:
                    self.currentScreenshotURL = url
                    self.currentVideoURL = nil
                case .video:
                    self.currentVideoURL = url
                    self.currentScreenshotURL = nil
                }
                self.showEditor(for: self.importedEditorSession(
                    kind: kind,
                    url: url,
                    summary: summary,
                    document: document
                ))
                self.statusMessage = "Opened \(url.lastPathComponent)"
            }
        }
        mediaImportTasksByPath[mediaIdentity] = task
        return task
    }

    private func finishMediaImport(path: String, requestID: UUID) {
        guard mediaImportRequestIDsByPath[path] == requestID else { return }
        mediaImportRequestIDsByPath.removeValue(forKey: path)
        mediaImportTasksByPath.removeValue(forKey: path)
    }

    private func importedEditorSession(
        kind: EditorMediaKind,
        url: URL,
        summary: ProjectSummary,
        document: ProjectDocument?
    ) -> EditorSession {
        switch kind {
        case .video:
            return EditorSession(
                kind: .video,
                url: url,
                title: document?.title ?? summary.title,
                projectPath: summary.path,
                recordingSession: document.map { recordingSession(for: $0, recordingURL: url) },
                timelineEditSnapshot: document?.editorState?.timelineEdits ?? .empty,
                videoEditorState: document?.editorState?.video
            )
        case .screenshot:
            return EditorSession(
                kind: .screenshot,
                url: url,
                title: document?.title ?? summary.title,
                projectPath: summary.path,
                screenshotEditorState: document?.editorState?.screenshot ?? .default
            )
        }
    }

    @discardableResult
    func openProjectFile(at projectURL: URL) -> Task<Void, Never> {
        statusMessage = "Opening \(projectURL.lastPathComponent)…"
        return Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return ProjectFileLoadOutcome.success(try Data(contentsOf: projectURL))
                } catch {
                    return ProjectFileLoadOutcome.failure(error.localizedDescription)
                }
            }.value

            guard !Task.isCancelled, let self else { return }
            let document: ProjectDocument
            switch outcome {
            case .success(let data):
                do {
                    document = try JSONDecoder().decode(ProjectDocument.self, from: data)
                } catch {
                    self.statusMessage = "Could not open \(projectURL.lastPathComponent): \(error.localizedDescription)"
                    return
                }
            case .failure(let message):
                self.statusMessage = "Could not open \(projectURL.lastPathComponent): \(message)"
                return
            }

            if let screenshotPath = document.screenshotPath {
                let screenshotURL = URL(fileURLWithPath: screenshotPath)
                guard FileManager.default.isReadableFile(atPath: screenshotURL.path) else {
                    self.statusMessage = "Could not open \(document.title): the screenshot file is missing or unreadable."
                    return
                }
                self.currentScreenshotURL = screenshotURL
                self.currentVideoURL = nil
                self.showEditor(for: EditorSession(
                    kind: .screenshot,
                    url: screenshotURL,
                    title: document.title,
                    projectPath: projectURL.path,
                    screenshotEditorState: document.editorState?.screenshot
                ))
                self.statusMessage = "Opened \(document.title)"
            } else if let recordingPath = document.recordingPath {
                let recordingURL = URL(fileURLWithPath: recordingPath)
                guard FileManager.default.isReadableFile(atPath: recordingURL.path) else {
                    self.statusMessage = "Could not open \(document.title): the recording file is missing or unreadable."
                    return
                }
                self.currentVideoURL = recordingURL
                self.currentScreenshotURL = nil
                self.showEditor(for: EditorSession(
                    kind: .video,
                    url: recordingURL,
                    title: document.title,
                    projectPath: projectURL.path,
                    recordingSession: self.recordingSession(for: document, recordingURL: recordingURL),
                    timelineEditSnapshot: document.editorState?.timelineEdits,
                    videoEditorState: document.editorState?.video
                ))
                self.statusMessage = "Opened \(document.title)"
            } else {
                self.statusMessage = "Project has no recording or screenshot path."
            }
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openPath(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func copyScreenshotToClipboard(_ screenshotURL: URL? = nil) {
        guard let url = screenshotURL ?? currentScreenshotURL,
              let image = NSImage(contentsOf: url) else {
            statusMessage = "No screenshot to copy."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        statusMessage = "Screenshot copied"
    }

    func autosaveProject(_ snapshot: ProjectAutosaveSnapshot) async throws -> ProjectSummary {
        let paramsData = try JSONEncoder().encode(ProjectUpdateRequest(snapshot: snapshot))
        let service = service
        return try await Task.detached(priority: .utility) {
            try service.call("updateProject", paramsData: paramsData, as: ProjectSummary.self)
        }.value
    }

    func handleProjectAutosaveStatus(_ status: ProjectAutosaveStatus) {
        if case .saved(let summary) = status {
            upsertProjectSummary(summary)
        }
    }

    func exportCurrentRecording(_ recordingURL: URL? = nil, options: VideoExportOptions = .default, edits: TimelineEditSnapshot = .empty) {
        videoExport.export(sourceURL: recordingURL ?? currentVideoURL, options: options, edits: edits)
    }

    func cancelVideoExport() {
        videoExport.cancelExport()
    }

    func retryPendingVideoExportSave() {
        videoExport.retrySave()
    }

    func revealExportedVideoInFinder() {
        videoExport.revealExportedFile()
    }

    func clearVideoExportDialogState() {
        videoExport.clear()
    }

    private func initialTimelineEdits(videoURL: URL, cursorTelemetryURL: URL?) async -> TimelineEditSnapshot {
        guard createZoomsAutomatically, let cursorTelemetryURL else {
            return .empty
        }

        let duration = await videoDuration(for: videoURL)
        let zooms = AutoZoomGenerator.generate(from: cursorTelemetryURL, duration: duration, preset: autoZoomAnimationPreset)
        return TimelineEditSnapshot(zoomRegions: zooms)
    }

    private func videoDuration(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let seconds = duration?.seconds ?? 0
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private func recordingSession(for document: ProjectDocument, recordingURL: URL) -> RecordingSession {
        if let recordingSession = document.recordingSession {
            return recordingSession
        }

        let facecamURL = facecamOutputURL(for: recordingURL)
        let existingFacecamURL = FileManager.default.fileExists(atPath: facecamURL.path) ? facecamURL : nil
        let telemetryURL = CursorTelemetryRecorder.telemetryURL(for: recordingURL)
        let existingTelemetryURL = FileManager.default.fileExists(atPath: telemetryURL.path) ? telemetryURL : nil
        let videoState = document.editorState?.video

        return RecordingSession(
            screenVideoPath: recordingURL.path,
            facecamVideoPath: existingFacecamURL?.path,
            facecamOffsetMs: nil,
            facecamSettings: videoState?.facecamSettings ?? defaultFacecamSettings(enabled: existingFacecamURL != nil),
            sourceName: document.sourceName,
            showCursorOverlay: videoState?.cursorOverlay.isVisible ?? true,
            cursorTelemetryPath: existingTelemetryURL?.path
        )
    }

    private func upsertProjectSummary(_ summary: ProjectSummary) {
        if !summary.id.hasPrefix("project-local-") {
            locallyPersistedProjectPaths.remove(summary.path)
        }
        noteLocalProjectMutation(path: summary.path)
        sendAppShell(.projectSummaryUpserted(summary))
    }

    private func noteLocalProjectMutation(path: String) {
        projectMutationVersion += 1
        projectMutationVersionsByPath[path] = projectMutationVersion
    }

    private func noteLocalProjectReplacement(
        from previousProjects: [ProjectSummary],
        to nextProjects: [ProjectSummary]
    ) {
        let previousByPath = Dictionary(previousProjects.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        let nextByPath = Dictionary(nextProjects.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        let changedPaths = Set(previousByPath.keys).union(nextByPath.keys).filter {
            previousByPath[$0] != nextByPath[$0]
        }
        guard !changedPaths.isEmpty else { return }
        projectMutationVersion += 1
        for path in changedPaths {
            projectMutationVersionsByPath[path] = projectMutationVersion
        }
    }

    private func projectsMergingConcurrentMutations(
        into refreshedProjects: [ProjectSummary],
        since version: Int
    ) -> [ProjectSummary] {
        let changedPaths = Set(projectMutationVersionsByPath.compactMap { path, mutationVersion in
            mutationVersion > version ? path : nil
        }).union(locallyPersistedProjectPaths)
        guard !changedPaths.isEmpty else { return refreshedProjects }

        let locallyChangedProjects = projects.filter { changedPaths.contains($0.path) }
        let unchangedRefreshedProjects = refreshedProjects.filter { !changedPaths.contains($0.path) }
        return locallyChangedProjects + unchangedRefreshedProjects
    }

    private func jsonObject<T: Encodable>(for value: T) -> Any? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    var isVideoExporting: Bool {
        videoExport.state.isExporting
    }

    var videoExportPhase: VideoExportPhase {
        videoExport.state.phase
    }

    var videoExportProgress: Double {
        videoExport.state.progress
    }

    var videoExportError: String? {
        videoExport.state.errorMessage
    }

    var exportedVideoURL: URL? {
        videoExport.state.exportedURL
    }

    private func temporaryVideoExportURL(options: VideoExportOptions) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("open-recorder-export-\(UUID().uuidString)")
            .appendingPathExtension(options.format.fileExtension)
    }

    private func videoExportSaveDestination(sourceURL: URL, options: VideoExportOptions) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.contentType]
        panel.nameFieldStringValue = suggestedVideoExportFileName(for: sourceURL, options: options)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func suggestedVideoExportFileName(for sourceURL: URL, options: VideoExportOptions) -> String {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let cropSuffix = options.cropSelection == nil ? "" : "-crop"
        return "\(baseName)-\(options.fileNameSuffix)\(cropSuffix).\(options.format.fileExtension)"
    }

    func openPrivacySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        openPrivacyPane("Privacy_Microphone")
    }

    func openCameraSettings() {
        openPrivacyPane("Privacy_Camera")
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    @discardableResult
    func refreshCaptureDevices() -> Task<Void, Never> {
        captureDeviceRefreshGeneration += 1
        let generation = captureDeviceRefreshGeneration
        captureDeviceRefreshTask?.cancel()
        captureOptions.send(.deviceRefreshStarted)
        let provider = captureDeviceProvider
        let task = Task { [weak self] in
            let devices = await Task.detached(priority: .userInitiated) {
                let microphones = provider.devices(for: .audio)
                let cameras = provider.devices(for: .video)
                return (microphones, cameras)
            }.value
            guard !Task.isCancelled,
                  let self,
                  generation == self.captureDeviceRefreshGeneration else {
                return
            }
            self.captureOptions.send(.devicesRefreshed(
                microphones: devices.0,
                cameras: devices.1
            ))
            self.captureDeviceRefreshTask = nil
        }
        captureDeviceRefreshTask = task
        return task
    }

    private func refreshCaptureDevicesForPreflight() async {
        var refreshTask = refreshCaptureDevices()
        await refreshTask.value
        while !Task.isCancelled,
              captureOptions.state.deviceLoadPhase == .loading,
              let latestRefreshTask = captureDeviceRefreshTask {
            refreshTask = latestRefreshTask
            await refreshTask.value
        }
    }

    func requestMicrophoneSelection(refreshDevices: Bool = true) {
        if refreshDevices {
            refreshCaptureDevices()
        }
        captureOptions.send(.microphoneSelectionRequested)
    }

    func requestCameraSelection(refreshDevices: Bool = true) {
        if refreshDevices {
            refreshCaptureDevices()
        }
        captureOptions.send(.cameraSelectionRequested)
    }

    func cancelMicrophoneSelection() {
        requestWindow(.closeMicrophoneSelector)
    }

    func cancelCameraSelection() {
        requestWindow(.closeCameraSelector)
    }

    func selectMicrophoneDevice(_ deviceID: String?) {
        captureOptions.send(.microphoneSelected(deviceID))
    }

    func selectCameraDevice(_ deviceID: String?) {
        captureOptions.send(.cameraSelected(deviceID))
        prewarmSelectedFacecamIfNeeded()
    }

    func selectNoMicrophoneInput() {
        disableMicrophone()
        requestWindow(.closeMicrophoneSelector)
    }

    func selectNoCameraInput() {
        disableCamera()
        requestWindow(.closeCameraSelector)
    }

    func disableMicrophone() {
        captureOptions.send(.microphoneDisabled)
    }

    func toggleSystemAudio() {
        captureOptions.send(.availabilityChanged(canChangeRecordingOptions))
        captureOptions.send(.systemAudioToggled)
    }

    func disableCamera() {
        captureOptions.send(.cameraDisabled)
        cancelFacecamPrewarm()
    }

    var selectedMicrophoneDeviceName: String {
        captureOptions.state.selectedMicrophoneDeviceName
    }

    var selectedCameraDeviceName: String {
        captureOptions.state.selectedCameraDeviceName
    }

    private var currentCaptureOptions: RecordingCaptureOptions {
        captureOptions.state.recordingOptions
    }

    private func captureMediaAuthorizationState(for mediaType: AVMediaType) -> CaptureMediaAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            .authorized
        case .notDetermined:
            .undetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    private var sourcesForReadiness: [CaptureSource] {
        if capture.sourceCatalogState == .idle, let selectedSource {
            return [selectedSource]
        }
        return capture.sources
    }

    @discardableResult
    private func ensureScreenRecordingPermissionForCapture() -> Bool {
        if capture.screenRecordingPermissionState == .granted {
            return true
        }

        if capture.screenRecordingPermissionState == .requestAvailable {
            _ = requestScreenRecordingPermission()
            refreshOnboardingPermissionStates()
        }

        let state = capture.screenRecordingPermissionState
        guard state == .granted else {
            reportCaptureBlocker(
                state == .requestAvailable
                    ? .screenRecordingPermissionRequired
                    : .screenRecordingPermissionNeedsRestart
            )
            return false
        }
        return true
    }

    private func reportCaptureBlocker(_ blocker: CaptureBlocker) {
        statusMessage = blocker.message
        if blocker.recoveryAction == .waitForCurrentCapture {
            focusActiveCaptureWindow()
        } else {
            showHUD()
        }
    }

    private func finishCapturePreflight(generation: Int) {
        guard generation == capturePreflightGeneration else { return }
        capturePreflightTask = nil
        pendingRecordingOptions = nil
        isCapturePreflightRunning = false
        captureOptions.send(.availabilityChanged(canChangeRecordingOptions))
    }

    private func preparePermissions(for options: RecordingCaptureOptions) async -> Bool {
        if options.includeMicrophone {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if !granted {
                    statusMessage = "Microphone permission is required for narration."
                    return false
                }
            } else if status == .denied || status == .restricted {
                statusMessage = "Microphone permission is denied."
                openMicrophoneSettings()
                return false
            }
        }

        if options.includeCamera {
            guard await prepareCameraPermissionForFacecam() else { return false }
        }

        return true
    }

    private func prepareCameraPermissionForFacecam() async -> Bool {
        if let prepareCameraPermission {
            return await prepareCameraPermission()
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                statusMessage = "Camera permission is required for facecam."
                return false
            }
        } else if status == .denied || status == .restricted {
            statusMessage = "Camera permission is denied."
            openCameraSettings()
            return false
        }
        return true
    }

    private func prewarmSelectedFacecamIfNeeded() {
        let options = currentCaptureOptions
        guard options.includeCamera else {
            cancelFacecamPrewarm()
            return
        }

        facecamPrewarmTask?.cancel()
        facecamPrewarmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.prepareCameraPermissionForFacecam() else { return }
            do {
                try await self.facecamRecorder.prepare(cameraDeviceID: options.cameraDeviceID)
                if !Task.isCancelled {
                    self.facecamPrewarmTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = "Camera warmup failed: \(error.localizedDescription)"
            }
        }
    }

    private func prepareFacecam(cameraDeviceID: String?) async throws {
        facecamPrewarmTask?.cancel()
        facecamPrewarmTask = nil
        if let prepareFacecamRecording {
            try await prepareFacecamRecording(cameraDeviceID)
        } else {
            try await facecamRecorder.prepare(cameraDeviceID: cameraDeviceID)
        }
    }

    private func startFacecam(outputURL: URL, cameraDeviceID: String?) async throws -> Date {
        if let startFacecamRecording {
            return try await startFacecamRecording(outputURL, cameraDeviceID)
        }
        return try await facecamRecorder.start(outputURL: outputURL, cameraDeviceID: cameraDeviceID)
    }

    private func stopFacecam() async throws -> URL? {
        if let stopFacecamRecording {
            return try await stopFacecamRecording()
        }
        return try await facecamRecorder.stop()
    }

    private func cancelFacecam() {
        if let cancelFacecamRecording {
            cancelFacecamRecording()
        } else {
            facecamRecorder.cancel()
        }
    }

    private func cancelFacecamPrewarm() {
        facecamPrewarmTask?.cancel()
        facecamPrewarmTask = nil
        cancelFacecam()
    }

    private func facecamOutputURL(for screenURL: URL) -> URL {
        screenURL
            .deletingPathExtension()
            .appendingPathExtension("facecam.mov")
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func flashDisplay(for source: CaptureSource) {
        guard let displayID = source.displayID,
              let screen = NSScreen.screen(displayID: displayID) else {
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: DisplayFlashOverlay())
        displayFlashWindows.append(window)
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self, window] in
            window.close()
            self?.displayFlashWindows.removeAll { $0 === window }
        }
    }
}

private struct DisplayFlashOverlay: View {
    var body: some View {
        let flashColor = Theme.accent
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(flashColor, lineWidth: 6)
            .padding(10)
            .background(flashColor.opacity(0.10))
            .ignoresSafeArea()
    }
}
