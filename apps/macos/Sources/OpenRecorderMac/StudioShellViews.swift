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
    @State private var sidebarExpanded = true

    var body: some View {
        HStack(spacing: 0) {
            StudioSidebar(isExpanded: sidebarExpanded)

            VStack(spacing: 0) {
                StudioTitleBar(sidebarExpanded: $sidebarExpanded, editorSession: editorSession)
                detailView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.studioBackground)
        .animation(.easeInOut(duration: 0.18), value: sidebarExpanded)
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

struct StudioSidebar: View {
    @EnvironmentObject private var model: AppModel
    var isExpanded: Bool

    private let items: [AppSection] = [.editor, .projects]
    private var isScreenshotEditor: Bool {
        model.currentScreenshotURL != nil && model.currentVideoURL == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: isExpanded ? 10 : 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brand.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.brand.opacity(0.24), lineWidth: 1)
                        }
                    Image(systemName: isScreenshotEditor ? "photo.fill" : "video.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brand)
                }
                .frame(width: 36, height: 36)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Recorder")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(isScreenshotEditor ? "Image Studio" : "Studio")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .padding(.horizontal, isExpanded ? 12 : 10)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.studioBorder)

            VStack(spacing: 4) {
                ForEach(items) { section in
                    SidebarButton(
                        title: section.title,
                        symbolName: sidebarSymbol(for: section),
                        isActive: model.selectedSection == section,
                        isExpanded: isExpanded
                    ) {
                        model.selectedSection = section
                    }
                }
            }
            .padding(8)

            Spacer()

            Divider()
                .overlay(Color.studioBorder)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            SidebarButton(title: "Help", symbolName: "questionmark.circle", isActive: false, isExpanded: isExpanded) {
                model.statusMessage = "Keyboard shortcuts are coming to the native editor."
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)

            if isExpanded {
                StatusFooter()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: isExpanded ? 224 : 56)
        .background(Color.studioPanel.opacity(0.95))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(width: 1)
        }
    }

    private func sidebarSymbol(for section: AppSection) -> String {
        switch section {
        case .editor: isScreenshotEditor ? "photo" : "video"
        case .projects: "folder.badge.gearshape"
        case .capture: "record.circle"
        case .settings: "gearshape"
        }
    }
}

struct SidebarButton: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    var isExpanded = true
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(8), help: title, action: action) {
            HStack(spacing: isExpanded ? 9 : 0) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, height: 18)
                if isExpanded {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isExpanded ? 10 : 0)
            .foregroundStyle(isActive ? Color.brand : Color.secondary)
            .background(isActive ? Color.brand.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct StatusFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.service.isAvailable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .shadow(color: model.service.isAvailable ? Color.green.opacity(0.55) : Color.orange.opacity(0.55), radius: 5)
            Text(model.statusMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StudioTitleBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var sidebarExpanded: Bool
    var editorSession: EditorSession?

    var body: some View {
        ZStack {
            HStack {
                StudioButton(hitTarget: .rectangle) {
                    sidebarExpanded.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .foregroundStyle(.secondary)

                Spacer()

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
            .padding(.horizontal, 12)

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
        .frame(height: 48)
        .background(Color.studioPanel.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)
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
