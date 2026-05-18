import AVFoundation
import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .capture
    @Published var captureMode: CaptureMode = .recording
    @Published var hudState: HUDState = .choosingMode
    @Published var selectedSource: CaptureSource?
    @Published var preferredSourceSelectorKind: CaptureSourceKind?
    @Published var paths: AppPaths?
    @Published var projects: [ProjectSummary] = []
    @Published var currentVideoURL: URL?
    @Published var currentScreenshotURL: URL?
    @Published var lastEditorSession: EditorSession?
    @Published var statusMessage = "Ready"
    @Published var serviceHealth: HealthPayload?
    @Published var recordingPhase: RecordingPhase = .idle
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
    @Published var isAreaSelectionActive = false
    @Published var screenshotExportRequestID: UUID?
    @Published var videoExportRequestID: UUID?
    @Published var videoExportRequestURL: URL?
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
    private var stopAfterRecordingStart = false
    private let countdownOverlayController = RecordingCountdownOverlayController()
    private let captureUIHideDelayNanoseconds: UInt64

    let service: RustServiceClient
    let capture: CaptureController
    private let screenRecordingPermission: ScreenRecordingPermission
    private let accessibilityPermission: AccessibilityPermission
    private let onboardingStore: OnboardingStateStore
    private let screenSelectionPresenter: ScreenSelectionPresenting
    private let screenshotCapture: @MainActor (CaptureSource, URL) throws -> Void
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

    var captureFlow: CaptureFlow {
        hudState.captureFlow
    }

    var isHUDVisible: Bool {
        hudState.presentation.isVisible
    }

    var canShowCaptureUI: Bool {
        !hudState.requiresHiddenCaptureUI
    }

    var canChangeRecordingOptions: Bool {
        recordingPhase == .idle && !capture.isRecording
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
        hudState = hudState.withPresentation(.hidden)
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
        hudState = hudState.withPresentation(.visible)
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
        selectedSource = resolved

        guard let resolved, let previousSelection else {
            return
        }
        if case .ready(let mode, let hudSource) = hudState.phase,
           hudSource.id == previousSelection.id || matchesIdentity(hudSource, previousSelection) {
            setHUDPhase(.ready(mode, resolved))
        }
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

    var canStartNewCapture: Bool {
        recordingPhase == .idle &&
            !capture.isRecording &&
            !isAreaSelectionActive &&
            !hudState.isCaptureOccupied
    }

    func beginCapture(_ mode: CaptureMode) {
        guard canStartNewCapture else {
            statusMessage = "Finish or cancel the current capture before starting another."
            focusActiveCaptureWindow()
            return
        }

        captureMode = mode
        preferredSourceSelectorKind = nil
        screenSelectionPresenter.dismiss()
        setHUDPhase(.choosingSourceType(mode))
        statusMessage = "Choose a source type."
        requestWindow(.showHUD)
    }

    func selectSource(_ source: CaptureSource) {
        preferredSourceSelectorKind = source.kind
        selectedSource = source
        setHUDPhase(.ready(hudState.mode ?? captureMode, source))
        statusMessage = "Selected \(source.name)"
        if source.kind == .display {
            flashDisplay(for: source)
        }
    }

    func selectInteractiveAreaSource(area: CaptureArea? = nil) {
        let source = CaptureSource(
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
        preferredSourceSelectorKind = .area
        selectedSource = source
        setHUDPhase(.ready(hudState.mode ?? captureMode, source))
        statusMessage = "Selected area"
    }

    func chooseSourceType(_ sourceType: CaptureSourceType) {
        let mode = hudState.mode ?? captureMode
        captureMode = mode

        switch sourceType {
        case .screen:
            requestScreenSelection()
        case .window:
            requestSourceSelector(kind: .window, mode: mode, statusMessage: "Choose a window.")
        case .area:
            requestSourceSelector(kind: .area, mode: mode, statusMessage: "Choose an area.")
        }
    }

    func requestSourceSelector(kind: CaptureSourceKind? = nil) {
        let resolvedKind = kind ?? selectedSource?.kind ?? preferredSourceSelectorKind ?? .window
        guard resolvedKind != .display else {
            requestScreenSelection()
            return
        }

        preferredSourceSelectorKind = resolvedKind
        requestWindow(.showSourceSelector)
    }

    private func requestSourceSelector(
        kind: CaptureSourceKind,
        mode: CaptureMode,
        statusMessage: String
    ) {
        preferredSourceSelectorKind = kind
        setHUDPhase(.selectingSource(mode))
        self.statusMessage = statusMessage
        requestWindow(.showSourceSelector)
    }

    func requestScreenSelection() {
        let mode = hudState.mode ?? captureMode
        captureMode = mode
        preferredSourceSelectorKind = .display
        setHUDPhase(.screenSelecting(mode))
        statusMessage = "Choose a screen."

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

    func completeScreenSelection(_ source: CaptureSource) {
        guard source.kind == .display else {
            statusMessage = "Choose a screen."
            return
        }

        screenSelectionPresenter.dismiss()
        selectSource(source)
        requestWindow(.showHUD)
    }

    func cancelScreenSelection(message: String? = nil) {
        screenSelectionPresenter.dismiss()
        let mode = hudState.mode ?? captureMode
        setHUDPhase(.choosingSourceType(mode))
        statusMessage = message ?? "Choose a source type."
        requestWindow(.showHUD)
    }

    private func presentScreenSelection(displaySources: [CaptureSource], mode: CaptureMode) {
        guard case .screenSelecting(let activeMode) = hudState.phase,
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
        let mode = hudState.mode ?? captureMode
        selectInteractiveAreaSource()
        setHUDPhase(.areaSelecting(mode))
        isAreaSelectionActive = true
        statusMessage = "Draw an area to capture."
        requestWindow(.showAreaSelector)
    }

    func completeInteractiveAreaSelection(_ area: CaptureArea) {
        isAreaSelectionActive = false
        selectInteractiveAreaSource(area: area)

        switch captureMode {
        case .recording:
            startRecording()
        case .screenshot:
            takeScreenshot()
        }
    }

    func cancelInteractiveAreaSelection() {
        cancelCapture()
    }

    func cancelCapture() {
        isAreaSelectionActive = false
        screenSelectionPresenter.dismiss()
        preferredSourceSelectorKind = nil
        setHUDPhase(.choosingMode)
        statusMessage = "Ready"
    }

    func requestWindow(_ action: NativeWindowCommandAction, editorSession: EditorSession? = nil) {
        windowCommand = NativeWindowCommand(action: action, editorSession: editorSession)
    }

    func showHUD() {
        guard canShowCaptureUI else {
            hudState = hudState.withPresentation(.hidden)
            return
        }
        hudState = hudState.withPresentation(.visible)
        requestWindow(.showHUD)
    }

    func hideHUD() {
        hudState = hudState.withPresentation(.hidden)
        requestWindow(.hideHUD)
    }

    func toggleHUDPresentation() {
        if hudState.presentation == .visible {
            hideHUD()
        } else {
            showHUD()
        }
    }

    func showEditor(for session: EditorSession) {
        screenSelectionPresenter.dismiss()
        hudState = .choosingMode
        isAreaSelectionActive = false
        preferredSourceSelectorKind = nil
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
        switch hudState.phase {
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
            hudState = hudState.withPresentation(.hidden)
        case .idle, .choosingMode:
            showHUD()
        }
    }

    private func setHUDPhase(_ phase: HUDPhase) {
        let previousPhase = hudState.phase
        hudState = hudState.withPhase(phase)

        if phase.requiresHiddenCaptureUI {
            screenSelectionPresenter.dismiss()
            return
        }

        if shouldCloseCaptureSetup(from: previousPhase, to: phase) {
            requestWindow(.closeCaptureSetup)
        }
    }

    private func shouldCloseCaptureSetup(from previousPhase: HUDPhase, to nextPhase: HUDPhase) -> Bool {
        guard case .choosingMode = nextPhase else {
            return false
        }

        switch previousPhase {
        case .choosingSourceType, .screenSelecting, .selectingSource, .ready, .areaSelecting:
            return true
        case .idle,
             .choosingMode,
             .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording,
             .capturingScreenshot:
            return false
        }
    }

    func toggleRecordingShortcut() {
        switch hudState.phase {
        case .ready(.recording, _):
            startRecording()
        case .countingDownRecording:
            cancelCountdownRecording()
        case .startingRecording:
            stopAfterRecordingStart = true
            statusMessage = "Recording will stop after it starts."
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
        guard let selectedSource = hudState.source ?? selectedSource else {
            statusMessage = "Choose a source first."
            return
        }
        guard recordingPhase == .idle else {
            return
        }

        do {
            let fileName = timestampedFileName(prefix: "recording", extension: "mp4")
            let prepared: PreparedFile = try service.call(
                "prepareRecordingFile",
                params: ["fileName": fileName],
                as: PreparedFile.self
            )
            let outputURL = URL(fileURLWithPath: prepared.path)
            statusMessage = "Recording starts in 3..."
            recordingPhase = .countingDown
            setHUDPhase(.countingDownRecording(selectedSource))
            stopAfterRecordingStart = false
            recordingStartTask?.cancel()
            recordingStartTask = Task { [weak self] in
                await self?.runRecordingStartFlow(source: selectedSource, outputURL: outputURL)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
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

            statusMessage = "Starting recording..."
            recordingPhase = .starting
            setHUDPhase(.startingRecording(selectedSource))

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
            recordingPhase = .recording
            setHUDPhase(.recording(selectedSource))
            recordingStartTask = nil
            if !statusMessage.hasPrefix("Recording without facecam") {
                statusMessage = "Recording \(selectedSource.name)"
            }
            if stopAfterRecordingStart {
                stopAfterRecordingStart = false
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
            recordingPhase = .interrupted
            restoreRecordingSetup(source: selectedSource, message: error.localizedDescription)
        }
    }

    private func cancelCountdownRecording() {
        guard case .countingDownRecording(let source) = hudState.phase else { return }
        recordingStartTask?.cancel()
        recordingStartTask = nil
        stopAfterRecordingStart = false
        countdownOverlayController.dismiss()
        restoreRecordingSetup(source: source, message: "Recording canceled.")
    }

    private func restoreRecordingSetup(source: CaptureSource, message: String? = nil) {
        recordingPhase = .idle
        stopAfterRecordingStart = false
        recordingStartTask = nil
        countdownOverlayController.dismiss()
        hudState = HUDState(phase: .ready(.recording, source), presentation: .visible)
        statusMessage = message ?? statusMessage
        requestWindow(source.kind == .display ? .showScreenRecordingSetup : .showRecordingSetup)
    }

    func stopRecording() {
        if recordingPhase == .countingDown {
            cancelCountdownRecording()
            return
        }
        if recordingPhase == .starting {
            stopAfterRecordingStart = true
            statusMessage = "Recording will stop after it starts."
            return
        }
        guard recordingPhase == .recording || capture.isRecording else {
            return
        }
        let source = hudState.source ?? selectedSource
        recordingPhase = .stopping
        if let source {
            setHUDPhase(.stoppingRecording(source))
        }
        Task {
            do {
                let outputURL = try await capture.stopRecording()
                let stoppedFacecamURL = try? await facecamRecorder.stop()
                let cursorTelemetryURL = cursorTelemetryRecorder.stop(videoURL: outputURL)
                currentVideoURL = outputURL
                currentScreenshotURL = nil

                if FileManager.default.fileExists(atPath: outputURL.path) {
                    let timelineEdits = await initialTimelineEdits(
                        videoURL: outputURL,
                        cursorTelemetryURL: cursorTelemetryURL
                    )
                    let recordingSession = RecordingSessionBuilder.build(
                        screenVideoURL: outputURL,
                        facecamURL: stoppedFacecamURL ?? activeFacecamURL,
                        sourceName: selectedSource?.name,
                        showCursor: showCursor,
                        cursorTelemetryURL: cursorTelemetryURL,
                        screenStartedAt: activeScreenStartedAt,
                        facecamStartedAt: activeFacecamStartedAt
                    )
                    let summary: ProjectSummary = try service.call(
                        "registerRecording",
                        params: [
                            "path": outputURL.path,
                            "sourceName": selectedSource?.name ?? "Screen Recording",
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
                    statusMessage = "Recording stopped before a file was written."
                }
            } catch {
                recordingPhase = .interrupted
                _ = cursorTelemetryRecorder.stop(videoURL: nil)
                statusMessage = error.localizedDescription
                if let source {
                    setHUDPhase(.ready(.recording, source))
                } else {
                    setHUDPhase(.choosingMode)
                }
            }
            activeScreenStartedAt = nil
            activeFacecamStartedAt = nil
            activeFacecamURL = nil
            recordingPhase = .idle
        }
    }

    func takeScreenshot() {
        guard let selectedSource = hudState.source ?? selectedSource else {
            statusMessage = "Choose a source first."
            return
        }
        guard !capture.isRecording else {
            statusMessage = "Finish or cancel the current capture before starting another."
            focusActiveCaptureWindow()
            return
        }

        do {
            setHUDPhase(.capturingScreenshot(selectedSource))
            Task { [weak self] in
                await self?.runScreenshotCapture(source: selectedSource)
            }
        }
    }

    private func runScreenshotCapture(source selectedSource: CaptureSource) async {
        do {
            if captureUIHideDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: captureUIHideDelayNanoseconds)
            } else {
                await Task.yield()
            }

            let ensuredPaths = try paths ?? service.call("paths", as: AppPaths.self)
            let outputURL = URL(fileURLWithPath: ensuredPaths.screenshotsDir)
                .appendingPathComponent(timestampedFileName(prefix: "screenshot", extension: "png"))
            try screenshotCapture(selectedSource, outputURL)
            let summary = registerScreenshotProject(outputURL, sourceName: selectedSource.name)
            currentScreenshotURL = outputURL
            currentVideoURL = nil
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
            restoreScreenshotSetup(source: selectedSource, message: "Screenshot canceled.")
        } catch {
            restoreScreenshotSetup(source: selectedSource, message: error.localizedDescription)
        }
    }

    private func restoreScreenshotSetup(source: CaptureSource, message: String) {
        hudState = HUDState(phase: .ready(.screenshot, source), presentation: .visible)
        statusMessage = message
        requestWindow(.showHUD)
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

    func requestScreenshotExport() {
        screenshotExportRequestID = UUID()
    }

    func requestVideoExport(_ recordingURL: URL? = nil) {
        guard let url = recordingURL ?? currentVideoURL else {
            statusMessage = "Open a recording first."
            return
        }
        videoExportRequestURL = url
        videoExportRequestID = UUID()
    }

    func exportCurrentRecording(_ recordingURL: URL? = nil, options: VideoExportOptions = .default, edits: TimelineEditSnapshot = .empty) {
        guard let url = recordingURL ?? currentVideoURL else {
            statusMessage = "Open a recording first."
            return
        }

        cancelVideoExportTask()
        resetVideoExportResult(removePendingFile: true)
        videoExportRequestURL = url
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
        videoExportRequestURL = nil
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
