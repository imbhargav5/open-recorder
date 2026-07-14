import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct EditorSessionMetadata: Equatable {
    var recordingSession: RecordingSession?
    var projectPath: String?
    var title: String?
    var videoEditorState: ProjectVideoEditorState?
    var screenshotEditorState: ScreenshotEditorState?

    init(explicitSession: EditorSession?, fallbackSession: EditorSession?) {
        let source = explicitSession ?? fallbackSession
        recordingSession = source?.recordingSession
        projectPath = source?.projectPath
        title = source?.title
        videoEditorState = source?.videoEditorState
        screenshotEditorState = source?.screenshotEditorState
    }
}

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
                workspace: workspace,
                editor: workspace.screenshot,
                exportRequest: workspace.state.screenshotExportRequest
            )
        } else if videoURL != nil {
            VideoEditorStudioView(
                videoURL: videoURL,
                projectPath: projectPath,
                editorTitle: editorTitle,
                recordingSession: recordingSession,
                initialTimelineEdits: editorSession?.timelineEditSnapshot,
                initialVideoState: initialVideoState,
                editorSessionID: editorSession?.id,
                workspace: workspace,
                editor: workspace.video,
                timelineEdits: workspace.timeline,
                videoExport: workspace.videoExport,
                exportRequest: workspace.state.videoExportRequest
            )
        } else {
            ContentUnavailableView {
                Label("No Capture Open", systemImage: "rectangle.on.rectangle.slash")
            } description: {
                Text("Open an Open Recorder project or start a new recording to edit it here.")
            } actions: {
                Button("Open Project…") {
                    model.openProjectFile()
                }
                .buttonStyle(.borderedProminent)

                Button("New Recording") {
                    model.beginCapture(.recording)
                }
                .disabled(!model.canStartNewCapture)
            }
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
        sessionMetadata.recordingSession
    }

    private var projectPath: String? {
        sessionMetadata.projectPath
    }

    private var editorTitle: String? {
        sessionMetadata.title
    }

    private var initialVideoState: ProjectVideoEditorState? {
        sessionMetadata.videoEditorState
    }

    private var initialScreenshotState: ScreenshotEditorState? {
        sessionMetadata.screenshotEditorState
    }

    private var sessionMetadata: EditorSessionMetadata {
        EditorSessionMetadata(
            explicitSession: editorSession,
            fallbackSession: model.lastEditorSession
        )
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
    var workspace: EditorWorkspaceDriver
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
                saveHandler: { [weak model] snapshot in
                    guard let model else { throw CancellationError() }
                    return try await model.autosaveProject(snapshot)
                },
                statusHandler: { [weak workspace, weak model] status in
                    workspace?.handleProjectAutosaveStatus(status, source: .video)
                    model?.handleProjectAutosaveStatus(status)
                },
                pausePlayback: { [weak playback] in
                    playback?.pause()
                },
                exportVideo: { [weak model, weak videoExport] recordingURL, options, edits in
                    videoExport?.export(sourceURL: recordingURL ?? model?.currentVideoURL, options: options, edits: edits)
                },
                clearVideoExportDialogState: { [weak videoExport] in
                    videoExport?.clear()
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
                cameraTimelineFallback: editor.state.currentFacecamSettings,
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
            TimelinePanel(
                videoURL: videoURL,
                playback: playback,
                edits: timelineEdits,
                hasRecordedCamera: editor.state.hasRecordedCamera,
                defaultCameraSettings: editor.state.currentFacecamSettings
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if timelineEdits.hasSelection {
            TimelineSelectionSidebar(
                edits: timelineEdits,
                playback: playback,
                defaultCameraSettings: editor.state.currentFacecamSettings
            )
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
                cursorStyleID: editor.binding(\.cursorOverlay.styleID),
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
            format: editor.exportFormatBinding,
            frameRate: editor.exportFrameRateBinding,
            quality: editor.exportQualityBinding,
            gifSize: editor.exportGIFSizeBinding,
            gifLoops: editor.exportGIFLoopsBinding,
            onExport: {
                editor.send(.exportConfirmed(
                    recordingURL: exportRequest?.url ?? videoURL,
                    edits: timelineEdits.snapshot,
                    snapshot: autosaveSnapshot,
                    cursorTelemetryURL: cursorTelemetryURL,
                    facecamVideoURL: facecamVideoURL,
                    facecamOffsetMs: recordingSession?.facecamOffsetMs,
                    cameraFallback: editor.state.currentFacecamSettings
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

    private var facecamVideoURL: URL? {
        guard let path = recordingSession?.facecamVideoPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
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
