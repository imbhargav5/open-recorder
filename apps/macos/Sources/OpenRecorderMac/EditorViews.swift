import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct EditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?
    @ObservedObject var timelineEdits: TimelineEditController

    var body: some View {
        if screenshotURL != nil {
            ScreenshotEditorStudioView(screenshotURL: screenshotURL)
        } else {
            VideoEditorStudioView(videoURL: videoURL, recordingSession: recordingSession, timelineEdits: timelineEdits)
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
    @ObservedObject var timelineEdits: TimelineEditController
    @State private var borderRadius = 12.0
    @State private var padding = 18.0
    @State private var shadow = 0.35
    @State private var backgroundBlur = 0.0
    @State private var background: BackgroundStyle = BackgroundPresets.default
    @State private var loopCursor = false
    @State private var cursorSize = 1.0
    @State private var cursorSmoothing = 0.40
    @State private var isExportDialogPresented = false
    @AppStorage("editor.video.sidebarWidth") private var sidebarWidth = 320.0
    @AppStorage("editor.video.timelineHeight") private var timelineHeight = 320.0

    var body: some View {
        StudioSplitPane(
            axis: .horizontal,
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
            secondarySize: $timelineHeight,
            minPrimarySize: 260,
            minSecondarySize: 280,
            maxSecondarySize: 420,
            dividerThickness: 12
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
                loopCursor: $loopCursor,
                cursorSize: $cursorSize,
                cursorSmoothing: $cursorSmoothing,
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
            timelineEdits.add(.speed, at: playback.currentTime, duration: playback.duration)
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
}
