import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct StudioWindowView: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?

    var body: some View {
        StudioShell(editorSession: editorSession)
            .onAppear {
                if model.selectedSection == .capture {
                    model.selectedSection = .editor
                }
            }
    }
}


struct StudioShell: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?

    var body: some View {
        VStack(spacing: 0) {
            StudioTitleBar(editorSession: editorSession)
            detailView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioBackground)
        .onAppear {
            if model.selectedSection == .capture {
                model.selectedSection = .editor
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selectedSection {
        case .capture:
            EditorStudioView(editorSession: editorSession)
        case .projects:
            ProjectsStudioView()
        case .editor:
            EditorStudioView(editorSession: editorSession)
        case .settings:
            SettingsStudioView()
        }
    }
}

struct StudioNavBar: View {
    @EnvironmentObject private var model: AppModel

    private let items: [AppSection] = [.editor, .projects]
    private var isScreenshotEditor: Bool {
        model.currentScreenshotURL != nil && model.currentVideoURL == nil
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { section in
                StudioNavButton(
                    title: section.title,
                    symbolName: navSymbol(for: section),
                    isActive: model.selectedSection == section
                ) {
                    model.selectedSection = section
                }
            }

            StudioIconNavButton(title: "Help", symbolName: "questionmark.circle") {
                model.statusMessage = "Keyboard shortcuts are coming to the native editor."
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.studioBorder.opacity(0.8), lineWidth: 1)
        }
    }

    private func navSymbol(for section: AppSection) -> String {
        switch section {
        case .editor: isScreenshotEditor ? "photo" : "video"
        case .projects: "folder.badge.gearshape"
        case .capture: "record.circle"
        case .settings: "gearshape"
        }
    }
}

struct StudioNavButton: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(7), help: title, action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(height: 30)
            .padding(.horizontal, 10)
            .foregroundStyle(isActive ? Color.brand : Color.secondary)
            .background(isActive ? Color.brand.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

struct StudioIconNavButton: View {
    var title: String
    var symbolName: String
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(7), help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(Color.secondary)
                .background(Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

struct StudioTitleBar: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?

    var body: some View {
        HStack(spacing: 12) {
            StudioNavBar()

            titleLabel
                .frame(minWidth: 0, maxWidth: .infinity)

            exportButton
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Color.studioPanel.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if model.selectedSection == .editor, let videoURL {
            StudioButton(hitTarget: .rounded(7)) {
                model.requestVideoExport(videoURL)
            } label: {
                Label("Export Video", systemImage: "arrow.down.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(Color.white)
            }
        } else if model.selectedSection == .editor, screenshotURL != nil {
            StudioButton(hitTarget: .rounded(7)) {
                model.requestScreenshotExport()
            } label: {
                Label("Export PNG", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(Color.white)
            }
        }
    }

    private var titleLabel: some View {
        HStack(spacing: 7) {
            if model.selectedSection == .editor, let editorMediaKind {
                Image(systemName: editorMediaKind.titleIconSystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
        }
    }

    private var title: String {
        switch model.selectedSection {
        case .capture:
            "Capture"
        case .projects:
            "Projects"
        case .settings:
            "Settings"
        case .editor:
            if let editorSession {
                editorSession.displayTitle
            } else if let currentVideoURL = model.currentVideoURL {
                EditorMediaKind.video.displayTitle(for: currentVideoURL)
            } else if let currentScreenshotURL = model.currentScreenshotURL {
                EditorMediaKind.screenshot.displayTitle(for: currentScreenshotURL)
            } else {
                "Open Recorder Editor"
            }
        }
    }

    private var editorMediaKind: EditorMediaKind? {
        if let editorSession {
            return editorSession.kind
        }
        if model.currentVideoURL != nil {
            return .video
        }
        if model.currentScreenshotURL != nil {
            return .screenshot
        }
        return nil
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
}
