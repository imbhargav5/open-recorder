import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct StudioWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    var editorSession: EditorSession?

    var body: some View {
        let workspace = model.appShell.workspace(for: editorSession)
        StudioShell(editorSession: editorSession, workspace: workspace)
            .alert("Couldn’t Save Changes", isPresented: workspace.autosaveRecoveryBinding) {
                Button("Retry and Close") {
                    Task {
                        guard await workspace.retryPendingAutosaves() else { return }
                        let outcome = await model.appShell.closeWorkspace(for: editorSession)
                        if outcome == .autosaveFailed {
                            model.appShell.activateWorkspace(for: editorSession)
                        }
                        guard outcome == .closed else { return }
                        dismissEditorWindow()
                    }
                }
                Button("Close Without Saving", role: .destructive) {
                    guard model.appShell.discardWorkspace(for: editorSession) else { return }
                    dismissEditorWindow()
                }
                .disabled(!workspace.canAbandonPendingAutosaves)
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text(autosaveRecoveryMessage(for: workspace))
            }
            .background {
                StudioWindowCloseInterceptor {
                    guard let request = model.appShell.beginClosingWorkspace(for: editorSession) else {
                        return true
                    }
                    let outcome = await model.appShell.finishClosingWorkspace(request)
                    if outcome == .autosaveFailed {
                        model.appShell.activateWorkspace(for: editorSession)
                    }
                    return outcome == .closed
                }
                .frame(width: 0, height: 0)
            }
            .onAppear {
                model.appShell.activateWorkspace(for: editorSession)
                if editorSession == nil, model.selectedSection == .capture {
                    model.selectedSection = .editor
                }
            }
            .task(id: workspace.state.statusSeverity) {
                guard workspace.state.statusSeverity == .failure else { return }
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      !workspace.state.isAutosaveRecoveryPresented else {
                    return
                }
                announceAutosaveFailure(workspace.state.autosaveFailureMessage)
            }
    }

    private func dismissEditorWindow() {
        if let editorSession {
            dismissWindow(id: "editor", value: editorSession)
        } else {
            dismissWindow(id: "studio")
        }
    }

    private func autosaveRecoveryMessage(for workspace: EditorWorkspaceDriver) -> String {
        let reason = workspace.state.autosaveFailureMessage
            ?? "Open Recorder couldn’t save the latest changes."
        if workspace.canAbandonPendingAutosaves {
            return "Your latest edits haven’t been saved to disk. \(reason) Retry, keep editing, or close and discard them."
        }
        return "Your latest edits haven’t been saved to disk. \(reason) Keep editing while the current save finishes, or retry and close afterward."
    }

    private func announceAutosaveFailure(_ message: String?) {
        guard let message else { return }
        let element: Any
        if let keyWindow = NSApp.keyWindow {
            element = keyWindow
        } else {
            element = NSApplication.shared
        }
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Save failed. \(message)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}


struct StudioShell: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?
    var workspace: EditorWorkspaceDriver

    var body: some View {
        VStack(spacing: 0) {
            StudioTitleBar(
                editorSession: editorSession,
                workspace: workspace
            )
            if let failureMessage = workspace.state.autosaveFailureMessage {
                WorkspaceAutosaveFailureBanner(
                    message: failureMessage,
                    isRetrying: workspace.state.isAutosaveRetryInProgress
                ) {
                    Task {
                        await workspace.retryPendingAutosavesKeepingWindowOpen()
                    }
                }
            }
            detailView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
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
            if editorSession == nil {
                if model.selectedSection == .capture {
                    workspace.send(.sectionSelected(.editor))
                } else {
                    workspace.send(.appSectionSynced(model.selectedSection))
                }
            }
        }
        .onChange(of: model.selectedSection) { _, section in
            if editorSession == nil {
                workspace.send(.appSectionSynced(section))
            }
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
            SettingsStudioView(
                driver: model.appShell.settings,
                serviceHealth: model.serviceHealth,
                paths: model.paths
            )
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

private struct WorkspaceAutosaveFailureBanner: View {
    var message: String
    var isRetrying: Bool
    var retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Changes not saved")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Changes not saved. \(message)")

            Spacer(minLength: 12)

            StudioButton(hitTarget: .rectangle, action: retry) {
                HStack(spacing: 6) {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRetrying ? "Retrying…" : "Retry Save")
                }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.overlayStrong, in: Rectangle())
            }
            .disabled(isRetrying)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.red.opacity(0.28))
                .frame(height: 1)
        }
    }
}

struct StudioNavBar: View {
    var selectedSection: AppSection
    var isScreenshotEditor: Bool
    var onSelectSection: (AppSection) -> Void
    var onToggleHelp: () -> Void

    private let items: [AppSection] = [.editor, .projects]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items) { section in
                StudioNavButton(
                    title: section.title,
                    symbolName: navSymbol(for: section),
                    isActive: selectedSection == section
                ) {
                    onSelectSection(section)
                }
            }

            Rectangle()
                .fill(Theme.borderStrong.opacity(0.40))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 2)

            StudioIconNavButton(title: "Keyboard Shortcuts", symbolName: "questionmark") {
                onToggleHelp()
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 32)
    }

    private func navSymbol(for section: AppSection) -> String {
        switch section {
        case .editor: isScreenshotEditor ? "photo.fill" : "video.fill"
        case .projects: "folder.fill"
        case .capture: "record.circle"
        case .settings: "gearshape.fill"
        }
    }
}

struct StudioNavButton: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: Theme.iconSm, weight: isActive ? .semibold : .medium))
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Theme.accent : (isHovering ? Color.white : Theme.fgMuted))
            .animation(.snappy(duration: 0.16), value: isHovering)
            .animation(.snappy(duration: 0.18), value: isActive)
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct StudioIconNavButton: View {
    var title: String
    var symbolName: String
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isHovering ? Color.white : Theme.fgMuted)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct EditorHistoryButton: View {
    var title: String
    var symbolName: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusSm), help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isEnabled ? Color.primary.opacity(0.86) : Color.secondary.opacity(0.38))
                .background(isEnabled ? Theme.overlayStrong.opacity(0.82) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                        .stroke(isEnabled ? Theme.borderSubtle : Color.clear, lineWidth: 1)
                }
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
        ZStack {
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

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    editorHistoryControls
                    exportButton
                }
            }

            titleLabel
                .frame(maxWidth: 520)
                .padding(.horizontal, 190)
                .allowsHitTesting(false)
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Theme.surface.opacity(0.90))
                LinearGradient(
                    colors: [Color.white.opacity(0.045), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderStrong.opacity(0.56))
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
            HStack(spacing: 2) {
                EditorHistoryButton(title: "Undo", symbolName: "arrow.uturn.backward", isEnabled: canUndo) {
                    workspace.undoActiveEditor(kind: editorMediaKind)
                }
                EditorHistoryButton(title: "Redo", symbolName: "arrow.uturn.forward", isEnabled: canRedo) {
                    workspace.redoActiveEditor(kind: editorMediaKind)
                }
            }
            .padding(3)
            .background(Theme.overlay.opacity(0.88), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if workspace.state.selectedSection == .editor, let videoURL {
            StudioButton(hitTarget: .rounded(Theme.radiusMd)) {
                workspace.send(.videoExportRequested(videoURL, editorSessionID: editorSession?.id))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.video.fill")
                        .font(.system(size: Theme.iconSm, weight: .semibold))
                    Text("Export Video")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .frame(height: Theme.btnHeightMd)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                .foregroundStyle(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
            }
        } else if workspace.state.selectedSection == .editor, screenshotURL != nil {
            StudioButton(hitTarget: .rounded(Theme.radiusMd)) {
                workspace.send(.screenshotExportRequested(screenshotURL, editorSessionID: editorSession?.id))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.system(size: Theme.iconSm, weight: .semibold))
                    Text("Export PNG")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .frame(height: Theme.btnHeightMd)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                .foregroundStyle(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
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
            workspaceStatusIndicator
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var workspaceStatusIndicator: some View {
        Group {
            switch workspace.state.statusSeverity {
            case .none:
                Color.clear
                    .accessibilityHidden(true)
            case .informational:
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Editor status: \(workspace.state.statusMessage)")
                    .help(workspace.state.statusMessage)
            case .progress:
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(workspace.state.statusMessage)
                    .help(workspace.state.statusMessage)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .accessibilityLabel("Editor status: \(workspace.state.statusMessage)")
                    .help(workspace.state.statusMessage)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
                .accessibilityLabel(
                    "Editor error: \(workspace.state.statusMessage). "
                        + (workspace.state.autosaveFailureMessage ?? "")
                )
                .help(workspace.state.autosaveFailureMessage ?? workspace.state.statusMessage)
            }
        }
        .frame(width: 18, height: 18)
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
                editorWindowTitle(
                    displayTitle: editorSession.displayTitle,
                    projectPath: editorSession.projectPath
                )
            } else if let currentVideoURL = model.currentVideoURL {
                editorWindowTitle(
                    displayTitle: EditorMediaKind.video.displayTitle(for: currentVideoURL),
                    projectPath: matchingLastSessionProjectPath(kind: .video, url: currentVideoURL)
                )
            } else if let currentScreenshotURL = model.currentScreenshotURL {
                editorWindowTitle(
                    displayTitle: EditorMediaKind.screenshot.displayTitle(for: currentScreenshotURL),
                    projectPath: matchingLastSessionProjectPath(kind: .screenshot, url: currentScreenshotURL)
                )
            } else {
                "Open Recorder Editor"
            }
        }
    }

    private func matchingLastSessionProjectPath(kind: EditorMediaKind, url: URL) -> String? {
        guard let session = model.lastEditorSession,
              session.kind == kind,
              session.url.standardizedFileURL == url.standardizedFileURL else {
            return nil
        }
        return session.projectPath
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

func editorWindowTitle(displayTitle: String, projectPath: String?) -> String {
    guard projectPath != nil else { return displayTitle }
    return displayTitle.hasSuffix(".openrecorder") ? displayTitle : "\(displayTitle).openrecorder"
}

struct EditorShortcutsHelpDialog: View {
    @Binding var isPresented: Bool

    private let shortcuts: [EditorShortcutHelpItem] = [
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
            HStack(spacing: 12) {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Speed up your workflow with hotkeys.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.fgMuted)
                }

                Spacer(minLength: 0)

                StudioButton(hitTarget: .rounded(Theme.radiusSm), help: "Close") {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Theme.fgMuted)
                        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                                .stroke(Theme.borderSubtle, lineWidth: 1)
                        }
                }
            }

            VStack(spacing: 0) {
                ForEach(shortcuts) { shortcut in
                    HStack(spacing: 14) {
                        Text(shortcut.keys)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Theme.overlayStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Theme.borderStrong.opacity(0.7), lineWidth: 1)
                            }
                            .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)

                        Text(shortcut.action)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.fg)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)

                    if shortcut.id != shortcuts.last?.id {
                        Rectangle()
                            .fill(Theme.borderSubtle.opacity(0.7))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Theme.surface.opacity(0.96))
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
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
