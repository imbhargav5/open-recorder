import Foundation

struct ProjectAutosaveSnapshot: Equatable {
    var projectPath: String
    var title: String
    var recordingPath: String?
    var screenshotPath: String?
    var sourceName: String?
    var editorState: ProjectEditorState
    var recordingSession: RecordingSession?
}

enum ProjectAutosaveStatus: Equatable {
    case saving
    case saved(ProjectSummary)
    case failed(String)
}

struct ProjectUpdateRequest: Encodable {
    var path: String
    var title: String
    var recordingPath: String?
    var screenshotPath: String?
    var sourceName: String?
    var editorState: ProjectEditorState
    var recordingSession: RecordingSession?

    init(snapshot: ProjectAutosaveSnapshot) {
        path = snapshot.projectPath
        title = snapshot.title
        recordingPath = snapshot.recordingPath
        screenshotPath = snapshot.screenshotPath
        sourceName = snapshot.sourceName
        editorState = snapshot.editorState
        recordingSession = snapshot.recordingSession
    }
}

@MainActor
final class ProjectAutosaveCoordinator: ObservableObject {
    typealias SaveHandler = (ProjectAutosaveSnapshot) async throws -> ProjectSummary
    typealias StatusHandler = (ProjectAutosaveStatus) -> Void

    private let debounceNanoseconds: UInt64
    private var saveHandler: SaveHandler?
    private var statusHandler: StatusHandler?
    private var pendingTask: Task<Void, Never>?
    private var latestSnapshot: ProjectAutosaveSnapshot?
    private var lastSavedSnapshot: ProjectAutosaveSnapshot?
    private var isSaving = false
    private var needsSaveAfterCurrent = false
    private var isAbandoned = false
    private var saveCompletionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        debounceNanoseconds: UInt64 = 800_000_000,
        saveHandler: SaveHandler? = nil,
        statusHandler: StatusHandler? = nil
    ) {
        self.debounceNanoseconds = debounceNanoseconds
        self.saveHandler = saveHandler
        self.statusHandler = statusHandler
    }

    deinit {
        pendingTask?.cancel()
    }

    func configure(saveHandler: @escaping SaveHandler, statusHandler: @escaping StatusHandler) {
        self.saveHandler = saveHandler
        self.statusHandler = statusHandler
    }

    var canAbandonPendingChanges: Bool {
        !isSaving
    }

    var hasPendingChanges: Bool {
        guard !isAbandoned else { return false }
        return isSaving || needsSaveAfterCurrent || latestSnapshot != lastSavedSnapshot
    }

    func markSaved(_ snapshot: ProjectAutosaveSnapshot?) {
        guard !isAbandoned else { return }
        pendingTask?.cancel()
        pendingTask = nil
        latestSnapshot = snapshot
        lastSavedSnapshot = snapshot
        needsSaveAfterCurrent = false
    }

    @discardableResult
    func abandonPendingChanges() -> Bool {
        guard !isSaving else { return false }
        isAbandoned = true
        pendingTask?.cancel()
        pendingTask = nil
        latestSnapshot = nil
        lastSavedSnapshot = nil
        needsSaveAfterCurrent = false
        return true
    }

    func schedule(_ snapshot: ProjectAutosaveSnapshot?) {
        guard !isAbandoned else { return }
        guard let snapshot else { return }
        latestSnapshot = snapshot

        guard snapshot != lastSavedSnapshot else {
            pendingTask?.cancel()
            pendingTask = nil
            return
        }

        if isSaving {
            needsSaveAfterCurrent = true
            return
        }

        pendingTask?.cancel()
        let debounceNanoseconds = debounceNanoseconds
        pendingTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.runPendingSave()
        }
    }

    @discardableResult
    func flush(_ snapshot: ProjectAutosaveSnapshot? = nil) async -> Bool {
        guard !isAbandoned else { return true }
        if let snapshot {
            latestSnapshot = snapshot
        }
        pendingTask?.cancel()
        pendingTask = nil
        if isSaving {
            needsSaveAfterCurrent = true
            await withCheckedContinuation { continuation in
                saveCompletionWaiters.append(continuation)
            }
            return latestSnapshot == lastSavedSnapshot
        }
        await saveLatestSnapshot()
        return latestSnapshot == lastSavedSnapshot
    }

    private func runPendingSave() async {
        pendingTask = nil
        await saveLatestSnapshot()
    }

    private func saveLatestSnapshot() async {
        guard !isAbandoned else { return }
        if isSaving {
            needsSaveAfterCurrent = true
            return
        }

        guard saveHandler != nil else { return }
        isSaving = true
        repeat {
            needsSaveAfterCurrent = false
            guard let snapshot = latestSnapshot,
                  snapshot != lastSavedSnapshot,
                  let saveHandler else {
                break
            }

            statusHandler?(.saving)
            do {
                let summary = try await saveHandler(snapshot)
                lastSavedSnapshot = snapshot
                statusHandler?(.saved(summary))
            } catch {
                statusHandler?(.failed(error.localizedDescription))
            }
        } while needsSaveAfterCurrent
        isSaving = false

        let waiters = saveCompletionWaiters
        saveCompletionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
