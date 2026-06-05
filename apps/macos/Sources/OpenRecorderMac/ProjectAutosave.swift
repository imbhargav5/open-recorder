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

    func markSaved(_ snapshot: ProjectAutosaveSnapshot?) {
        pendingTask?.cancel()
        pendingTask = nil
        latestSnapshot = snapshot
        lastSavedSnapshot = snapshot
        needsSaveAfterCurrent = false
    }

    func schedule(_ snapshot: ProjectAutosaveSnapshot?) {
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
            await self?.saveLatestSnapshot()
        }
    }

    func flush(_ snapshot: ProjectAutosaveSnapshot? = nil) async {
        if let snapshot {
            latestSnapshot = snapshot
        }
        pendingTask?.cancel()
        pendingTask = nil
        await saveLatestSnapshot()
    }

    private func saveLatestSnapshot() async {
        guard let snapshot = latestSnapshot,
              snapshot != lastSavedSnapshot,
              let saveHandler else {
            return
        }

        if isSaving {
            needsSaveAfterCurrent = true
            return
        }

        isSaving = true
        statusHandler?(.saving)
        do {
            let summary = try await saveHandler(snapshot)
            lastSavedSnapshot = snapshot
            statusHandler?(.saved(summary))
        } catch {
            statusHandler?(.failed(error.localizedDescription))
        }
        isSaving = false

        if needsSaveAfterCurrent {
            needsSaveAfterCurrent = false
            await saveLatestSnapshot()
        }
    }
}
