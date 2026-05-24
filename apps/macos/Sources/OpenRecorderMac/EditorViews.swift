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
                editor: workspace.video,
                timelineEdits: workspace.timeline,
                videoExport: model.appShell.videoExport,
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
    @State private var playback = VideoPlaybackController()
    var editor: VideoEditorDriver
    var timelineEdits: TimelineEditDriver
    var videoExport: VideoExportDriver
    var exportRequest: EditorExportRequest?
    @State private var sidebarWidth: CGFloat = 320
    private let timelineHeight = TimelineMetrics.compactPanelHeight

    var body: some View {
        ResizableStudioSplitPane(
            secondarySize: $sidebarWidth,
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
        .background(Theme.appBgMuted)
        .sheet(item: editor.activeSheetBinding(exportIsBusy: videoExport.state.phase.isBusy)) { sheet in
            switch sheet {
            case .export:
                exportDialog
            case .crop(let cropVideoURL):
                cropDialog(videoURL: cropVideoURL)
            }
        }
        .onChange(of: exportRequest?.id) { _, requestID in
            guard requestID != nil, isVideoExportRequestTarget else { return }
            editor.send(.exportRequested)
        }
        .onChange(of: videoURL) { _, _ in
            syncEditorSession()
        }
        .onChange(of: editorSessionID) { _, _ in
            syncEditorSession()
        }
        .onChange(of: autosaveSnapshot) { _, snapshot in
            editor.send(.autosaveSnapshotChanged(snapshot))
        }
        .onAppear {
            editor.configure(
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
                    videoExport.export(sourceURL: recordingURL ?? model.currentVideoURL, options: options, edits: edits)
                },
                clearVideoExportDialogState: {
                    videoExport.clear()
                }
            )
            syncEditorSession()
        }
        .onDisappear {
            editor.send(.disappeared(autosaveSnapshot))
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
                background: editor.state.video.background,
                padding: editor.state.video.padding,
                borderRadius: editor.state.video.borderRadius,
                shadow: editor.state.video.shadow,
                backgroundBlur: editor.state.video.backgroundBlur,
                inset: editor.state.video.inset,
                insetColor: editor.state.video.insetColor,
                insetOpacity: editor.state.video.insetOpacity,
                insetBalance: editor.state.video.insetBalance,
                cursorTelemetryURL: cursorTelemetryURL,
                cursorSettings: editor.state.cursorOverlaySettings,
                cropSelection: editor.state.video.cropSelection,
                facecamSettings: editor.state.currentFacecamSettings,
                previewAspectPreset: editor.previewAspectPresetBinding,
                onCropVideo: {
                    guard let videoURL else { return }
                    editor.send(.cropRequested(videoURL))
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
                borderRadius: editor.binding(\.borderRadius),
                padding: editor.binding(\.padding),
                shadow: editor.binding(\.shadow),
                backgroundBlur: editor.binding(\.backgroundBlur),
                background: editor.binding(\.background),
                inset: editor.binding(\.inset),
                insetColor: editor.binding(\.insetColor),
                insetOpacity: editor.binding(\.insetOpacity),
                insetBalance: editor.binding(\.insetBalance),
                showCursor: editor.binding(\.cursorOverlay.isVisible),
                loopCursor: editor.binding(\.cursorOverlay.loops),
                cursorSize: editor.binding(\.cursorOverlay.size),
                cursorSmoothing: editor.binding(\.cursorOverlay.smoothing),
                cursorStyle: editor.binding(\.cursorOverlay.style),
                cursorVariant: editor.binding(\.cursorOverlay.variant),
                facecamEnabled: editor.facecamBinding(\.enabled, default: false),
                facecamSize: editor.facecamBinding(\.size, default: 22),
                facecamBorderWidth: editor.facecamBinding(\.borderWidth, default: 4),
                facecamAnchor: editor.facecamBinding(\.anchor, default: FacecamAnchor.bottomRight.rawValue),
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
            phase: videoExport.state.phase,
            progress: videoExport.state.progress,
            errorMessage: videoExport.state.errorMessage,
            exportedFileName: videoExport.state.exportedFileName,
            isExporting: videoExport.state.isExporting,
            resolution: editor.exportResolutionBinding,
            format: editor.state.exportDraft.format,
            frameRate: editor.exportFrameRateBinding,
            onExport: {
                editor.send(.exportConfirmed(
                    recordingURL: exportRequest?.url ?? videoURL,
                    edits: timelineEdits.snapshot,
                    snapshot: autosaveSnapshot,
                    cursorTelemetryURL: cursorTelemetryURL
                ))
            },
            onRetrySave: {
                videoExport.retrySave()
            },
            onShowInFinder: {
                videoExport.revealExportedFile()
            },
            onCancelExport: {
                videoExport.cancelExport()
            },
            onClose: {
                editor.send(.sheetDismissed(exportIsBusy: videoExport.state.phase.isBusy))
            }
        )
        .frame(width: 460)
        .interactiveDismissDisabled(videoExport.state.phase.isBusy)
    }

    private func cropDialog(videoURL: URL) -> some View {
        VideoCropDialog(
            videoURL: videoURL,
            initialSelection: editor.state.video.cropSelection,
            initialTime: playback.currentTime,
            sourceSize: playback.naturalVideoSize,
            onConfirm: { selection in
                editor.send(.cropConfirmed(selection))
            },
            onCancel: {
                editor.send(.cropCanceled)
            }
        )
    }

    private func syncEditorSession() {
        editor.send(.sessionChanged(VideoEditorSessionContext(
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
        editor.autosaveSnapshot(
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
