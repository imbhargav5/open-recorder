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
    private var sessionsByID: [UUID: EditorSession] = [:]
    private var defaultCloseGeneration: UUID?
    private var closeGenerationBySessionID: [UUID: UUID] = [:]
    private var recoverableSessionIDsByKey: [EditorWorkspaceRecoveryKey: [UUID]] = [:]
    private var recoveryKeyBySessionID: [UUID: EditorWorkspaceRecoveryKey] = [:]
    private var configureWorkspace: (EditorWorkspaceDriver) -> Void = { _ in }
    private(set) var terminationBlockingSession: EditorSession?

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
        sessionsByID[sessionID] = session

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

    func prepareForTermination() async -> Bool {
        terminationBlockingSession = nil
        while !Task.isCancelled {
            let workspaces = uniqueWorkspaces

            if workspaces.contains(where: { $0.videoExport.state.phase.isBusy }) {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return false
                }
                continue
            }

            if let workspace = workspaces.first(where: { $0.videoExport.state.pendingTempURL != nil }) {
                terminationBlockingSession = session(for: workspace)
                workspace.send(.statusUpdated(EditorWorkspaceStatus(
                    message: "Save or cancel the finished export before quitting.",
                    severity: .failure
                )))
                return false
            }

            for workspace in workspaces {
                var didFlush = false
                repeat {
                    didFlush = await workspace.flushPendingAutosaves()
                    guard !Task.isCancelled else { return false }
                    guard didFlush else {
                        terminationBlockingSession = session(for: workspace)
                        workspace.send(.autosaveRecoveryRequired)
                        return false
                    }
                } while workspace.hasPendingAutosaves
            }

            // Autosaving one workspace can suspend while another window changes or
            // opens. Re-snapshot at a fixed point and repeat until every current
            // workspace is quiescent in the same main-actor turn.
            await Task.yield()
            let currentWorkspaces = uniqueWorkspaces
            let snapshotIDs = Set(workspaces.map(ObjectIdentifier.init))
            let currentIDs = Set(currentWorkspaces.map(ObjectIdentifier.init))
            if snapshotIDs != currentIDs
                || currentWorkspaces.contains(where: {
                    $0.hasPendingAutosaves
                        || $0.videoExport.state.phase.isBusy
                        || $0.videoExport.state.pendingTempURL != nil
                }) {
                continue
            }
            return true
        }
        return false
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
            guard canCloseWithoutDiscardingExport(request.workspace) else {
                cancelClose(request)
                return .canceled
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
        guard canCloseWithoutDiscardingExport(request.workspace) else {
            cancelClose(request)
            return .canceled
        }
        request.workspace.discardTransientState()
        workspacesBySessionID.removeValue(forKey: sessionID)
        sessionsByID.removeValue(forKey: sessionID)
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
            guard canCloseWithoutDiscardingExport(discardedWorkspace) else { return false }
            guard discardedWorkspace.abandonPendingAutosaves() else { return false }
            discardedWorkspace.discardTransientState()
            defaultCloseGeneration = nil
            let replacement = EditorWorkspaceDriver(synchronizesAppShell: true)
            configureWorkspace(replacement)
            defaultWorkspace = replacement
            return true
        }
        guard let workspace = workspacesBySessionID[session.id] else { return false }
        guard canCloseWithoutDiscardingExport(workspace) else { return false }
        guard workspace.abandonPendingAutosaves() else { return false }
        workspacesBySessionID.removeValue(forKey: session.id)
        sessionsByID.removeValue(forKey: session.id)
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

    private func canCloseWithoutDiscardingExport(_ workspace: EditorWorkspaceDriver) -> Bool {
        let exportState = workspace.videoExport.state
        guard !exportState.phase.isBusy, exportState.pendingTempURL == nil else {
            let message = exportState.phase.isBusy
                ? "Finish or cancel the active export before closing this editor."
                : "Save or cancel the finished export before closing this editor."
            workspace.send(.statusUpdated(EditorWorkspaceStatus(
                message: message,
                severity: .failure
            )))
            return false
        }
        return true
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
            sessionsByID.removeValue(forKey: recoverableSessionID)
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

    private var uniqueWorkspaces: [EditorWorkspaceDriver] {
        var seen: Set<ObjectIdentifier> = []
        return ([defaultWorkspace] + Array(workspacesBySessionID.values)).filter { workspace in
            seen.insert(ObjectIdentifier(workspace)).inserted
        }
    }

    private func session(for workspace: EditorWorkspaceDriver) -> EditorSession? {
        guard let sessionID = workspacesBySessionID.first(where: { $0.value === workspace })?.key else {
            return nil
        }
        return sessionsByID[sessionID]
    }

    #if DEBUG
    var sessionCountForTesting: Int {
        workspacesBySessionID.count
    }
    #endif
}
