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
    var backendLoadPhase: LoadPhase = .idle

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
    case pathsChanged(AppPaths?)
    case currentVideoURLChanged(URL?)
    case currentScreenshotURLChanged(URL?)
    case windowCommandRequested(NativeWindowCommandAction, editorSession: EditorSession? = nil)
    case windowCommandConsumed(UUID?)
    case backendRefreshStarted
    case backendRefreshed(paths: AppPaths?, projects: [ProjectSummary], health: HealthPayload?)
    case backendRefreshFailed(String)
    case editorSessionShown(EditorSession)
    case editorMediaOpened(EditorMediaKind, URL)
    case projectSummaryUpserted(ProjectSummary)
    case projectSummaryRemoved(path: String)
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

        case .pathsChanged(let paths):
            guard self.paths != paths else { return [] }
            self.paths = paths
            return []

        case .currentVideoURLChanged(let url):
            guard currentVideoURL != url else { return [] }
            currentVideoURL = url
            return []

        case .currentScreenshotURLChanged(let url):
            guard currentScreenshotURL != url else { return [] }
            currentScreenshotURL = url
            return []

        case .windowCommandRequested(let action, let editorSession):
            let command = NativeWindowCommand(action: action, editorSession: editorSession)
            windowCommand = command
            return [.emitWindowCommand(command)]

        case .windowCommandConsumed(let id):
            guard windowCommand?.id == id else { return [] }
            windowCommand = nil
            return []

        case .backendRefreshStarted:
            guard backendLoadPhase != .loading else { return [] }
            backendLoadPhase = .loading
            statusMessage = "Loading projects…"
            return [.setStatusMessage(statusMessage)]

        case .backendRefreshed(let paths, let projects, let health):
            self.paths = paths
            self.projects = projects
            serviceHealth = health
            backendLoadPhase = .loaded
            statusMessage = "Rust service ready"
            return [.setStatusMessage(statusMessage)]

        case .backendRefreshFailed(let message):
            backendLoadPhase = .failed(message)
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

        case .projectSummaryRemoved(let path):
            projects.removeAll { $0.path == path }
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
    private(set) var state = AppShellState()
    @ObservationIgnored private let workspaces = EditorWorkspaceRegistry()
    let capture = CaptureDriver()
    let captureOptions = CaptureOptionsDriver()
    let inlineSourceSelector = SourceSelectorDriver(sourceTab: .screens)
    let floatingSourceSelector = SourceSelectorDriver(sourceTab: .windows, visibleTabs: [.windows, .area])
    let onboarding = OnboardingDriver(
        screenRecordingPermissionState: .requestAvailable,
        accessibilityPermissionState: .requestAvailable
    )
    let settings = SettingsDriver(createZoomsAutomatically: false)
    @ObservationIgnored private var refreshBackend: () -> Void = {}
    @ObservationIgnored private var emitWindowCommand: (NativeWindowCommand) -> Void = { _ in }
    @ObservationIgnored private var openEditorSession: (EditorSession) -> Void = { _ in }
    @ObservationIgnored private var setStatusMessage: (String) -> Void = { _ in }

    func configure(
        refreshBackend: @escaping () -> Void = {},
        emitWindowCommand: @escaping (NativeWindowCommand) -> Void = { _ in },
        openEditorSession: @escaping (EditorSession) -> Void = { _ in },
        setStatusMessage: @escaping (String) -> Void = { _ in },
        configureWorkspace: @escaping (EditorWorkspaceDriver) -> Void = { _ in }
    ) {
        self.refreshBackend = refreshBackend
        self.emitWindowCommand = emitWindowCommand
        self.openEditorSession = openEditorSession
        self.setStatusMessage = setStatusMessage
        workspaces.configure(configureWorkspace)
    }

    func workspace(for editorSession: EditorSession?) -> EditorWorkspaceDriver {
        workspaces.workspace(for: editorSession)
    }

    func activateWorkspace(for editorSession: EditorSession?) {
        workspaces.activate(sessionID: editorSession?.id)
    }

    func prepareForTermination() async -> Bool {
        await workspaces.prepareForTermination()
    }

    var terminationBlockingEditorSession: EditorSession? {
        workspaces.terminationBlockingSession
    }

    @discardableResult
    func closeWorkspace(for editorSession: EditorSession?) async -> EditorWorkspaceCloseOutcome {
        return await workspaces.close(session: editorSession)
    }

    func beginClosingWorkspace(for editorSession: EditorSession?) -> EditorWorkspaceCloseRequest? {
        return workspaces.beginClose(session: editorSession)
    }

    @discardableResult
    func finishClosingWorkspace(_ request: EditorWorkspaceCloseRequest) async -> EditorWorkspaceCloseOutcome {
        await workspaces.finishClose(request)
    }

    @discardableResult
    func discardWorkspace(for editorSession: EditorSession?) -> Bool {
        workspaces.discard(session: editorSession)
    }

    #if DEBUG
    var sessionWorkspaceCountForTesting: Int {
        workspaces.sessionCountForTesting
    }
    #endif

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
