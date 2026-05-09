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

    let service = RustServiceClient()
    let capture = CaptureController()
    private let facecamRecorder = FacecamRecorder()
    private let cursorTelemetryRecorder = CursorTelemetryRecorder()
    private let captureDeviceProvider = CaptureDeviceProvider()

    var captureFlow: CaptureFlow {
        hudState.captureFlow
    }

    func bootstrap() {
        Task {
            await refreshSources()
            refreshCaptureDevices()
        }
        refreshBackendState()
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
        await capture.reloadSources(requestScreenRecordingPermission: requestScreenRecordingPermission)
        if selectedSource == nil || !capture.sources.contains(where: { $0.id == selectedSource?.id }) {
            selectedSource = capture.sources.first
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
        if let selectedSource {
            hudState = .ready(mode, selectedSource)
        } else {
            hudState = .selectingSource(mode)
        }
        statusMessage = selectedSource == nil ? "Choose a source." : "Ready"
        requestWindow(.showSourceSelector)
    }

    func selectSource(_ source: CaptureSource) {
        selectedSource = source
        hudState = .ready(hudState.mode ?? captureMode, source)
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
        selectedSource = source
        hudState = .ready(hudState.mode ?? captureMode, source)
        statusMessage = "Selected area"
    }

    func requestInteractiveAreaSelection() {
        let mode = hudState.mode ?? captureMode
        selectInteractiveAreaSource()
        hudState = .areaSelecting(mode)
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
        hudState = .choosingMode
        statusMessage = "Ready"
        requestWindow(.closeAreaSelector)
    }

    func requestWindow(_ action: NativeWindowCommandAction, editorSession: EditorSession? = nil) {
        windowCommand = NativeWindowCommand(action: action, editorSession: editorSession)
    }

    func showEditor(for session: EditorSession) {
        hudState = .choosingMode
        isAreaSelectionActive = false
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
        switch hudState {
        case .selectingSource, .ready, .areaSelecting:
            requestWindow(.showSourceSelector)
        case .startingRecording, .recording, .stoppingRecording, .capturingScreenshot:
            requestWindow(.showHUD)
        case .idle, .choosingMode:
            requestWindow(.showHUD)
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
            statusMessage = "Starting recording..."
            recordingPhase = .starting
            hudState = .startingRecording(selectedSource)
            Task {
                do {
                    refreshCaptureDevices()
                    let options = currentCaptureOptions
                    guard await preparePermissions(for: options) else {
                        recordingPhase = .idle
                        hudState = .ready(.recording, selectedSource)
                        return
                    }

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
                    requestWindow(.closeSourceSelector)
                    recordingPhase = .recording
                    hudState = .recording(selectedSource)
                    if !statusMessage.hasPrefix("Recording without facecam") {
                        statusMessage = "Recording \(selectedSource.name)"
                    }
                } catch {
                    facecamRecorder.cancel()
                    _ = cursorTelemetryRecorder.stop(videoURL: nil)
                    activeScreenStartedAt = nil
                    activeFacecamStartedAt = nil
                    activeFacecamURL = nil
                    recordingPhase = .interrupted
                    statusMessage = error.localizedDescription
                    recordingPhase = .idle
                    hudState = .ready(.recording, selectedSource)
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard recordingPhase == .recording || capture.isRecording else {
            return
        }
        let source = hudState.source ?? selectedSource
        recordingPhase = .stopping
        if let source {
            hudState = .stoppingRecording(source)
        }
        Task {
            do {
                let outputURL = try await capture.stopRecording()
                let stoppedFacecamURL = try? await facecamRecorder.stop()
                let cursorTelemetryURL = cursorTelemetryRecorder.stop(videoURL: outputURL)
                currentVideoURL = outputURL
                currentScreenshotURL = nil

                if FileManager.default.fileExists(atPath: outputURL.path) {
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
                            "title": outputURL.deletingPathExtension().lastPathComponent
                        ],
                        as: ProjectSummary.self
                    )
                    projects = try service.call("listProjects", as: [ProjectSummary].self)
                    showEditor(for: EditorSession(
                        kind: .video,
                        url: outputURL,
                        title: summary.title,
                        recordingSession: recordingSession
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
                    hudState = .ready(.recording, source)
                } else {
                    hudState = .choosingMode
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
            hudState = .capturingScreenshot(selectedSource)
            let ensuredPaths = try paths ?? service.call("paths", as: AppPaths.self)
            let outputURL = URL(fileURLWithPath: ensuredPaths.screenshotsDir)
                .appendingPathComponent(timestampedFileName(prefix: "screenshot", extension: "png"))
            try capture.takeScreenshot(source: selectedSource, outputURL: outputURL)
            let _: PreparedFile = try service.call(
                "rememberScreenshot",
                params: ["path": outputURL.path],
                as: PreparedFile.self
            )
            currentScreenshotURL = outputURL
            currentVideoURL = nil
            showEditor(for: EditorSession(kind: .screenshot, url: outputURL))
            statusMessage = "Captured \(outputURL.lastPathComponent)"
        } catch {
            hudState = .ready(.screenshot, selectedSource)
            statusMessage = error.localizedDescription
        }
    }

    func openProject(_ project: ProjectSummary) {
        if let recordingPath = project.recordingPath {
            let recordingURL = URL(fileURLWithPath: recordingPath)
            currentVideoURL = recordingURL
            currentScreenshotURL = nil
            showEditor(for: EditorSession(kind: .video, url: recordingURL, title: project.title))
            statusMessage = "Opened \(project.title)"
        } else {
            statusMessage = "Project has no recording path."
        }
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

    func openProjectFile(at projectURL: URL) {
        do {
            let document: ProjectDocument = try service.call(
                "loadProject",
                params: ["path": projectURL.path],
                as: ProjectDocument.self
            )
            if let recordingPath = document.recordingPath {
                let recordingURL = URL(fileURLWithPath: recordingPath)
                currentVideoURL = recordingURL
                currentScreenshotURL = nil
                showEditor(for: EditorSession(kind: .video, url: recordingURL, title: document.title))
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

    func exportCurrentRecording(_ recordingURL: URL? = nil, options: VideoExportOptions = .default) {
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
                cancellationToken: cancellationToken
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
        cancellationToken: VideoExportCancellationToken
    ) async {
        do {
            try await VideoExportRenderer.export(
                sourceURL: sourceURL,
                targetURL: targetURL,
                options: options,
                cancellationToken: cancellationToken,
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
        let suffix = "\(options.resolution.fileSuffix)-\(options.frameRate.fileSuffix)"
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
