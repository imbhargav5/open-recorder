import AVFoundation
import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .capture
    @Published private(set) var captureState: CaptureState = .choosingMode
    @Published var paths: AppPaths?
    @Published var projects: [ProjectSummary] = []
    @Published var currentVideoURL: URL?
    @Published var currentScreenshotURL: URL?
    @Published var lastEditorSession: EditorSession?
    @Published var statusMessage = "Ready"
    @Published var serviceHealth: HealthPayload?
    @Published var includeMicrophone = false
    @Published var includeSystemAudio = false
    @Published var includeCamera = false
    @Published var showCursor = true
    @Published var showClicks = false
    @Published var createZoomsAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(createZoomsAutomatically, forKey: Self.createZoomsAutomaticallyDefaultsKey)
        }
    }
    @Published var microphoneDevices: [CaptureDeviceInfo] = []
    @Published var cameraDevices: [CaptureDeviceInfo] = []
    @Published var selectedMicrophoneDeviceID: String?
    @Published var selectedCameraDeviceID: String?
    @Published var windowCommand: NativeWindowCommand?
    @Published var isVideoExporting = false
    @Published var videoExportPhase: VideoExportPhase = .idle
    @Published var videoExportProgress = 0.0
    @Published var videoExportError: String?
    @Published var exportedVideoURL: URL?
    @Published var screenRecordingPermissionState: ScreenRecordingPermissionState
    @Published var accessibilityPermissionState: AccessibilityPermissionState
    @Published var onboardingStatusMessage = ""

    private var pendingVideoExportTempURL: URL?
    private var pendingVideoExportSourceURL: URL?
    private var pendingVideoExportOptions: VideoExportOptions?
    private var videoExportTask: Task<Void, Never>?
    private var videoExportCancellationToken: VideoExportCancellationToken?

    private var handledWindowCommandID: UUID?
    private var activeScreenStartedAt: Date?
    private var activeFacecamStartedAt: Date?
    private var activeFacecamURL: URL?
    private var displayFlashWindows: [NSWindow] = []
    private var recordingStartTask: Task<Void, Never>?
    private var screenshotCaptureTask: Task<Void, Never>?
    private let countdownOverlayController = RecordingCountdownOverlayController()
    private let captureUIHideDelayNanoseconds: UInt64

    let service: RustServiceClient
    let capture: CaptureController
    private let screenRecordingPermission: ScreenRecordingPermission
    private let accessibilityPermission: AccessibilityPermission
    private let onboardingStore: OnboardingStateStore
    private let screenSelectionPresenter: ScreenSelectionPresenting
    private let screenshotCapture: @MainActor (CaptureSource, URL) throws -> Void
    private let stopRecordingCapture: @MainActor () async throws -> URL
    private let rememberScreenshot: @Sendable (URL) throws -> Void
    private let facecamRecorder = FacecamRecorder()
    private let cursorTelemetryRecorder = CursorTelemetryRecorder()
    private let captureDeviceProvider = CaptureDeviceProvider()
    private static let createZoomsAutomaticallyDefaultsKey = "recording.createZoomsAutomatically"

    init(
        screenRecordingPermission: ScreenRecordingPermission = ScreenRecordingPermission(),
        accessibilityPermission: AccessibilityPermission = AccessibilityPermission(),
        onboardingStore: OnboardingStateStore = .live,
        screenSelectionPresenter: ScreenSelectionPresenting = ScreenSelectionOverlayController(),
        captureUIHideDelayNanoseconds: UInt64 = 180_000_000,
        screenshotCapture: (@MainActor (CaptureSource, URL) throws -> Void)? = nil,
        stopRecording: (@MainActor () async throws -> URL)? = nil,
        rememberScreenshot: (@Sendable (URL) throws -> Void)? = nil
    ) {
        let service = RustServiceClient()
        let capture = CaptureController(screenRecordingPermission: screenRecordingPermission)
        self.createZoomsAutomatically = UserDefaults.standard.object(forKey: Self.createZoomsAutomaticallyDefaultsKey) as? Bool ?? true
        self.service = service
        self.screenRecordingPermission = screenRecordingPermission
        self.accessibilityPermission = accessibilityPermission
        self.onboardingStore = onboardingStore
        self.screenSelectionPresenter = screenSelectionPresenter
        self.captureUIHideDelayNanoseconds = captureUIHideDelayNanoseconds
        self.capture = capture
        self.screenshotCapture = screenshotCapture ?? { source, outputURL in
            try capture.takeScreenshot(source: source, outputURL: outputURL)
        }
        self.stopRecordingCapture = stopRecording ?? {
            try await capture.stopRecording()
        }
        self.rememberScreenshot = rememberScreenshot ?? { outputURL in
            let _: PreparedFile = try service.call(
                "rememberScreenshot",
                params: ["path": outputURL.path],
                as: PreparedFile.self
            )
        }
        self.screenRecordingPermissionState = screenRecordingPermission.currentState()
        self.accessibilityPermissionState = accessibilityPermission.currentState()
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
        captureState = state
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
        captureState.canChangeRecordingOptions(runtimeIsRecording: capture.isRecording)
    }

    func bootstrap() {
        presentOnboardingIfNeeded()
        Task {
            await refreshSources()
            refreshCaptureDevices()
        }
        refreshBackendState()
    }

    var canContinueOnboarding: Bool {
        screenRecordingPermissionState == .granted
    }

    func refreshOnboardingPermissionStates() {
        let nextScreenRecordingPermissionState = screenRecordingPermission.currentState()
        let nextAccessibilityPermissionState = accessibilityPermission.currentState()

        if screenRecordingPermissionState != nextScreenRecordingPermissionState {
            screenRecordingPermissionState = nextScreenRecordingPermissionState
        }

        if accessibilityPermissionState != nextAccessibilityPermissionState {
            accessibilityPermissionState = nextAccessibilityPermissionState
        }

        if canContinueOnboarding && onboardingStatusMessage.localizedCaseInsensitiveContains("required") {
            onboardingStatusMessage = ""
        }
    }

    func presentOnboardingIfNeeded() {
        guard !onboardingStore.isCompleted() else {
            return
        }
        showOnboarding()
    }

    func showOnboarding() {
        refreshOnboardingPermissionStates()
        captureState = captureState.withPresentation(.hidden)
        requestWindow(.showOnboarding)
    }

    func requestOnboardingScreenRecordingPermission() {
        switch screenRecordingPermission.currentState() {
        case .granted:
            onboardingStatusMessage = "Screen Recording is enabled."
        case .requestAvailable:
            let outcome = screenRecordingPermission.requestGrant()
            switch outcome {
            case .granted:
                onboardingStatusMessage = "Screen Recording is enabled."
            case .promptShownWithoutGrant, .promptAlreadyShown:
                onboardingStatusMessage = "Enable Screen Recording in System Settings, then quit and reopen Open Recorder if macOS asks."
            }
        case .requestAlreadyShown:
            onboardingStatusMessage = "Enable Screen Recording in System Settings, then quit and reopen Open Recorder if macOS asks."
            openPrivacySettings()
        }
        refreshOnboardingPermissionStates()
    }

    func requestOnboardingAccessibilityPermission() {
        switch accessibilityPermission.currentState() {
        case .granted:
            onboardingStatusMessage = "Accessibility access is enabled."
        case .requestAvailable:
            let outcome = accessibilityPermission.requestGrant()
            switch outcome {
            case .granted:
                onboardingStatusMessage = "Accessibility access is enabled."
            case .promptShownWithoutGrant, .promptAlreadyShown:
                onboardingStatusMessage = "Enable Accessibility access in System Settings to capture shortcuts and cursor details."
            }
        case .requestAlreadyShown:
            onboardingStatusMessage = "Enable Accessibility access in System Settings to capture shortcuts and cursor details."
            openAccessibilitySettings()
        }
        refreshOnboardingPermissionStates()
    }

    @discardableResult
    func completeOnboarding() -> Bool {
        refreshOnboardingPermissionStates()
        guard canContinueOnboarding else {
            onboardingStatusMessage = "Screen Recording permission is required before continuing."
            return false
        }

        onboardingStore.setCompleted(true)
        onboardingStatusMessage = ""
        statusMessage = "Ready"
        captureState = captureState.withPresentation(.visible)
        requestWindow(.finishOnboarding)
        return true
    }

    func refreshBackendState() {
        do {
            serviceHealth = try service.call("health", as: HealthPayload.self)
            paths = try service.call("paths", as: AppPaths.self)
            projects = try service.call("listProjects", as: [ProjectSummary].self)
            statusMessage = "Rust service ready"
        } catch {
            statusMessage = error.localizedDescription
        }
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
        let previousSelection = selectedSource
        await capture.reloadSources(requestScreenRecordingPermission: requestScreenRecordingPermission)

        let resolved = resolveSelection(previous: previousSelection, in: capture.sources)
        dispatch(.refreshSelectedSource(resolved))
    }

    private func resolveSelection(previous: CaptureSource?, in sources: [CaptureSource]) -> CaptureSource? {
        guard let previous else {
            return sources.first
        }
        if previous.kind == .area {
            return previous
        }
        if let match = sources.first(where: { matchesIdentity($0, previous) }) {
            return match
        }
        return sources.first
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
            if let candidateWindowID = candidate.windowID,
               let referenceWindowID = reference.windowID,
               candidateWindowID == referenceWindowID,
               candidate.ownerBundleID == reference.ownerBundleID {
                return true
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

    @discardableResult
    private func dispatch(_ event: CaptureEvent) -> CaptureTransition {
        let transition = captureState.applying(event)
        captureState = transition.state
        if let message = transition.statusMessage {
            statusMessage = message
        }
        interpretCaptureEffects(transition.effects)
        return transition
    }

    private func interpretCaptureEffects(_ effects: [CaptureEffect]) {
        for effect in effects {
            switch effect {
            case .showHUD:
                requestWindow(.showHUD)
            case .hideHUD:
                requestWindow(.hideHUD)
            case .closeCaptureSetup:
                requestWindow(.closeCaptureSetup)
            case .showSourceSelector:
                requestWindow(.showSourceSelector)
            case .showAreaSelector:
                requestWindow(.showAreaSelector)
            case .showRecordingSetup(let kind):
                requestWindow(kind == .display ? .showScreenRecordingSetup : .showRecordingSetup)
            case .dismissScreenSelection:
                screenSelectionPresenter.dismiss()
            case .dismissCaptureWindows:
                requestWindow(.hideRecordingSetup)
            case .focusActiveCaptureWindow:
                focusActiveCaptureWindow()
            case .flashDisplay(let source):
                flashDisplay(for: source)
            case .cancelRecordingStart:
                recordingStartTask?.cancel()
                recordingStartTask = nil
                countdownOverlayController.dismiss()
            case .cancelScreenshotCapture:
                screenshotCaptureTask?.cancel()
                screenshotCaptureTask = nil
            case .prepareRecordingFile(let source):
                prepareRecordingFile(for: source)
            case .runRecordingStart(let source, let outputURL):
                recordingStartTask?.cancel()
                recordingStartTask = Task { [weak self] in
                    await self?.runRecordingStartFlow(source: source, outputURL: outputURL)
                }
            case .stopRecording(let source):
                Task {
                    await runRecordingStopFlow(source: source)
                }
            case .runScreenshotCapture(let source):
                screenshotCaptureTask?.cancel()
                screenshotCaptureTask = Task { [weak self] in
                    await self?.runScreenshotCapture(source: source)
                }
            }
        }
    }

    private func prepareRecordingFile(for source: CaptureSource) {
        do {
            let fileName = timestampedFileName(prefix: "recording", extension: "mp4")
            let prepared: PreparedFile = try service.call(
                "prepareRecordingFile",
                params: ["fileName": fileName],
                as: PreparedFile.self
            )
            dispatch(.recordingFilePrepared(source, URL(fileURLWithPath: prepared.path)))
        } catch {
            dispatch(.recordingFilePreparationFailed(source, message: error.localizedDescription))
        }
    }

    var canStartNewCapture: Bool {
        captureState.canStartNewCapture(runtimeIsRecording: capture.isRecording)
    }

    func beginCapture(_ mode: CaptureMode) {
        dispatch(.beginCapture(mode, runtimeIsRecording: capture.isRecording))
    }

    func selectSource(_ source: CaptureSource) {
        dispatch(.selectSource(source))
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
        dispatch(.chooseSourceType(sourceType))
        if sourceType == .screen {
            presentCurrentScreenSelection()
        }
    }

    func requestSourceSelector(kind: CaptureSourceKind? = nil) {
        dispatch(.requestSourceSelector(kind))
        if case .screenSelecting = captureState.phase {
            presentCurrentScreenSelection()
        }
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
        dispatch(.selectSource(interactiveAreaSource()))
        dispatch(.requestInteractiveAreaSelection)
    }

    func completeInteractiveAreaSelection(_ area: CaptureArea) {
        dispatch(.completeInteractiveAreaSelection(interactiveAreaSource(area: area)))
    }

    func cancelInteractiveAreaSelection() {
        cancelCapture()
    }

    func cancelCapture() {
        dispatch(.cancelCapture)
    }

    func requestWindow(_ action: NativeWindowCommandAction, editorSession: EditorSession? = nil) {
        windowCommand = NativeWindowCommand(action: action, editorSession: editorSession)
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
        lastEditorSession = session
        selectedSection = .editor
        requestWindow(.showStudio, editorSession: session)
    }

    func consumeWindowCommand(_ command: NativeWindowCommand?) -> NativeWindowCommand? {
        guard let command, handledWindowCommandID != command.id else {
            return nil
        }
        handledWindowCommandID = command.id
        return command
    }

    private func focusActiveCaptureWindow() {
        switch captureState.phase {
        case .selectingSource:
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
            captureState = captureState.withPresentation(.hidden)
        case .idle, .choosingMode:
            showHUD()
        }
    }

    func toggleRecordingShortcut() {
        switch captureState.phase {
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
        dispatch(.recordingStartRequested)
    }

    private func runRecordingStartFlow(source selectedSource: CaptureSource, outputURL: URL) async {
        do {
            refreshCaptureDevices()
            let options = currentCaptureOptions
            guard await preparePermissions(for: options) else {
                restoreRecordingSetup(source: selectedSource)
                return
            }

            try await countdownOverlayController.run(for: selectedSource)
            guard !Task.isCancelled else { return }

            dispatch(.recordingStarting(selectedSource))

            cursorTelemetryRecorder.start(for: selectedSource)
            try await capture.startRecording(
                source: selectedSource,
                outputURL: outputURL,
                options: options
            )
            activeScreenStartedAt = Date()
            activeFacecamURL = nil
            activeFacecamStartedAt = nil

            if options.includeCamera {
                do {
                    let facecamURL = facecamOutputURL(for: outputURL)
                    if FileManager.default.fileExists(atPath: facecamURL.path) {
                        try FileManager.default.removeItem(at: facecamURL)
                    }
                    activeFacecamStartedAt = try await facecamRecorder.start(
                        outputURL: facecamURL,
                        cameraDeviceID: options.cameraDeviceID
                    )
                    activeFacecamURL = facecamURL
                } catch {
                    includeCamera = false
                    activeFacecamURL = nil
                    activeFacecamStartedAt = nil
                    statusMessage = "Recording without facecam: \(error.localizedDescription)"
                }
            }

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
            recordingStartTask = nil
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
            facecamRecorder.cancel()
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
        recordingStartTask = nil
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
            let stoppedFacecamURL = try? await facecamRecorder.stop()
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
                let summary: ProjectSummary = try service.call(
                    "registerRecording",
                    params: [
                        "path": outputURL.path,
                        "sourceName": sourceName ?? "Screen Recording",
                        "title": outputURL.deletingPathExtension().lastPathComponent,
                        "editorState": jsonObject(for: ProjectEditorState(timelineEdits: timelineEdits)) ?? [:]
                    ],
                    as: ProjectSummary.self
                )
                projects = try service.call("listProjects", as: [ProjectSummary].self)
                showEditor(for: EditorSession(
                    kind: .video,
                    url: outputURL,
                    title: summary.title,
                    projectPath: summary.path,
                    recordingSession: recordingSession,
                    timelineEditSnapshot: timelineEdits
                ))
                statusMessage = "Saved \(summary.title)"
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
        guard !capture.isRecording else {
            statusMessage = "Finish or cancel the current capture before starting another."
            focusActiveCaptureWindow()
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

            let ensuredPaths = try paths ?? service.call("paths", as: AppPaths.self)
            let outputURL = URL(fileURLWithPath: ensuredPaths.screenshotsDir)
                .appendingPathComponent(timestampedFileName(prefix: "screenshot", extension: "png"))
            try screenshotCapture(selectedSource, outputURL)
            try Task.checkCancellation()
            guard isActiveScreenshotCapture(for: selectedSource) else {
                throw CancellationError()
            }
            let summary = registerScreenshotProject(outputURL, sourceName: selectedSource.name)
            try Task.checkCancellation()
            guard isActiveScreenshotCapture(for: selectedSource) else {
                throw CancellationError()
            }
            currentScreenshotURL = outputURL
            currentVideoURL = nil
            screenshotCaptureTask = nil
            showEditor(for: EditorSession(
                kind: .screenshot,
                url: outputURL,
                title: summary?.title,
                projectPath: summary?.path,
                screenshotEditorState: .default
            ))
            statusMessage = "Captured \(outputURL.lastPathComponent)"
            if summary == nil {
                rememberScreenshotInBackground(outputURL)
            }
        } catch is CancellationError {
            screenshotCaptureTask = nil
            if case .capturingScreenshot(let activeSource) = captureState.phase,
               activeSource.id == selectedSource.id {
                restoreScreenshotSetup(source: selectedSource, message: "Screenshot canceled.")
            }
        } catch {
            screenshotCaptureTask = nil
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

    private func registerScreenshotProject(_ outputURL: URL, sourceName: String?) -> ProjectSummary? {
        let title = outputURL.deletingPathExtension().lastPathComponent
        do {
            let summary: ProjectSummary = try service.call(
                "registerScreenshot",
                params: [
                    "path": outputURL.path,
                    "sourceName": sourceName ?? "Screenshot",
                    "title": title,
                    "editorState": jsonObject(for: ProjectEditorState(screenshot: ScreenshotEditorState.default)) ?? [:]
                ],
                as: ProjectSummary.self
            )
            upsertProjectSummary(summary)
            return summary
        } catch {
            return nil
        }
    }

    func openProject(_ project: ProjectSummary) {
        openProjectFile(at: URL(fileURLWithPath: project.path))
    }

    func openProjectFile() {
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

    func openEditorFile(at url: URL) {
        if url.pathExtension.lowercased() == "openrecorder" {
            openProjectFile(at: url)
            return
        }

        if EditorMediaKind.screenshot.supports(url) {
            currentScreenshotURL = url
            currentVideoURL = nil
            showEditor(for: EditorSession(kind: .screenshot, url: url))
            statusMessage = "Opened \(url.lastPathComponent)"
            return
        }

        if EditorMediaKind.video.supports(url) {
            currentVideoURL = url
            currentScreenshotURL = nil
            showEditor(for: EditorSession(kind: .video, url: url))
            statusMessage = "Opened \(url.lastPathComponent)"
            return
        }

        statusMessage = "Unsupported file: \(url.lastPathComponent)"
    }

    func openProjectFile(at projectURL: URL) {
        do {
            let document: ProjectDocument = try service.call(
                "loadProject",
                params: ["path": projectURL.path],
                as: ProjectDocument.self
            )
            if let screenshotPath = document.screenshotPath {
                let screenshotURL = URL(fileURLWithPath: screenshotPath)
                currentScreenshotURL = screenshotURL
                currentVideoURL = nil
                showEditor(for: EditorSession(
                    kind: .screenshot,
                    url: screenshotURL,
                    title: document.title,
                    projectPath: projectURL.path,
                    screenshotEditorState: document.editorState?.screenshot
                ))
                statusMessage = "Opened \(document.title)"
                refreshBackendState()
            } else if let recordingPath = document.recordingPath {
                let recordingURL = URL(fileURLWithPath: recordingPath)
                currentVideoURL = recordingURL
                currentScreenshotURL = nil
                showEditor(for: EditorSession(
                    kind: .video,
                    url: recordingURL,
                    title: document.title,
                    projectPath: projectURL.path,
                    recordingSession: recordingSession(for: document, recordingURL: recordingURL),
                    timelineEditSnapshot: document.editorState?.timelineEdits,
                    videoEditorState: document.editorState?.video
                ))
                statusMessage = "Opened \(document.title)"
                refreshBackendState()
            } else {
                statusMessage = "Project has no recording path."
            }
        } catch {
            statusMessage = error.localizedDescription
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
        switch status {
        case .saving:
            statusMessage = "Saving..."
        case .saved(let summary):
            upsertProjectSummary(summary)
            statusMessage = "Saved"
        case .failed(let message):
            statusMessage = "Autosave failed: \(message)"
        }
    }

    func exportCurrentRecording(_ recordingURL: URL? = nil, options: VideoExportOptions = .default, edits: TimelineEditSnapshot = .empty) {
        guard let url = recordingURL ?? currentVideoURL else {
            statusMessage = "Open a recording first."
            return
        }

        cancelVideoExportTask()
        resetVideoExportResult(removePendingFile: true)
        pendingVideoExportSourceURL = url
        pendingVideoExportOptions = options

        let targetURL = temporaryVideoExportURL(options: options)
        let cancellationToken = VideoExportCancellationToken()
        pendingVideoExportTempURL = targetURL
        videoExportCancellationToken = cancellationToken
        isVideoExporting = true
        videoExportPhase = .exporting
        videoExportProgress = 0
        statusMessage = "Exporting \(options.resolution.title) \(options.format.title) at \(options.frameRate.title)..."

        videoExportTask = Task {
            await exportRecording(
                from: url,
                to: targetURL,
                options: options,
                cancellationToken: cancellationToken,
                edits: edits
            )
        }
    }

    func cancelVideoExport() {
        guard videoExportPhase == .exporting || isVideoExporting else { return }
        cancelVideoExportTask()
        if let pendingVideoExportTempURL {
            try? FileManager.default.removeItem(at: pendingVideoExportTempURL)
        }
        pendingVideoExportTempURL = nil
        isVideoExporting = false
        videoExportProgress = 0
        videoExportError = "Export canceled."
        videoExportPhase = .failed
        statusMessage = "Export canceled."
    }

    func retryPendingVideoExportSave() {
        guard let tempURL = pendingVideoExportTempURL,
              let sourceURL = pendingVideoExportSourceURL,
              let options = pendingVideoExportOptions else {
            videoExportError = "No completed export is waiting to be saved."
            videoExportPhase = .failed
            return
        }

        saveRenderedVideo(tempURL: tempURL, sourceURL: sourceURL, options: options)
    }

    func revealExportedVideoInFinder() {
        guard let exportedVideoURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([exportedVideoURL])
    }

    func clearVideoExportDialogState() {
        if videoExportPhase.isBusy {
            cancelVideoExport()
        }
        cancelVideoExportTask()
        resetVideoExportResult(removePendingFile: true)
        videoExportPhase = .idle
        videoExportProgress = 0
        isVideoExporting = false
    }

    private func exportRecording(
        from sourceURL: URL,
        to targetURL: URL,
        options: VideoExportOptions,
        cancellationToken: VideoExportCancellationToken,
        edits: TimelineEditSnapshot
    ) async {
        do {
            try await VideoExportRenderer.export(
                sourceURL: sourceURL,
                targetURL: targetURL,
                options: options,
                cancellationToken: cancellationToken,
                edits: edits,
                progressHandler: { [weak self] progress in
                    self?.videoExportProgress = progress
                }
            )
            guard !Task.isCancelled else { return }
            videoExportTask = nil
            videoExportCancellationToken = nil
            isVideoExporting = false
            videoExportProgress = 1
            videoExportPhase = .saving
            statusMessage = "Choose where to save \(options.resolution.title) \(options.format.title) at \(options.frameRate.title)."
            saveRenderedVideo(tempURL: targetURL, sourceURL: sourceURL, options: options)
        } catch {
            guard !Task.isCancelled else { return }
            videoExportTask = nil
            videoExportCancellationToken = nil
            isVideoExporting = false
            videoExportError = error.localizedDescription
            videoExportPhase = .failed
            statusMessage = error.localizedDescription
        }
    }

    private func saveRenderedVideo(tempURL: URL, sourceURL: URL, options: VideoExportOptions) {
        videoExportPhase = .saving
        videoExportError = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.contentType]
        panel.nameFieldStringValue = suggestedVideoExportFileName(for: sourceURL, options: options)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let targetURL = panel.url else {
            videoExportError = "Save dialog canceled. Click Save Again to save without re-exporting."
            videoExportPhase = .savePending
            statusMessage = "Export ready to save."
            return
        }

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: targetURL)
            try? FileManager.default.removeItem(at: tempURL)
            pendingVideoExportTempURL = nil
            pendingVideoExportSourceURL = nil
            pendingVideoExportOptions = nil
            exportedVideoURL = targetURL
            videoExportPhase = .success
            statusMessage = "Exported \(targetURL.lastPathComponent)"
        } catch {
            videoExportError = error.localizedDescription
            videoExportPhase = .failed
            statusMessage = error.localizedDescription
        }
    }

    private func resetVideoExportResult(removePendingFile: Bool) {
        if removePendingFile, let pendingVideoExportTempURL {
            try? FileManager.default.removeItem(at: pendingVideoExportTempURL)
        }
        pendingVideoExportTempURL = nil
        pendingVideoExportSourceURL = nil
        pendingVideoExportOptions = nil
        videoExportError = nil
        exportedVideoURL = nil
    }

    private func initialTimelineEdits(videoURL: URL, cursorTelemetryURL: URL?) async -> TimelineEditSnapshot {
        guard createZoomsAutomatically, let cursorTelemetryURL else {
            return .empty
        }

        let duration = await videoDuration(for: videoURL)
        let zooms = AutoZoomGenerator.generate(from: cursorTelemetryURL, duration: duration)
        return TimelineEditSnapshot(zoomRegions: zooms)
    }

    private func videoDuration(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let seconds = duration?.seconds ?? 0
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private func recordingSession(for document: ProjectDocument, recordingURL: URL) -> RecordingSession {
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
        projects.removeAll { $0.path == summary.path }
        projects.insert(summary, at: 0)
    }

    private func jsonObject<T: Encodable>(for value: T) -> Any? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func cancelVideoExportTask() {
        videoExportTask?.cancel()
        videoExportTask = nil
        videoExportCancellationToken?.cancel()
        videoExportCancellationToken = nil
    }

    private func temporaryVideoExportURL(options: VideoExportOptions) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("open-recorder-export-\(UUID().uuidString)")
            .appendingPathExtension(options.format.fileExtension)
    }

    private func suggestedVideoExportFileName(for sourceURL: URL, options: VideoExportOptions) -> String {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let resolutionSuffix: String
        if options.resolution == .custom, let customOutputSize = options.customOutputSize {
            resolutionSuffix = "\(Int(customOutputSize.width.rounded()))x\(Int(customOutputSize.height.rounded()))"
        } else {
            resolutionSuffix = options.resolution.fileSuffix
        }
        let cropSuffix = options.cropSelection == nil ? "" : "-crop"
        let suffix = "\(resolutionSuffix)\(cropSuffix)-\(options.frameRate.fileSuffix)"
        return "\(baseName)-\(suffix).\(options.format.fileExtension)"
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

    func refreshCaptureDevices() {
        microphoneDevices = captureDeviceProvider.devices(for: .audio)
        cameraDevices = captureDeviceProvider.devices(for: .video)

        if let selectedMicrophoneDeviceID,
           !microphoneDevices.contains(where: { $0.id == selectedMicrophoneDeviceID }) {
            self.selectedMicrophoneDeviceID = nil
        }

        if let selectedCameraDeviceID,
           !cameraDevices.contains(where: { $0.id == selectedCameraDeviceID }) {
            self.selectedCameraDeviceID = nil
        }
    }

    func requestMicrophoneSelection(refreshDevices: Bool = true) {
        if refreshDevices {
            refreshCaptureDevices()
        }
        requestWindow(.showMicrophoneSelector)
    }

    func requestCameraSelection(refreshDevices: Bool = true) {
        if refreshDevices {
            refreshCaptureDevices()
        }
        requestWindow(.showCameraSelector)
    }

    func cancelMicrophoneSelection() {
        requestWindow(.closeMicrophoneSelector)
    }

    func cancelCameraSelection() {
        requestWindow(.closeCameraSelector)
    }

    func selectMicrophoneDevice(_ deviceID: String?) {
        includeMicrophone = true
        selectedMicrophoneDeviceID = deviceID
        statusMessage = "Microphone set to \(selectedMicrophoneDeviceName)"
        requestWindow(.closeMicrophoneSelector)
    }

    func selectCameraDevice(_ deviceID: String?) {
        includeCamera = true
        selectedCameraDeviceID = deviceID
        statusMessage = "Camera set to \(selectedCameraDeviceName)"
        requestWindow(.closeCameraSelector)
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
        includeMicrophone = false
        statusMessage = "Microphone off"
    }

    func toggleSystemAudio() {
        guard canChangeRecordingOptions else {
            statusMessage = includeSystemAudio ? "System audio is on for this recording." : "System audio is off for this recording."
            return
        }

        includeSystemAudio.toggle()
        statusMessage = includeSystemAudio ? "System audio on" : "System audio off"
    }

    func disableCamera() {
        includeCamera = false
        statusMessage = "Camera off"
    }

    var selectedMicrophoneDeviceName: String {
        guard let selectedMicrophoneDeviceID,
              let device = microphoneDevices.first(where: { $0.id == selectedMicrophoneDeviceID }) else {
            return "System Default"
        }
        return device.name
    }

    var selectedCameraDeviceName: String {
        guard let selectedCameraDeviceID,
              let device = cameraDevices.first(where: { $0.id == selectedCameraDeviceID }) else {
            return "System Default"
        }
        return device.name
    }

    private var currentCaptureOptions: RecordingCaptureOptions {
        RecordingCaptureOptions(
            includeMicrophone: includeMicrophone,
            microphoneDeviceID: includeMicrophone ? selectedMicrophoneDeviceID : nil,
            includeSystemAudio: includeSystemAudio,
            includeCamera: includeCamera,
            cameraDeviceID: includeCamera ? selectedCameraDeviceID : nil,
            showCursor: showCursor,
            showClicks: showClicks
        )
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
        }

        return true
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
        let flashColor = Color(red: 0.145, green: 0.388, blue: 0.922)
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(flashColor, lineWidth: 6)
            .padding(10)
            .background(flashColor.opacity(0.10))
            .ignoresSafeArea()
    }
}
