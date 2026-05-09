import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct EditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?

    var body: some View {
        if screenshotURL != nil {
            ScreenshotEditorStudioView(screenshotURL: screenshotURL)
        } else {
            VideoEditorStudioView(videoURL: videoURL, recordingSession: recordingSession)
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
}

struct VideoEditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var videoURL: URL?
    var recordingSession: RecordingSession?
    @StateObject private var playback = VideoPlaybackController()
    @StateObject private var timelineEdits = TimelineEditController()
    @State private var borderRadius = 12.0
    @State private var padding = 18.0
    @State private var shadow = 0.35
    @State private var backgroundBlur = 0.0
    @State private var background: BackgroundStyle = BackgroundPresets.default
    @State private var loopCursor = false
    @State private var cursorSize = 1.0
    @State private var cursorSmoothing = 0.40
    @State private var isExportDialogPresented = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                VideoPreviewPanel(
                    videoURL: videoURL,
                    recordingSession: recordingSession,
                    playback: playback,
                    timelineEdits: timelineEdits,
                    background: background,
                    padding: padding,
                    borderRadius: borderRadius,
                    shadow: shadow,
                    backgroundBlur: backgroundBlur
                )
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                TimelinePanel(videoURL: videoURL, playback: playback, edits: timelineEdits)
                    .frame(height: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SettingsInspector(
                borderRadius: $borderRadius,
                padding: $padding,
                shadow: $shadow,
                backgroundBlur: $backgroundBlur,
                background: $background,
                loopCursor: $loopCursor,
                cursorSize: $cursorSize,
                cursorSmoothing: $cursorSmoothing,
                recordingSession: recordingSession
            )
            .frame(width: 320)
        }
        .padding(16)
        .background(Color.studioMutedBackground)
        .sheet(
            isPresented: $isExportDialogPresented,
            onDismiss: {
                if !model.videoExportPhase.isBusy {
                    model.clearVideoExportDialogState()
                }
            }
        ) {
            VideoExportDialog(
                phase: model.videoExportPhase,
                progress: model.videoExportProgress,
                errorMessage: model.videoExportError,
                exportedFileName: model.exportedVideoURL?.lastPathComponent,
                isExporting: model.isVideoExporting,
                onExport: { options in
                    let styled = options.with(
                        background: background,
                        padding: padding,
                        borderRadius: borderRadius,
                        shadow: shadow,
                        backgroundBlur: backgroundBlur
                    )
                    model.exportCurrentRecording(model.videoExportRequestURL ?? videoURL, options: styled, edits: timelineEdits.snapshot)
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
                    isExportDialogPresented = false
                }
            )
            .frame(width: 420)
            .interactiveDismissDisabled(model.videoExportPhase.isBusy)
        }
        .onChange(of: model.videoExportRequestID) { _, requestID in
            guard requestID != nil, videoURL != nil else { return }
            isExportDialogPresented = true
        }
    }
}
