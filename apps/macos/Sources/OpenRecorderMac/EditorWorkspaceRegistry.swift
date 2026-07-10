import Foundation

struct EditorWorkspaceRecoveryKey: Hashable {
    let kind: EditorMediaKind
    let path: String

    init(session: EditorSession) {
        kind = session.kind
        let durablePath = session.projectPath ?? session.path
        path = URL(fileURLWithPath: durablePath).standardizedFileURL.path
    }
}

struct EditorWorkspaceCloseRequest {
    let sessionID: UUID?
    let generation: UUID
    let workspace: EditorWorkspaceDriver
    let recoveryKey: EditorWorkspaceRecoveryKey?
}

enum EditorWorkspaceCloseOutcome: Equatable {
    case closed
    case canceled
    case autosaveFailed
}

@MainActor
final class EditorWorkspaceRegistry {
    private(set) var defaultWorkspace = EditorWorkspaceDriver(synchronizesAppShell: true)

    private var workspacesBySessionID: [UUID: EditorWorkspaceDriver] = [:]
    private var defaultCloseGeneration: UUID?
    private var closeGenerationBySessionID: [UUID: UUID] = [:]
    private var recoverableSessionIDsByKey: [EditorWorkspaceRecoveryKey: [UUID]] = [:]
    private var recoveryKeyBySessionID: [UUID: EditorWorkspaceRecoveryKey] = [:]
    private var configureWorkspace: (EditorWorkspaceDriver) -> Void = { _ in }

    func configure(_ configureWorkspace: @escaping (EditorWorkspaceDriver) -> Void) {
        self.configureWorkspace = configureWorkspace
        configureWorkspace(defaultWorkspace)
        workspacesBySessionID.values.forEach(configureWorkspace)
    }

    func workspace(for session: EditorSession?) -> EditorWorkspaceDriver {
        guard let session else {
            return defaultWorkspace
        }
        let sessionID = session.id

        if let workspace = workspacesBySessionID[sessionID] {
            return workspace
        }

        let recoveryKey = EditorWorkspaceRecoveryKey(session: session)
        if let workspace = recoverWorkspace(for: recoveryKey, newSessionID: sessionID) {
            return workspace
        }

        let workspace = EditorWorkspaceDriver(synchronizesAppShell: false)
        configureWorkspace(workspace)
        workspacesBySessionID[sessionID] = workspace
        return workspace
    }

    func activate(sessionID: UUID?) {
        guard let sessionID else {
            defaultCloseGeneration = nil
            return
        }
        closeGenerationBySessionID.removeValue(forKey: sessionID)
        removeRecoveryRecord(for: sessionID)
    }

    func beginClose(session: EditorSession?) -> EditorWorkspaceCloseRequest? {
        let closeGeneration = UUID()
        guard let session else {
            defaultCloseGeneration = closeGeneration
            return EditorWorkspaceCloseRequest(
                sessionID: nil,
                generation: closeGeneration,
                workspace: defaultWorkspace,
                recoveryKey: nil
            )
        }
        let sessionID = session.id
        guard let workspace = workspacesBySessionID[sessionID] else { return nil }
        closeGenerationBySessionID[sessionID] = closeGeneration
        return EditorWorkspaceCloseRequest(
            sessionID: sessionID,
            generation: closeGeneration,
            workspace: workspace,
            recoveryKey: EditorWorkspaceRecoveryKey(session: session)
        )
    }

    @discardableResult
    func finishClose(_ request: EditorWorkspaceCloseRequest) async -> EditorWorkspaceCloseOutcome {
        var didFlushAutosaves = false
        repeat {
            didFlushAutosaves = await request.workspace.flushPendingAutosaves()
            guard !Task.isCancelled else {
                cancelClose(request)
                return .canceled
            }
            guard didFlushAutosaves else { break }
        } while request.workspace.hasPendingAutosaves

        guard let sessionID = request.sessionID else {
            guard defaultCloseGeneration == request.generation,
                  request.workspace === defaultWorkspace else {
                return .canceled
            }
            defaultCloseGeneration = nil
            guard didFlushAutosaves else {
                request.workspace.send(.autosaveRecoveryRequired)
                return .autosaveFailed
            }
            request.workspace.discardTransientState()
            if request.workspace.state.isAutosaveRecoveryPresented {
                request.workspace.send(.autosaveRecoveryResolved("Saved"))
            }
            return .closed
        }

        guard closeGenerationBySessionID[sessionID] == request.generation,
              workspacesBySessionID[sessionID] === request.workspace else {
            return .canceled
        }
        guard didFlushAutosaves else {
            closeGenerationBySessionID.removeValue(forKey: sessionID)
            markRecoverable(request)
            request.workspace.send(.autosaveRecoveryRequired)
            return .autosaveFailed
        }
        request.workspace.discardTransientState()
        workspacesBySessionID.removeValue(forKey: sessionID)
        closeGenerationBySessionID.removeValue(forKey: sessionID)
        removeRecoveryRecord(for: sessionID)
        return .closed
    }

    @discardableResult
    func close(session: EditorSession?) async -> EditorWorkspaceCloseOutcome {
        guard let request = beginClose(session: session) else { return .canceled }
        return await finishClose(request)
    }

    @discardableResult
    func discard(session: EditorSession?) -> Bool {
        guard let session else {
            let discardedWorkspace = defaultWorkspace
            guard discardedWorkspace.abandonPendingAutosaves() else { return false }
            discardedWorkspace.discardTransientState()
            defaultCloseGeneration = nil
            let replacement = EditorWorkspaceDriver(synchronizesAppShell: true)
            configureWorkspace(replacement)
            defaultWorkspace = replacement
            return true
        }
        guard let workspace = workspacesBySessionID[session.id] else { return false }
        guard workspace.abandonPendingAutosaves() else { return false }
        workspacesBySessionID.removeValue(forKey: session.id)
        workspace.discardTransientState()
        closeGenerationBySessionID.removeValue(forKey: session.id)
        removeRecoveryRecord(for: session.id)
        return true
    }

    private func markRecoverable(_ request: EditorWorkspaceCloseRequest) {
        guard let sessionID = request.sessionID,
              let recoveryKey = request.recoveryKey else {
            return
        }
        recoveryKeyBySessionID[sessionID] = recoveryKey
        var sessionIDs = recoverableSessionIDsByKey[recoveryKey, default: []]
        if !sessionIDs.contains(sessionID) {
            sessionIDs.append(sessionID)
        }
        recoverableSessionIDsByKey[recoveryKey] = sessionIDs
    }

    private func cancelClose(_ request: EditorWorkspaceCloseRequest) {
        guard let sessionID = request.sessionID else {
            if defaultCloseGeneration == request.generation {
                defaultCloseGeneration = nil
            }
            return
        }
        if closeGenerationBySessionID[sessionID] == request.generation {
            closeGenerationBySessionID.removeValue(forKey: sessionID)
        }
    }

    private func recoverWorkspace(
        for recoveryKey: EditorWorkspaceRecoveryKey,
        newSessionID: UUID
    ) -> EditorWorkspaceDriver? {
        guard var sessionIDs = recoverableSessionIDsByKey[recoveryKey] else { return nil }
        while let recoverableSessionID = sessionIDs.popLast() {
            guard let workspace = workspacesBySessionID.removeValue(forKey: recoverableSessionID) else {
                recoveryKeyBySessionID.removeValue(forKey: recoverableSessionID)
                continue
            }
            closeGenerationBySessionID.removeValue(forKey: recoverableSessionID)
            recoveryKeyBySessionID.removeValue(forKey: recoverableSessionID)
            recoverableSessionIDsByKey[recoveryKey] = sessionIDs.isEmpty ? nil : sessionIDs
            workspacesBySessionID[newSessionID] = workspace
            return workspace
        }
        recoverableSessionIDsByKey.removeValue(forKey: recoveryKey)
        return nil
    }

    private func removeRecoveryRecord(for sessionID: UUID) {
        guard let recoveryKey = recoveryKeyBySessionID.removeValue(forKey: sessionID),
              var sessionIDs = recoverableSessionIDsByKey[recoveryKey] else {
            return
        }
        sessionIDs.removeAll { $0 == sessionID }
        recoverableSessionIDsByKey[recoveryKey] = sessionIDs.isEmpty ? nil : sessionIDs
    }

    #if DEBUG
    var sessionCountForTesting: Int {
        workspacesBySessionID.count
    }
    #endif
}
