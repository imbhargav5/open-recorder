import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct EditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?
    var workspace: EditorWorkspaceDriver

    var body: some View {
        if screenshotURL != nil {
            ScreenshotEditorStudioView(
                screenshotURL: screenshotURL,
                projectPath: projectPath,
                editorTitle: editorTitle,
                initialScreenshotState: initialScreenshotState,
                editorSessionID: editorSession?.id,
                editor: workspace.screenshot,
                exportRequest: workspace.state.screenshotExportRequest
            )
        } else {
            VideoEditorStudioView(
                videoURL: videoURL,
                projectPath: projectPath,
                editorTitle: editorTitle,
                recordingSession: recordingSession,
                initialTimelineEdits: editorSession?.timelineEditSnapshot,
                initialVideoState: initialVideoState,
                editorSessionID: editorSession?.id,
                timelineEdits: workspace.timeline,
                exportRequest: workspace.state.videoExportRequest
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

    private var initialScreenshotState: ScreenshotEditorState? {
        editorSession?.screenshotEditorState ?? model.lastEditorSession?.screenshotEditorState
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
    var timelineEdits: TimelineEditDriver
    var exportRequest: EditorExportRequest?
    @State private var driver = VideoEditorDriver()
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
        .sheet(item: driver.activeSheetBinding(exportIsBusy: model.videoExportPhase.isBusy)) { sheet in
            switch sheet {
            case .export:
                exportDialog
            case .crop(let cropVideoURL):
                cropDialog(videoURL: cropVideoURL)
            }
        }
        .onChange(of: exportRequest?.id) { _, requestID in
            guard requestID != nil, isVideoExportRequestTarget else { return }
            driver.send(.exportRequested)
        }
        .onChange(of: videoURL) { _, _ in
            syncEditorSession()
        }
        .onChange(of: editorSessionID) { _, _ in
            syncEditorSession()
        }
        .onChange(of: autosaveSnapshot) { _, snapshot in
            driver.send(.autosaveSnapshotChanged(snapshot))
        }
        .onAppear {
            driver.configure(
                applyTimelineSnapshot: { snapshot in
                    timelineEdits.applySnapshot(snapshot)
                },
                saveHandler: { snapshot in
                    try await model.autosaveProject(snapshot)
                },
                statusHandler: { status in
                    model.handleProjectAutosaveStatus(status)
                },
                pausePlayback: {
                    playback.pause()
                },
                exportVideo: { recordingURL, options, edits in
                    model.exportCurrentRecording(recordingURL, options: options, edits: edits)
                },
                clearVideoExportDialogState: {
                    model.clearVideoExportDialogState()
                }
            )
            syncEditorSession()
        }
        .onDisappear {
            driver.send(.disappeared(autosaveSnapshot))
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
                background: driver.state.video.background,
                padding: driver.state.video.padding,
                borderRadius: driver.state.video.borderRadius,
                shadow: driver.state.video.shadow,
                backgroundBlur: driver.state.video.backgroundBlur,
                inset: driver.state.video.inset,
                insetColor: driver.state.video.insetColor,
                insetOpacity: driver.state.video.insetOpacity,
                insetBalance: driver.state.video.insetBalance,
                cursorTelemetryURL: cursorTelemetryURL,
                cursorSettings: driver.state.cursorOverlaySettings,
                cropSelection: driver.state.video.cropSelection,
                facecamSettings: driver.state.currentFacecamSettings,
                previewAspectPreset: driver.previewAspectPresetBinding,
                onCropVideo: {
                    guard let videoURL else { return }
                    driver.send(.cropRequested(videoURL))
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
                borderRadius: driver.binding(\.borderRadius),
                padding: driver.binding(\.padding),
                shadow: driver.binding(\.shadow),
                backgroundBlur: driver.binding(\.backgroundBlur),
                background: driver.binding(\.background),
                inset: driver.binding(\.inset),
                insetColor: driver.binding(\.insetColor),
                insetOpacity: driver.binding(\.insetOpacity),
                insetBalance: driver.binding(\.insetBalance),
                showCursor: driver.binding(\.cursorOverlay.isVisible),
                loopCursor: driver.binding(\.cursorOverlay.loops),
                cursorSize: driver.binding(\.cursorOverlay.size),
                cursorSmoothing: driver.binding(\.cursorOverlay.smoothing),
                cursorStyle: driver.binding(\.cursorOverlay.style),
                cursorVariant: driver.binding(\.cursorOverlay.variant),
                facecamEnabled: driver.facecamBinding(\.enabled, default: false),
                facecamSize: driver.facecamBinding(\.size, default: 22),
                facecamBorderWidth: driver.facecamBinding(\.borderWidth, default: 4),
                facecamAnchor: driver.facecamBinding(\.anchor, default: FacecamAnchor.bottomRight.rawValue),
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
            resolution: driver.exportResolutionBinding,
            format: driver.state.exportDraft.format,
            frameRate: driver.exportFrameRateBinding,
            onExport: {
                driver.send(.exportConfirmed(
                    recordingURL: exportRequest?.url ?? videoURL,
                    edits: timelineEdits.snapshot,
                    snapshot: autosaveSnapshot,
                    cursorTelemetryURL: cursorTelemetryURL
                ))
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
                driver.send(.sheetDismissed(exportIsBusy: model.videoExportPhase.isBusy))
            }
        )
        .frame(width: 420)
        .interactiveDismissDisabled(model.videoExportPhase.isBusy)
    }

    private func cropDialog(videoURL: URL) -> some View {
        VideoCropDialog(
            videoURL: videoURL,
            initialSelection: driver.state.video.cropSelection,
            initialTime: playback.currentTime,
            sourceSize: playback.naturalVideoSize,
            onConfirm: { selection in
                driver.send(.cropConfirmed(selection))
            },
            onCancel: {
                driver.send(.cropCanceled)
            }
        )
    }

    private func syncEditorSession() {
        driver.send(.sessionChanged(VideoEditorSessionContext(
            videoURL: videoURL,
            projectPath: projectPath,
            editorTitle: editorTitle,
            recordingSession: recordingSession,
            initialTimelineEdits: initialTimelineEdits,
            initialVideoState: initialVideoState,
            editorSessionID: editorSessionID,
            defaultShowCursor: model.showCursor
        )))
    }

    private var autosaveSnapshot: ProjectAutosaveSnapshot? {
        driver.autosaveSnapshot(
            projectPath: projectPath,
            videoURL: videoURL,
            editorTitle: editorTitle,
            recordingSession: recordingSession,
            timelineEdits: timelineEdits.snapshot
        )
    }

    private var cursorTelemetryURL: URL? {
        if let path = recordingSession?.cursorTelemetryPath {
            return URL(fileURLWithPath: path)
        }

        guard let videoURL else { return nil }
        let derivedURL = CursorTelemetryRecorder.telemetryURL(for: videoURL)
        return FileManager.default.fileExists(atPath: derivedURL.path) ? derivedURL : nil
    }

    private var isVideoExportRequestTarget: Bool {
        guard let videoURL else { return false }
        if let requestedEditorSessionID = exportRequest?.editorSessionID {
            return requestedEditorSessionID == editorSessionID
        }
        if let requestedURL = exportRequest?.url {
            return requestedURL == videoURL
        }
        return true
    }
}
