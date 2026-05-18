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
    @State private var workspace = EditorWorkspaceDriver()

    var body: some View {
        VStack(spacing: 0) {
            StudioTitleBar(
                editorSession: editorSession,
                workspace: workspace
            )
            detailView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioBackground)
        .sheet(isPresented: workspace.shortcutsHelpBinding) {
            EditorShortcutsHelpDialog(isPresented: workspace.shortcutsHelpBinding)
        }
        .background {
            StudioKeyDownMonitor { event in
                handleShellShortcut(event)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            workspace.configure(
                setAppSection: { section in
                    model.selectedSection = section
                },
                setStatusMessage: { message in
                    model.statusMessage = message
                }
            )
            if model.selectedSection == .capture {
                workspace.send(.sectionSelected(.editor))
            } else {
                workspace.send(.appSectionSynced(model.selectedSection))
            }
        }
        .onChange(of: model.selectedSection) { _, section in
            workspace.send(.appSectionSynced(section))
        }
    }

    private func handleShellShortcut(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        guard event.modifierFlags.contains(.command),
              event.modifierFlags.intersection([.control, .option]).isEmpty else {
            return false
        }

        let key = (event.charactersIgnoringModifiers ?? event.characters ?? "").lowercased()
        if key == "k" {
            workspace.send(.shortcutsHelpToggled)
            return true
        }

        if key == "z", !isTextInputActive {
            if event.modifierFlags.contains(.shift) {
                return workspace.redoActiveEditor(kind: activeEditorMediaKind)
            }
            return workspace.undoActiveEditor(kind: activeEditorMediaKind)
        }

        return false
    }

    @ViewBuilder
    private var detailView: some View {
        switch workspace.state.selectedSection {
        case .capture:
            EditorStudioView(editorSession: editorSession, workspace: workspace)
        case .projects:
            ProjectsStudioView()
        case .editor:
            EditorStudioView(editorSession: editorSession, workspace: workspace)
        case .settings:
            SettingsStudioView()
        }
    }

    private var activeEditorMediaKind: EditorMediaKind? {
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

    private var isTextInputActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}

struct StudioNavBar: View {
    var selectedSection: AppSection
    var isScreenshotEditor: Bool
    var onSelectSection: (AppSection) -> Void
    var onToggleHelp: () -> Void

    private let items: [AppSection] = [.editor, .projects]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { section in
                StudioNavButton(
                    title: section.title,
                    symbolName: navSymbol(for: section),
                    isActive: selectedSection == section
                ) {
                    onSelectSection(section)
                }
            }

            StudioIconNavButton(title: "Help", symbolName: "questionmark.circle") {
                onToggleHelp()
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
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .background(isActive ? Color.brand : Color.clear, in: RoundedRectangle(cornerRadius: 7))
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

struct EditorHistoryButton: View {
    var title: String
    var symbolName: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(6), help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isEnabled ? Color.primary.opacity(0.86) : Color.secondary.opacity(0.38))
                .background(isEnabled ? Color.white.opacity(0.065) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

struct StudioTitleBar: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?
    var workspace: EditorWorkspaceDriver

    var body: some View {
        HStack(spacing: 12) {
            StudioNavBar(
                selectedSection: workspace.state.selectedSection,
                isScreenshotEditor: editorMediaKind == .screenshot,
                onSelectSection: { section in
                    workspace.send(.sectionSelected(section))
                },
                onToggleHelp: {
                    workspace.send(.shortcutsHelpToggled)
                }
            )

            titleLabel
                .frame(minWidth: 0, maxWidth: .infinity)

            HStack(spacing: 8) {
                editorHistoryControls
                exportButton
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Color.studioPanel.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                workspace.send(.timelineSelectionClearRequested)
            }
        )
    }

    @ViewBuilder
    private var editorHistoryControls: some View {
        if workspace.state.selectedSection == .editor, editorMediaKind != nil {
            HStack(spacing: 4) {
                EditorHistoryButton(title: "Undo", symbolName: "arrow.uturn.backward", isEnabled: canUndo) {
                    workspace.undoActiveEditor(kind: editorMediaKind)
                }
                EditorHistoryButton(title: "Redo", symbolName: "arrow.uturn.forward", isEnabled: canRedo) {
                    workspace.redoActiveEditor(kind: editorMediaKind)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.studioBorder.opacity(0.8), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if workspace.state.selectedSection == .editor, let videoURL {
            StudioButton(hitTarget: .rounded(7)) {
                workspace.send(.videoExportRequested(videoURL, editorSessionID: editorSession?.id))
            } label: {
                Label("Export Video", systemImage: "arrow.down.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(Color.white)
                }
        } else if workspace.state.selectedSection == .editor, screenshotURL != nil {
            StudioButton(hitTarget: .rounded(7)) {
                workspace.send(.screenshotExportRequested(screenshotURL, editorSessionID: editorSession?.id))
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

    private var canUndo: Bool {
        workspace.canUndo(kind: editorMediaKind)
    }

    private var canRedo: Bool {
        workspace.canRedo(kind: editorMediaKind)
    }

    private var titleLabel: some View {
        HStack(spacing: 7) {
            if workspace.state.selectedSection == .editor, let editorMediaKind {
                Image(systemName: editorMediaKind.titleIconSystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520, alignment: .leading)
        }
    }

    private var title: String {
        switch workspace.state.selectedSection {
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

struct EditorShortcutsHelpDialog: View {
    @Binding var isPresented: Bool

    private let shortcuts = [
        EditorShortcutHelpItem(keys: "Space", action: "Play or pause preview"),
        EditorShortcutHelpItem(keys: "Z", action: "Add zoom section at playhead"),
        EditorShortcutHelpItem(keys: "S", action: "Cycle selected clip speed"),
        EditorShortcutHelpItem(keys: "T", action: "Split clip at playhead"),
        EditorShortcutHelpItem(keys: "Cmd Z", action: "Undo editor change"),
        EditorShortcutHelpItem(keys: "Cmd Shift Z", action: "Redo editor change"),
        EditorShortcutHelpItem(keys: "Cmd K", action: "Toggle shortcuts")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                StudioButton(hitTarget: .circle, help: "Close") {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.secondary)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
            }

            VStack(spacing: 0) {
                ForEach(shortcuts) { shortcut in
                    HStack(spacing: 14) {
                        Text(shortcut.keys)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.primary)
                            .frame(width: 104, height: 30)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.studioBorder, lineWidth: 1)
                            }

                        Text(shortcut.action)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.secondary)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)

                    if shortcut.id != shortcuts.last?.id {
                        Rectangle()
                            .fill(Color.studioBorder.opacity(0.8))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 430)
        .background(Color.studioPanel)
        .background {
            StudioKeyDownMonitor { event in
                handleShortcut(event)
            }
            .frame(width: 0, height: 0)
        }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        let key = (event.charactersIgnoringModifiers ?? event.characters ?? "").lowercased()

        if key == "\u{1b}" {
            isPresented = false
            return true
        }

        guard event.modifierFlags.contains(.command),
              event.modifierFlags.intersection([.control, .option]).isEmpty,
              key == "k" else {
            return false
        }

        isPresented.toggle()
        return true
    }
}

struct EditorShortcutHelpItem: Identifiable {
    var keys: String
    var action: String

    var id: String { keys }
}
