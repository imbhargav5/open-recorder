import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct EditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?
    @ObservedObject var timelineEdits: TimelineEditController
    @ObservedObject var screenshotEditor: ScreenshotEditorController

    var body: some View {
        if screenshotURL != nil {
            ScreenshotEditorStudioView(screenshotURL: screenshotURL, editor: screenshotEditor)
        } else {
            VideoEditorStudioView(
                videoURL: videoURL,
                projectPath: projectPath,
                editorTitle: editorTitle,
                recordingSession: recordingSession,
                initialTimelineEdits: editorSession?.timelineEditSnapshot,
                initialVideoState: initialVideoState,
                editorSessionID: editorSession?.id,
                timelineEdits: timelineEdits
            )
        }
    }

    private var videoURL: URL? {
        if let editorSession {
            return editorSession.kind == .video ? editorSession.url : nil
        }
        return model.currentVideoURL
    }

    private var screenshotURL: URL? {
        if let editorSession {
            return editorSession.kind == .screenshot ? editorSession.url : nil
        }
        return model.currentScreenshotURL
    }

    private var recordingSession: RecordingSession? {
        editorSession?.recordingSession ?? model.lastEditorSession?.recordingSession
    }

    private var projectPath: String? {
        editorSession?.projectPath ?? model.lastEditorSession?.projectPath
    }

    private var editorTitle: String? {
        editorSession?.title ?? model.lastEditorSession?.title
    }

    private var initialVideoState: ProjectVideoEditorState? {
        editorSession?.videoEditorState ?? model.lastEditorSession?.videoEditorState
    }
}

struct VideoEditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var videoURL: URL?
    var projectPath: String?
    var editorTitle: String?
    var recordingSession: RecordingSession?
    var initialTimelineEdits: TimelineEditSnapshot?
    var initialVideoState: ProjectVideoEditorState?
    var editorSessionID: UUID?
    @StateObject private var playback = VideoPlaybackController()
    @StateObject private var autosave = ProjectAutosaveCoordinator()
    @ObservedObject var timelineEdits: TimelineEditController
    @State private var borderRadius = 12.0
    @State private var padding = 18.0
    @State private var shadow = 0.35
    @State private var backgroundBlur = 0.0
    @State private var background: BackgroundStyle = BackgroundPresets.default
    @State private var inset = 0.0
    @State private var insetColor = SerializableColor(hex: "#276FAA")
    @State private var insetOpacity = 1.0
    @State private var insetBalance = VideoInsetBalance.centered
    @State private var showCursorOverlay = true
    @State private var loopCursor = false
    @State private var cursorSize = 1.0
    @State private var cursorSmoothing = 0.40
    @State private var cursorStyle = CursorStyle.arrow
    @State private var cursorVariant = CursorVariant.standard
    @State private var facecamEnabled = false
    @State private var facecamShape = "circle"
    @State private var facecamSize = 22.0
    @State private var facecamCornerRadius = 24.0
    @State private var facecamBorderWidth = 4.0
    @State private var facecamBorderColor = "#FFFFFF"
    @State private var facecamMargin = 4.0
    @State private var facecamAnchor = FacecamAnchor.bottomRight.rawValue
    @State private var activeSheet: VideoEditorSheet?
    @State private var presentedSheet: VideoEditorSheet?
    @State private var videoCropSelection = VideoCropSelection.fullFrame
    @State private var previewAspectPreset: VideoPreviewAspectPreset = .auto
    @State private var appliedTimelineIdentity: String?
    @State private var appliedVideoStateIdentity: String?
    private let sidebarWidth: CGFloat = 320
    private let timelineHeight = TimelineMetrics.compactPanelHeight

    var body: some View {
        StudioSplitPane(
            axis: .horizontal,
            secondarySize: sidebarWidth,
            minPrimarySize: 520,
            minSecondarySize: 280,
            maxSecondarySize: 440
        ) {
            editorColumn
        } secondary: {
            sidebarContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .background(Color.studioMutedBackground)
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            switch sheet {
            case .export:
                exportDialog
            case .crop(let cropVideoURL):
                cropDialog(videoURL: cropVideoURL)
            }
        }
        .onChange(of: model.videoExportRequestID) { _, requestID in
            guard requestID != nil, videoURL != nil else { return }
            presentSheet(.export)
        }
        .onChange(of: videoURL) { _, _ in
            applyInitialEditorState(markAutosaved: true)
        }
        .onChange(of: editorSessionID) { _, _ in
            applyInitialEditorState(markAutosaved: true)
        }
        .onChange(of: autosaveSnapshot) { _, snapshot in
            autosave.schedule(snapshot)
        }
        .onAppear {
            autosave.configure(
                saveHandler: { snapshot in
                    try await model.autosaveProject(snapshot)
                },
                statusHandler: { status in
                    model.handleProjectAutosaveStatus(status)
                }
            )
            applyInitialEditorState(markAutosaved: true)
        }
        .onDisappear {
            let snapshot = autosaveSnapshot
            Task {
                await autosave.flush(snapshot)
            }
        }
        .background {
            StudioKeyDownMonitor { event in
                handleEditorShortcut(event)
            }
            .frame(width: 0, height: 0)
        }
    }

    private var editorColumn: some View {
        StudioSplitPane(
            axis: .vertical,
            secondarySize: timelineHeight,
            minPrimarySize: 260,
            minSecondarySize: TimelineMetrics.compactPanelHeight,
            maxSecondarySize: TimelineMetrics.compactPanelHeight
        ) {
            VideoPreviewPanel(
                videoURL: videoURL,
                recordingSession: recordingSession,
                playback: playback,
                timelineEdits: timelineEdits,
                background: background,
                padding: padding,
                borderRadius: borderRadius,
                shadow: shadow,
                backgroundBlur: backgroundBlur,
                inset: inset,
                insetColor: insetColor,
                insetOpacity: insetOpacity,
                insetBalance: insetBalance,
                cursorTelemetryURL: cursorTelemetryURL,
                cursorSettings: cursorOverlaySettings,
                cropSelection: videoCropSelection,
                facecamSettings: currentFacecamSettings,
                previewAspectPreset: $previewAspectPreset,
                onCropVideo: {
                    guard let videoURL else { return }
                    playback.pause()
                    presentSheet(.crop(videoURL))
                },
                onRequestClearSelection: {
                    timelineEdits.clearSelection()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } secondary: {
            TimelinePanel(videoURL: videoURL, playback: playback, edits: timelineEdits)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if timelineEdits.hasSelection {
            TimelineSelectionSidebar(edits: timelineEdits, playback: playback)
        } else {
            SettingsInspector(
                borderRadius: $borderRadius,
                padding: $padding,
                shadow: $shadow,
                backgroundBlur: $backgroundBlur,
                background: $background,
                inset: $inset,
                insetColor: $insetColor,
                insetOpacity: $insetOpacity,
                insetBalance: $insetBalance,
                showCursor: $showCursorOverlay,
                loopCursor: $loopCursor,
                cursorSize: $cursorSize,
                cursorSmoothing: $cursorSmoothing,
                cursorStyle: $cursorStyle,
                cursorVariant: $cursorVariant,
                facecamEnabled: $facecamEnabled,
                facecamSize: $facecamSize,
                facecamBorderWidth: $facecamBorderWidth,
                facecamAnchor: $facecamAnchor,
                recordingSession: recordingSession
            )
        }
    }

    private func handleEditorShortcut(_ event: NSEvent) -> Bool {
        guard !isTextInputActive else { return false }
        guard editorShortcutModifiersAreAllowed(event.modifierFlags) else { return false }

        let key = (event.charactersIgnoringModifiers ?? event.characters ?? "").lowercased()
        switch key {
        case " ":
            guard !event.isARepeat else { return true }
            playback.togglePlayback()
            return true
        case "z":
            guard !event.isARepeat else { return true }
            timelineEdits.add(.zoom, at: playback.currentTime, duration: playback.duration)
            return true
        case "s":
            guard !event.isARepeat else { return true }
            timelineEdits.cycleClipSpeed(at: playback.currentTime, duration: playback.duration)
            return true
        case "t":
            guard !event.isARepeat else { return true }
            timelineEdits.addClipSplit(at: playback.currentTime, duration: playback.duration)
            return true
        default:
            return false
        }
    }

    private var isTextInputActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func editorShortcutModifiersAreAllowed(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection([.command, .control, .option]).isEmpty
    }

    private var exportDialog: some View {
        VideoExportDialog(
            phase: model.videoExportPhase,
            progress: model.videoExportProgress,
            errorMessage: model.videoExportError,
            exportedFileName: model.exportedVideoURL?.lastPathComponent,
            isExporting: model.isVideoExporting,
            initialOptions: VideoExportOptions.default.withCropSelection(videoCropSelection),
            onExport: { options in
                let styled = styledExportOptions(from: options)
                let edits = timelineEdits.snapshot
                let recordingURL = model.videoExportRequestURL ?? videoURL
                let snapshot = autosaveSnapshot
                Task {
                    await autosave.flush(snapshot)
                    model.exportCurrentRecording(recordingURL, options: styled, edits: edits)
                }
            },
            onRetrySave: {
                model.retryPendingVideoExportSave()
            },
            onShowInFinder: {
                model.revealExportedVideoInFinder()
            },
            onCancelExport: {
                model.cancelVideoExport()
            },
            onClose: {
                activeSheet = nil
            }
        )
        .frame(width: 420)
        .interactiveDismissDisabled(model.videoExportPhase.isBusy)
    }

    private func cropDialog(videoURL: URL) -> some View {
        VideoCropDialog(
            videoURL: videoURL,
            initialSelection: videoCropSelection,
            initialTime: playback.currentTime,
            sourceSize: playback.naturalVideoSize,
            onConfirm: { selection in
                videoCropSelection = selection
                activeSheet = nil
            },
            onCancel: {
                activeSheet = nil
            }
        )
    }

    private func presentSheet(_ sheet: VideoEditorSheet) {
        presentedSheet = sheet
        activeSheet = sheet
    }

    private func handleSheetDismiss() {
        if presentedSheet == .export, !model.videoExportPhase.isBusy {
            model.clearVideoExportDialogState()
        }
        presentedSheet = nil
    }

    private func applyInitialEditorState(markAutosaved: Bool = false) {
        applyInitialTimelineEdits()
        applyInitialVideoState()
        if markAutosaved {
            autosave.markSaved(autosaveSnapshot)
        }
    }

    private func applyInitialTimelineEdits() {
        let identity = editorSessionID?.uuidString ?? videoURL?.path ?? "empty"
        guard appliedTimelineIdentity != identity else { return }
        appliedTimelineIdentity = identity
        timelineEdits.applySnapshot(initialTimelineEdits ?? .empty)
    }

    private func applyInitialVideoState() {
        let identity = editorSessionID?.uuidString ?? videoURL?.path ?? "empty"
        guard appliedVideoStateIdentity != identity else { return }
        appliedVideoStateIdentity = identity

        let state = initialVideoState
        let defaults = ProjectVideoEditorState.default
        background = state?.background ?? defaults.background
        padding = state?.padding ?? defaults.padding
        borderRadius = state?.borderRadius ?? defaults.borderRadius
        shadow = state?.shadow ?? defaults.shadow
        backgroundBlur = state?.backgroundBlur ?? defaults.backgroundBlur
        inset = state?.inset ?? defaults.inset
        insetColor = state?.insetColor ?? defaults.insetColor
        insetOpacity = state?.insetOpacity ?? defaults.insetOpacity
        insetBalance = state?.insetBalance ?? defaults.insetBalance
        videoCropSelection = state?.cropSelection ?? defaults.cropSelection
        previewAspectPreset = .auto

        let defaultCursor = CursorOverlaySettings(
            isVisible: recordingSession?.showCursorOverlay ?? model.showCursor,
            loops: defaults.cursorOverlay.loops,
            size: defaults.cursorOverlay.size,
            smoothing: defaults.cursorOverlay.smoothing
        )
        let cursor = state?.cursorOverlay ?? defaultCursor
        showCursorOverlay = cursor.isVisible
        loopCursor = cursor.loops
        cursorSize = cursor.size
        cursorSmoothing = cursor.smoothing
        cursorStyle = cursor.style
        cursorVariant = cursor.variant

        let facecam = (state?.facecamSettings
            ?? recordingSession?.facecamSettings
            ?? defaultFacecamSettings(enabled: recordingSession?.hasRecordedCamera == true))
            .clamped
        let hasRecordedCamera = recordingSession?.hasRecordedCamera == true
        facecamEnabled = hasRecordedCamera && facecam.enabled
        facecamShape = facecam.shape
        facecamSize = facecam.size
        facecamCornerRadius = facecam.cornerRadius
        facecamBorderWidth = facecam.borderWidth
        facecamBorderColor = facecam.borderColor
        facecamMargin = facecam.margin
        facecamAnchor = facecam.anchor
    }

    private func styledExportOptions(from options: VideoExportOptions) -> VideoExportOptions {
        options.with(
            background: background,
            padding: padding,
            borderRadius: borderRadius,
            shadow: shadow,
            backgroundBlur: backgroundBlur,
            inset: inset,
            insetColor: insetColor,
            insetOpacity: insetOpacity,
            insetBalance: insetBalance
        )
        .withAspectPreset(previewAspectPreset)
        .withCursorOverlay(cursorOverlaySettings, telemetryURL: cursorTelemetryURL)
    }

    private var autosaveSnapshot: ProjectAutosaveSnapshot? {
        guard let projectPath, let videoURL else { return nil }
        return ProjectAutosaveSnapshot(
            projectPath: projectPath,
            title: editorTitle ?? EditorMediaKind.video.displayTitle(for: videoURL),
            recordingPath: videoURL.path,
            sourceName: recordingSession?.sourceName,
            editorState: ProjectEditorState(timelineEdits: timelineEdits.snapshot, video: currentVideoState)
        )
    }

    private var currentVideoState: ProjectVideoEditorState {
        ProjectVideoEditorState(
            background: background,
            padding: padding,
            borderRadius: borderRadius,
            shadow: shadow,
            backgroundBlur: backgroundBlur,
            inset: inset,
            insetColor: insetColor,
            insetOpacity: insetOpacity,
            insetBalance: insetBalance,
            cropSelection: videoCropSelection,
            cursorOverlay: cursorOverlaySettings,
            facecamSettings: currentFacecamSettings
        )
    }

    private var currentFacecamSettings: FacecamSettings? {
        guard recordingSession?.hasRecordedCamera == true else {
            return nil
        }

        return FacecamSettings(
            enabled: facecamEnabled,
            shape: facecamShape,
            size: facecamSize,
            cornerRadius: facecamCornerRadius,
            borderWidth: facecamBorderWidth,
            borderColor: facecamBorderColor,
            margin: facecamMargin,
            anchor: facecamAnchor
        )
        .clamped
    }

    private var cursorOverlaySettings: CursorOverlaySettings {
        CursorOverlaySettings(
            isVisible: showCursorOverlay,
            loops: loopCursor,
            size: cursorSize,
            smoothing: cursorSmoothing,
            style: cursorStyle,
            variant: cursorStyle.resolvedVariant(cursorVariant)
        )
        .clamped
    }

    private var cursorTelemetryURL: URL? {
        if let path = recordingSession?.cursorTelemetryPath {
            return URL(fileURLWithPath: path)
        }

        guard let videoURL else { return nil }
        let derivedURL = CursorTelemetryRecorder.telemetryURL(for: videoURL)
        return FileManager.default.fileExists(atPath: derivedURL.path) ? derivedURL : nil
    }
}

private enum VideoEditorSheet: Identifiable, Equatable {
    case export
    case crop(URL)

    var id: String {
        switch self {
        case .export:
            "export"
        case .crop(let videoURL):
            "crop:\(videoURL.path)"
        }
    }
}
