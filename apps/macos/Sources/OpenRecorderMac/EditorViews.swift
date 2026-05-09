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
    var videoURL: URL?
    var recordingSession: RecordingSession?
    @StateObject private var playback = VideoPlaybackController()
    @State private var borderRadius = 12.0
    @State private var padding = 18.0
    @State private var shadow = 0.35
    @State private var backgroundBlur = 0.0
    @State private var loopCursor = false
    @State private var cursorSize = 1.0
    @State private var cursorSmoothing = 0.40

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                VideoPreviewPanel(videoURL: videoURL, recordingSession: recordingSession, playback: playback)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                TimelinePanel(videoURL: videoURL, playback: playback)
                    .frame(height: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SettingsInspector(
                borderRadius: $borderRadius,
                padding: $padding,
                shadow: $shadow,
                backgroundBlur: $backgroundBlur,
                loopCursor: $loopCursor,
                cursorSize: $cursorSize,
                cursorSmoothing: $cursorSmoothing,
                recordingSession: recordingSession
            )
            .frame(width: 320)
        }
        .padding(16)
        .background(Color.studioMutedBackground)
    }
}

