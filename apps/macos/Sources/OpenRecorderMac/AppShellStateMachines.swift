import Foundation
import Observation
import SwiftUI

extension HealthPayload: Equatable {}
extension HealthPayload {
    static func == (lhs: HealthPayload, rhs: HealthPayload) -> Bool {
        lhs.service == rhs.service && lhs.version == rhs.version && lhs.platform == rhs.platform
    }
}

extension NativeWindowCommand: Equatable {
    static func == (lhs: NativeWindowCommand, rhs: NativeWindowCommand) -> Bool {
        lhs.id == rhs.id && lhs.action == rhs.action && lhs.editorSession == rhs.editorSession
    }
}

struct AppShellState: Equatable {
    var selectedSection: AppSection = .capture
    var statusMessage = "Ready"
    var windowCommand: NativeWindowCommand?
    var currentVideoURL: URL?
    var currentScreenshotURL: URL?
    var lastEditorSession: EditorSession?
    var projects: [ProjectSummary] = []
    var paths: AppPaths?
    var serviceHealth: HealthPayload?

    var activeEditorKind: EditorMediaKind? {
        if let lastEditorSession {
            return lastEditorSession.kind
        }
        if currentVideoURL != nil {
            return .video
        }
        if currentScreenshotURL != nil {
            return .screenshot
        }
        return nil
    }
}

enum AppShellEvent: Equatable {
    case bootstrapRequested
    case sectionSelected(AppSection)
    case statusChanged(String)
    case windowCommandRequested(NativeWindowCommandAction, editorSession: EditorSession? = nil)
    case windowCommandConsumed(UUID?)
    case backendRefreshed(paths: AppPaths?, projects: [ProjectSummary], health: HealthPayload?)
    case backendRefreshFailed(String)
    case editorSessionShown(EditorSession)
    case editorMediaOpened(EditorMediaKind, URL)
    case projectSummaryUpserted(ProjectSummary)
    case projectsReplaced([ProjectSummary])
}

enum AppShellEffect: Equatable {
    case refreshBackend
    case emitWindowCommand(NativeWindowCommand)
    case openEditorSession(EditorSession)
    case setStatusMessage(String)
}

extension AppShellState {
    mutating func applying(_ event: AppShellEvent) -> [AppShellEffect] {
        switch event {
        case .bootstrapRequested:
            return [.refreshBackend]

        case .sectionSelected(let section):
            guard selectedSection != section else { return [] }
            selectedSection = section
            return []

        case .statusChanged(let message):
            guard statusMessage != message else { return [] }
            statusMessage = message
            return [.setStatusMessage(message)]

        case .windowCommandRequested(let action, let editorSession):
            let command = NativeWindowCommand(action: action, editorSession: editorSession)
            windowCommand = command
            return [.emitWindowCommand(command)]

        case .windowCommandConsumed(let id):
            guard windowCommand?.id == id else { return [] }
            windowCommand = nil
            return []

        case .backendRefreshed(let paths, let projects, let health):
            self.paths = paths
            self.projects = projects
            serviceHealth = health
            statusMessage = "Rust service ready"
            return [.setStatusMessage(statusMessage)]

        case .backendRefreshFailed(let message):
            statusMessage = message
            return [.setStatusMessage(message)]

        case .editorSessionShown(let session):
            lastEditorSession = session
            selectedSection = .editor
            switch session.kind {
            case .video:
                currentVideoURL = session.url
                currentScreenshotURL = nil
            case .screenshot:
                currentScreenshotURL = session.url
                currentVideoURL = nil
            }
            let command = NativeWindowCommand(action: .showStudio, editorSession: session)
            windowCommand = command
            return [.openEditorSession(session), .emitWindowCommand(command)]

        case .editorMediaOpened(let kind, let url):
            selectedSection = .editor
            switch kind {
            case .video:
                currentVideoURL = url
                currentScreenshotURL = nil
            case .screenshot:
                currentScreenshotURL = url
                currentVideoURL = nil
            }
            statusMessage = "Opened \(url.lastPathComponent)"
            return [.setStatusMessage(statusMessage)]

        case .projectSummaryUpserted(let summary):
            projects.removeAll { $0.path == summary.path }
            projects.insert(summary, at: 0)
            return []

        case .projectsReplaced(let projects):
            self.projects = projects
            return []
        }
    }
}

@Observable
@MainActor
final class AppShellDriver {
    var state = AppShellState()

    @ObservationIgnored private var refreshBackend: () -> Void = {}
    @ObservationIgnored private var emitWindowCommand: (NativeWindowCommand) -> Void = { _ in }
    @ObservationIgnored private var openEditorSession: (EditorSession) -> Void = { _ in }
    @ObservationIgnored private var setStatusMessage: (String) -> Void = { _ in }

    func configure(
        refreshBackend: @escaping () -> Void = {},
        emitWindowCommand: @escaping (NativeWindowCommand) -> Void = { _ in },
        openEditorSession: @escaping (EditorSession) -> Void = { _ in },
        setStatusMessage: @escaping (String) -> Void = { _ in }
    ) {
        self.refreshBackend = refreshBackend
        self.emitWindowCommand = emitWindowCommand
        self.openEditorSession = openEditorSession
        self.setStatusMessage = setStatusMessage
    }

    func send(_ event: AppShellEvent) {
        perform(state.applying(event))
    }

    private func perform(_ effects: [AppShellEffect]) {
        for effect in effects {
            switch effect {
            case .refreshBackend:
                refreshBackend()
            case .emitWindowCommand(let command):
                emitWindowCommand(command)
            case .openEditorSession(let session):
                openEditorSession(session)
            case .setStatusMessage(let message):
                setStatusMessage(message)
            }
        }
    }
}
