import CoreGraphics
import XCTest
@testable import OpenRecorderMac

@MainActor
final class AppShellStateMachineTests: XCTestCase {
    func testHealthPayloadDecodesServiceResponseFields() throws {
        let json: String = """
        {
          "service": "open-recorder",
          "version": "1.2.3",
          "platform": "macOS"
        }
        """

        let health = try JSONDecoder().decode(HealthPayload.self, from: Data(json.utf8))

        XCTAssertEqual(health, HealthPayload(service: "open-recorder", version: "1.2.3", platform: "macOS"))
    }

    func testShellRoutesEditorSessionAndWindowCommand() throws {
        var state = AppShellState()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/demo.mp4"), title: "Demo")

        let effects = state.applying(.editorSessionShown(session))

        XCTAssertEqual(state.selectedSection, .editor)
        XCTAssertEqual(state.currentVideoURL, session.url)
        XCTAssertNil(state.currentScreenshotURL)
        XCTAssertEqual(state.lastEditorSession, session)
        XCTAssertEqual(state.windowCommand?.action, .showStudio)
        XCTAssertEqual(state.windowCommand?.editorSession, session)
        let windowCommand = try XCTUnwrap(state.windowCommand)
        XCTAssertEqual(effects, [.openEditorSession(session), .emitWindowCommand(windowCommand)])
    }

    func testShellConsumesWindowCommandOnce() {
        var state = AppShellState()

        let effects = state.applying(.windowCommandRequested(.showHUD))
        let command = state.windowCommand
        XCTAssertEqual(effects, command.map { [.emitWindowCommand($0)] } ?? [])

        XCTAssertEqual(state.applying(.windowCommandConsumed(command?.id)), [])
        XCTAssertNil(state.windowCommand)
        XCTAssertEqual(state.applying(.windowCommandConsumed(command?.id)), [])
    }

    func testShellBackendRefreshOwnsServiceStateAndStatus() {
        var state = AppShellState()
        let paths = AppPaths(recordingsDir: "/r", screenshotsDir: "/s", projectsDir: "/p", supportDir: "/support")
        let project = makeProjectSummary(path: "/p/demo.openrecorder")
        let health = HealthPayload(service: "open-recorder", version: "1.0", platform: "macOS")

        let effects = state.applying(.backendRefreshed(paths: paths, projects: [project], health: health))

        XCTAssertEqual(state.paths, paths)
        XCTAssertEqual(state.projects, [project])
        XCTAssertEqual(state.serviceHealth, health)
        XCTAssertEqual(state.backendLoadPhase, .loaded)
        XCTAssertEqual(state.statusMessage, "Rust service ready")
        XCTAssertEqual(effects, [.setStatusMessage("Rust service ready")])
    }

    func testShellBackendRefreshPublishesLoadingBeforeResultsArrive() {
        var state = AppShellState()

        let effects = state.applying(.backendRefreshStarted)

        XCTAssertEqual(state.backendLoadPhase, .loading)
        XCTAssertEqual(state.statusMessage, "Loading projects…")
        XCTAssertEqual(effects, [.setStatusMessage("Loading projects…")])
        XCTAssertEqual(state.applying(.backendRefreshStarted), [])
    }

    func testShellBackendFailurePreservesLastUsableData() {
        let paths = AppPaths(recordingsDir: "/r", screenshotsDir: "/s", projectsDir: "/p", supportDir: "/support")
        let project = makeProjectSummary(path: "/p/demo.openrecorder")
        let health = HealthPayload(service: "open-recorder", version: "1.0", platform: "macOS")
        var state = AppShellState(
            projects: [project],
            paths: paths,
            serviceHealth: health,
            backendLoadPhase: .loaded
        )

        _ = state.applying(.backendRefreshStarted)
        let effects = state.applying(.backendRefreshFailed("Service unavailable"))

        XCTAssertEqual(state.projects, [project])
        XCTAssertEqual(state.paths, paths)
        XCTAssertEqual(state.serviceHealth, health)
        XCTAssertEqual(state.backendLoadPhase, .failed("Service unavailable"))
        XCTAssertEqual(effects, [.setStatusMessage("Service unavailable")])
    }

    func testShellRemovesProjectSummaryByPath() {
        var state = AppShellState()
        let first = makeProjectSummary(path: "/p/first.openrecorder")
        let second = makeProjectSummary(path: "/p/second.openrecorder")
        state.projects = [first, second]

        let effects = state.applying(.projectSummaryRemoved(path: first.path))

        XCTAssertEqual(effects, [])
        XCTAssertEqual(state.projects, [second])
    }

    func testShellDriverOwnsLongLivedChildDrivers() {
        let shell = AppShellDriver()
        let workspace = shell.workspace(for: nil)
        let capture = shell.capture
        let captureOptions = shell.captureOptions
        let inlineSourceSelector = shell.inlineSourceSelector
        let floatingSourceSelector = shell.floatingSourceSelector
        let onboarding = shell.onboarding
        let settings = shell.settings
        let videoExport = workspace.videoExport

        XCTAssertTrue(shell.workspace(for: nil) === workspace)
        XCTAssertTrue(shell.capture === capture)
        XCTAssertTrue(shell.captureOptions === captureOptions)
        XCTAssertTrue(shell.inlineSourceSelector === inlineSourceSelector)
        XCTAssertTrue(shell.floatingSourceSelector === floatingSourceSelector)
        XCTAssertTrue(shell.onboarding === onboarding)
        XCTAssertTrue(shell.settings === settings)
        XCTAssertTrue(shell.workspace(for: nil).videoExport === videoExport)
    }

    func testShellDriverKeepsEditorWindowWorkspacesIndependentBySession() {
        let shell = AppShellDriver()
        let firstSession = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/first.png"))
        let secondSession = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/second.png"))

        let firstWorkspace = shell.workspace(for: firstSession)
        let secondWorkspace = shell.workspace(for: secondSession)

        XCTAssertTrue(shell.workspace(for: nil) === shell.workspace(for: nil))
        XCTAssertTrue(shell.workspace(for: firstSession) === firstWorkspace)
        XCTAssertFalse(firstWorkspace === secondWorkspace)

        firstWorkspace.screenshot.update(\.padding, to: 96)
        secondWorkspace.screenshot.update(\.padding, to: 18)

        XCTAssertEqual(firstWorkspace.screenshot.state.screenshot.padding, 96)
        XCTAssertEqual(secondWorkspace.screenshot.state.screenshot.padding, 18)
        XCTAssertFalse(firstWorkspace.videoExport === secondWorkspace.videoExport)
    }

    func testSessionWorkspaceNavigationDoesNotMutateGlobalSection() {
        let shell = AppShellDriver()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/session.mp4"))
        let workspace = shell.workspace(for: session)
        var forwardedSections: [AppSection] = []
        workspace.configure(
            setAppSection: { forwardedSections.append($0) },
            setStatusMessage: { _ in }
        )

        workspace.send(.sectionSelected(.projects))

        XCTAssertEqual(workspace.state.selectedSection, .projects)
        XCTAssertTrue(forwardedSections.isEmpty)
        XCTAssertEqual(shell.state.selectedSection, .capture)
    }

    func testDefaultWorkspaceMayForwardNavigationToAppShell() {
        let shell = AppShellDriver()
        var forwardedSections: [AppSection] = []
        let workspace = shell.workspace(for: nil)
        workspace.configure(
            setAppSection: { forwardedSections.append($0) },
            setStatusMessage: { _ in }
        )

        workspace.send(.sectionSelected(.projects))

        XCTAssertEqual(forwardedSections, [.projects])
    }

    func testClosingSessionEvictsItsWorkspace() async {
        let shell = AppShellDriver()
        let session = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/close.png"))
        let originalWorkspace = shell.workspace(for: session)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 1)

        await shell.closeWorkspace(for: session)

        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 0)
        XCTAssertFalse(shell.workspace(for: session) === originalWorkspace)
    }

    func testClosingSessionFlushesBothEditorAutosavesBeforeEviction() async {
        let shell = AppShellDriver()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/autosave.mp4"))
        let workspace = shell.workspace(for: session)
        let videoSnapshot = makeWorkspaceAutosaveSnapshot(path: "/tmp/video.openrecorder", kind: .video)
        let screenshotSnapshot = makeWorkspaceAutosaveSnapshot(path: "/tmp/screenshot.openrecorder", kind: .screenshot)
        var savedSnapshots: [ProjectAutosaveSnapshot] = []

        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                savedSnapshots.append(snapshot)
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.screenshot.configure(
            saveHandler: { snapshot in
                savedSnapshots.append(snapshot)
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            setWorkspaceStatus: { _ in }
        )
        workspace.video.send(.autosaveSnapshotChanged(videoSnapshot))
        workspace.screenshot.send(.autosaveSnapshotChanged(screenshotSnapshot))

        await shell.closeWorkspace(for: session)

        XCTAssertEqual(savedSnapshots, [videoSnapshot, screenshotSnapshot])
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 0)
    }

    func testPreparingForTerminationFlushesAutosavesWithoutEvictingOpenWorkspace() async {
        let shell = AppShellDriver()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/quit-save.mp4"))
        let workspace = shell.workspace(for: session)
        let snapshot = makeWorkspaceAutosaveSnapshot(path: "/tmp/quit-save.openrecorder", kind: .video)
        var savedSnapshots: [ProjectAutosaveSnapshot] = []
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                savedSnapshots.append(snapshot)
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(snapshot))

        let canTerminate = await shell.prepareForTermination()

        XCTAssertTrue(canTerminate)
        XCTAssertEqual(savedSnapshots, [snapshot])
        XCTAssertTrue(shell.workspace(for: session) === workspace)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 1)
    }

    func testPreparingForTerminationRechecksEarlierAndNewWorkspacesAtAFixedPoint() async {
        let shell = AppShellDriver()
        let firstWorkspace = shell.workspace(for: nil)
        let secondSession = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/quit-second.mp4"))
        let secondWorkspace = shell.workspace(for: secondSession)
        let secondSaveGate = WorkspaceAutosaveGate()
        let secondSaveStarted = expectation(description: "Second workspace save started")
        var savedPaths: [String] = []

        firstWorkspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                savedPaths.append(snapshot.projectPath)
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        secondWorkspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                secondSaveStarted.fulfill()
                await secondSaveGate.wait()
                savedPaths.append(snapshot.projectPath)
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        firstWorkspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: "/tmp/quit-first-1.openrecorder", kind: .video)
        ))
        secondWorkspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: "/tmp/quit-second.openrecorder", kind: .video)
        ))

        let termination = Task { @MainActor in await shell.prepareForTermination() }
        await fulfillment(of: [secondSaveStarted], timeout: 1)

        firstWorkspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: "/tmp/quit-first-2.openrecorder", kind: .video)
        ))
        let thirdSession = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/quit-third.png"))
        let thirdWorkspace = shell.workspace(for: thirdSession)
        thirdWorkspace.screenshot.configure(
            saveHandler: { snapshot in
                savedPaths.append(snapshot.projectPath)
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            setWorkspaceStatus: { _ in }
        )
        thirdWorkspace.screenshot.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: "/tmp/quit-third.openrecorder", kind: .screenshot)
        ))
        await secondSaveGate.open()

        let canTerminate = await termination.value
        XCTAssertTrue(canTerminate)
        XCTAssertEqual(Set(savedPaths), Set([
            "/tmp/quit-first-1.openrecorder",
            "/tmp/quit-first-2.openrecorder",
            "/tmp/quit-second.openrecorder",
            "/tmp/quit-third.openrecorder"
        ]))
    }

    func testPreparingForTerminationCancelsQuitAndPresentsRecoveryWhenAutosaveFails() async {
        let shell = AppShellDriver()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/quit-failure.mp4"))
        let workspace = shell.workspace(for: session)
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { _ in throw WorkspaceAutosaveError.failed },
            statusHandler: { [weak workspace] status in
                workspace?.handleProjectAutosaveStatus(status, source: .video)
            },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: "/tmp/quit-failure.openrecorder", kind: .video)
        ))

        let canTerminate = await shell.prepareForTermination()

        XCTAssertFalse(canTerminate)
        XCTAssertTrue(workspace.state.isAutosaveRecoveryPresented)
        XCTAssertEqual(workspace.state.statusSeverity, .failure)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 1)
    }

    func testReopeningSessionDuringCloseReusesWorkspaceAndCancelsEviction() async {
        let shell = AppShellDriver()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/reopen.mp4"))
        let workspace = shell.workspace(for: session)
        let snapshot = makeWorkspaceAutosaveSnapshot(path: "/tmp/reopen.openrecorder", kind: .video)
        let gate = WorkspaceAutosaveGate()
        let saveStarted = expectation(description: "Workspace save started")

        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                saveStarted.fulfill()
                await gate.wait()
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(snapshot))
        let initialFlush = Task { @MainActor in
            await workspace.video.flushPendingAutosave()
        }
        await fulfillment(of: [saveStarted], timeout: 1)

        guard let closeRequest = shell.beginClosingWorkspace(for: session) else {
            return XCTFail("Expected a close request")
        }
        let close = Task { @MainActor in
            await shell.finishClosingWorkspace(closeRequest)
        }

        shell.activateWorkspace(for: session)
        let reopenedWorkspace = shell.workspace(for: session)
        await gate.open()
        _ = await initialFlush.value
        _ = await close.value

        XCTAssertTrue(reopenedWorkspace === workspace)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 1)

        await shell.closeWorkspace(for: session)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 0)
    }

    func testActivationCancelsCloseBeforeAsyncCleanupStarts() async {
        let shell = AppShellDriver()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/delayed-close.mp4"))
        let workspace = shell.workspace(for: session)
        guard let closeRequest = shell.beginClosingWorkspace(for: session) else {
            return XCTFail("Expected a close request")
        }

        shell.activateWorkspace(for: session)
        let reopenedWorkspace = shell.workspace(for: session)
        await shell.finishClosingWorkspace(closeRequest)

        XCTAssertTrue(reopenedWorkspace === workspace)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 1)

        await shell.closeWorkspace(for: session)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 0)
    }

    func testFailedAutosaveRetainsSessionWorkspaceAndExportForRecovery() async {
        let shell = AppShellDriver()
        let projectPath = "/tmp/failed-save.openrecorder"
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/failed-save.mp4"),
            projectPath: projectPath
        )
        let workspace = shell.workspace(for: session)
        let snapshot = makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        var statuses: [ProjectAutosaveStatus] = []
        let exportStarted = expectation(description: "Export started")
        let exportCanceled = expectation(description: "Export is canceled explicitly")
        let temporaryURL = URL(fileURLWithPath: "/tmp/failed-save-export.mov")
        var cancellationToken: VideoExportCancellationToken?
        var deletedURLs: [URL] = []
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { _ in throw WorkspaceAutosaveError.failed },
            statusHandler: { statuses.append($0) },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.videoExport.configure(
            renderVideo: { _, _, _, token, _, _ in
                cancellationToken = token
                exportStarted.fulfill()
                while !token.isCancelled && !Task.isCancelled {
                    await Task.yield()
                }
                exportCanceled.fulfill()
                throw CancellationError()
            },
            temporaryURL: { _ in temporaryURL },
            saveDestination: { _, _ -> URL? in nil },
            copyFile: { _, _ in },
            deleteFile: { deletedURLs.append($0) },
            revealFile: { _ in },
            setStatusMessage: { _ in }
        )
        workspace.video.send(.autosaveSnapshotChanged(snapshot))
        workspace.videoExport.export(sourceURL: session.url, options: .default, edits: .empty)
        await fulfillment(of: [exportStarted], timeout: 1)

        let closeOutcome = await shell.closeWorkspace(for: session)

        let reopenedSession = EditorSession(
            kind: .video,
            url: session.url,
            projectPath: projectPath
        )
        XCTAssertNotEqual(reopenedSession.id, session.id)
        XCTAssertEqual(closeOutcome, .autosaveFailed)
        XCTAssertTrue(shell.workspace(for: reopenedSession) === workspace)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 1)
        XCTAssertTrue(workspace.state.isAutosaveRecoveryPresented)
        XCTAssertEqual(statuses.last, .failed("Save failed"))
        XCTAssertFalse(cancellationToken?.isCancelled == true)
        XCTAssertEqual(workspace.videoExport.state.phase, .exporting)
        XCTAssertEqual(deletedURLs, [])

        workspace.videoExport.cancelExport()
        await fulfillment(of: [exportCanceled], timeout: 1)

        XCTAssertTrue(cancellationToken?.isCancelled == true)
        XCTAssertEqual(workspace.videoExport.state.phase, .failed)
        XCTAssertEqual(deletedURLs, [temporaryURL])
    }

    func testMixedAutosaveOutcomePreservesTheFirstFailureReason() async {
        let shell = AppShellDriver()
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/mixed-save.mp4"),
            projectPath: "/tmp/mixed-save.openrecorder"
        )
        let workspace = shell.workspace(for: session)
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { _ in throw WorkspaceAutosaveError.failed },
            statusHandler: { [weak workspace] status in
                workspace?.handleProjectAutosaveStatus(status)
            },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.screenshot.configure(
            saveHandler: { snapshot in
                makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { [weak workspace] status in
                workspace?.handleProjectAutosaveStatus(status)
            },
            setWorkspaceStatus: { _ in }
        )
        workspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: session.projectPath!, kind: .video)
        ))
        workspace.screenshot.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: session.projectPath!, kind: .screenshot)
        ))

        let outcome = await shell.closeWorkspace(for: session)

        XCTAssertEqual(outcome, .autosaveFailed)
        XCTAssertEqual(workspace.state.statusSeverity, .failure)
        XCTAssertEqual(workspace.state.autosaveFailureMessage, "Save failed")
    }

    func testCloseFlushesEditsCreatedWhileAnotherEditorAutosaveIsInFlight() async {
        let shell = AppShellDriver()
        let projectPath = "/tmp/quiescent-close.openrecorder"
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/quiescent-close.mp4"),
            projectPath: projectPath
        )
        let workspace = shell.workspace(for: session)
        let screenshotGate = WorkspaceAutosaveGate()
        let screenshotSaveStarted = expectation(description: "Screenshot save started")
        var savedVideoTitles: [String] = []
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                savedVideoTitles.append(snapshot.title)
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { [weak workspace] status in
                workspace?.handleProjectAutosaveStatus(status)
            },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.screenshot.configure(
            saveHandler: { snapshot in
                screenshotSaveStarted.fulfill()
                await screenshotGate.wait()
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { [weak workspace] status in
                workspace?.handleProjectAutosaveStatus(status)
            },
            setWorkspaceStatus: { _ in }
        )
        var initialVideo = makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        initialVideo.title = "Initial video"
        workspace.video.send(.autosaveSnapshotChanged(initialVideo))
        workspace.screenshot.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .screenshot)
        ))

        let close = Task { @MainActor in
            await shell.closeWorkspace(for: session)
        }
        await fulfillment(of: [screenshotSaveStarted], timeout: 1)
        var updatedVideo = initialVideo
        updatedVideo.title = "Updated during close"
        workspace.video.send(.autosaveSnapshotChanged(updatedVideo))
        await screenshotGate.open()

        let closeOutcome = await close.value
        XCTAssertEqual(closeOutcome, .closed)
        XCTAssertEqual(savedVideoTitles, ["Initial video", "Updated during close"])
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 0)
    }

    func testCloseJoinerStartsFreshFlushForEditAddedBeforeCoalescedFlushCompletes() async {
        let shell = AppShellDriver()
        let projectPath = "/tmp/coalesced-close.openrecorder"
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/coalesced-close.mp4"),
            projectPath: projectPath
        )
        let workspace = shell.workspace(for: session)
        let screenshotGate = WorkspaceAutosaveGate()
        let screenshotSaveStarted = expectation(description: "Coalesced screenshot save started")
        var savedVideoTitles: [String] = []
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                savedVideoTitles.append(snapshot.title)
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.screenshot.configure(
            saveHandler: { snapshot in
                screenshotSaveStarted.fulfill()
                await screenshotGate.wait()
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            setWorkspaceStatus: { _ in }
        )
        var initialVideo = makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        initialVideo.title = "Initial coalesced video"
        workspace.video.send(.autosaveSnapshotChanged(initialVideo))
        workspace.screenshot.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .screenshot)
        ))

        let originalFlush = Task { @MainActor in
            await workspace.flushPendingAutosaves()
        }
        await fulfillment(of: [screenshotSaveStarted], timeout: 1)
        let close = Task { @MainActor in
            await shell.closeWorkspace(for: session)
        }
        await Task.yield()
        var lateVideo = initialVideo
        lateVideo.title = "Late coalesced video"
        workspace.video.send(.autosaveSnapshotChanged(lateVideo))
        await screenshotGate.open()

        let originalFlushOutcome = await originalFlush.value
        let closeOutcome = await close.value
        XCTAssertTrue(originalFlushOutcome)
        XCTAssertEqual(closeOutcome, .closed)
        XCTAssertEqual(savedVideoTitles, ["Initial coalesced video", "Late coalesced video"])
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 0)
    }

    func testCancelingCloseDuringAutosaveDoesNotEvictWorkspace() async {
        let shell = AppShellDriver()
        let projectPath = "/tmp/canceled-close.openrecorder"
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/canceled-close.mp4"),
            projectPath: projectPath
        )
        let workspace = shell.workspace(for: session)
        let gate = WorkspaceAutosaveGate()
        let saveStarted = expectation(description: "Save started")
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                saveStarted.fulfill()
                await gate.wait()
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        ))
        guard let request = shell.beginClosingWorkspace(for: session) else {
            return XCTFail("Expected a close request")
        }
        let close = Task { @MainActor in
            await shell.finishClosingWorkspace(request)
        }
        await fulfillment(of: [saveStarted], timeout: 1)

        close.cancel()
        await gate.open()

        let canceledOutcome = await close.value
        XCTAssertEqual(canceledOutcome, .canceled)
        XCTAssertTrue(shell.workspace(for: session) === workspace)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 1)
        let finalCloseOutcome = await shell.closeWorkspace(for: session)
        XCTAssertEqual(finalCloseOutcome, .closed)
    }

    func testRetryingRecoveredAutosaveAllowsCleanClose() async {
        let shell = AppShellDriver()
        let projectPath = "/tmp/retry-save.openrecorder"
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/retry-save.mp4"),
            projectPath: projectPath
        )
        let workspace = shell.workspace(for: session)
        var shouldFail = true
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                if shouldFail { throw WorkspaceAutosaveError.failed }
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        ))

        let failedCloseOutcome = await shell.closeWorkspace(for: session)
        XCTAssertEqual(failedCloseOutcome, .autosaveFailed)
        shouldFail = false
        let didRetrySave = await workspace.retryPendingAutosaves()
        XCTAssertTrue(didRetrySave)
        XCTAssertFalse(workspace.state.isAutosaveRecoveryPresented)
        XCTAssertEqual(workspace.state.statusMessage, "Saved")

        let successfulCloseOutcome = await shell.closeWorkspace(for: session)
        XCTAssertEqual(successfulCloseOutcome, .closed)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 0)
    }

    func testDiscardingRecoveredAutosaveAllowsExplicitDataLoss() async {
        let shell = AppShellDriver()
        let projectPath = "/tmp/discard-save.openrecorder"
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/discard-save.mp4"),
            projectPath: projectPath
        )
        let workspace = shell.workspace(for: session)
        var didDiscard = false
        let saveAfterDiscard = expectation(description: "Discarded workspace must not save on disappear")
        saveAfterDiscard.isInverted = true
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { _ in
                if didDiscard { saveAfterDiscard.fulfill() }
                throw WorkspaceAutosaveError.failed
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        ))

        let failedCloseOutcome = await shell.closeWorkspace(for: session)
        XCTAssertEqual(failedCloseOutcome, .autosaveFailed)
        didDiscard = true
        shell.discardWorkspace(for: session)
        workspace.video.send(.disappeared(
            makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        ))

        await fulfillment(of: [saveAfterDiscard], timeout: 0.05)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 0)
        XCTAssertFalse(shell.workspace(for: session) === workspace)
    }

    func testWorkspaceCannotBeDiscardedWhileAutosaveIsInFlight() async {
        let shell = AppShellDriver()
        let projectPath = "/tmp/in-flight-discard.openrecorder"
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/in-flight-discard.mp4"),
            projectPath: projectPath
        )
        let workspace = shell.workspace(for: session)
        let gate = WorkspaceAutosaveGate()
        let saveStarted = expectation(description: "Autosave started before discard")
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                saveStarted.fulfill()
                await gate.wait()
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        ))
        let flush = Task { @MainActor in
            await workspace.video.flushPendingAutosave()
        }
        await fulfillment(of: [saveStarted], timeout: 1)

        XCTAssertFalse(shell.discardWorkspace(for: session))
        XCTAssertTrue(shell.workspace(for: session) === workspace)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 1)

        await gate.open()
        _ = await flush.value
        let closeOutcome = await shell.closeWorkspace(for: session)
        XCTAssertEqual(closeOutcome, .closed)
    }

    func testDefaultWorkspaceFailedCloseCanRetryWithoutEviction() async {
        let shell = AppShellDriver()
        let workspace = shell.workspace(for: nil)
        let snapshot = makeWorkspaceAutosaveSnapshot(path: "/tmp/default-retry.openrecorder", kind: .video)
        var shouldFail = true
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { snapshot in
                if shouldFail { throw WorkspaceAutosaveError.failed }
                return makeProjectSummary(path: snapshot.projectPath)
            },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(snapshot))

        let failedCloseOutcome = await shell.closeWorkspace(for: nil)
        XCTAssertEqual(failedCloseOutcome, .autosaveFailed)
        XCTAssertTrue(workspace.state.isAutosaveRecoveryPresented)
        XCTAssertTrue(shell.workspace(for: nil) === workspace)

        shouldFail = false
        let didRetrySave = await workspace.retryPendingAutosaves()
        XCTAssertTrue(didRetrySave)
        XCTAssertFalse(workspace.state.isAutosaveRecoveryPresented)

        let successfulCloseOutcome = await shell.closeWorkspace(for: nil)
        XCTAssertEqual(successfulCloseOutcome, .closed)
        XCTAssertTrue(shell.workspace(for: nil) === workspace)
    }

    func testDefaultWorkspaceDiscardReplacesAbandonedState() async {
        let shell = AppShellDriver()
        let workspace = shell.workspace(for: nil)
        let snapshot = makeWorkspaceAutosaveSnapshot(path: "/tmp/default-discard.openrecorder", kind: .video)
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { _ in throw WorkspaceAutosaveError.failed },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(snapshot))

        let failedCloseOutcome = await shell.closeWorkspace(for: nil)
        XCTAssertEqual(failedCloseOutcome, .autosaveFailed)
        shell.discardWorkspace(for: nil)

        let replacement = shell.workspace(for: nil)
        XCTAssertFalse(replacement === workspace)
        XCTAssertFalse(replacement.state.isAutosaveRecoveryPresented)
    }

    func testReactivatedFailedSessionCannotBeStolenByAnotherWindow() async {
        let shell = AppShellDriver()
        let projectPath = "/tmp/reactivated.openrecorder"
        let session = EditorSession(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/reactivated.mp4"),
            projectPath: projectPath
        )
        let workspace = shell.workspace(for: session)
        workspace.video.configure(
            applyTimelineSnapshot: { _ in },
            saveHandler: { _ in throw WorkspaceAutosaveError.failed },
            statusHandler: { _ in },
            pausePlayback: {},
            exportVideo: { _, _, _ in },
            clearVideoExportDialogState: {}
        )
        workspace.video.send(.autosaveSnapshotChanged(
            makeWorkspaceAutosaveSnapshot(path: projectPath, kind: .video)
        ))
        await shell.closeWorkspace(for: session)

        shell.activateWorkspace(for: session)
        let secondSession = EditorSession(
            kind: .video,
            url: session.url,
            projectPath: projectPath
        )
        let secondWorkspace = shell.workspace(for: secondSession)

        XCTAssertTrue(shell.workspace(for: session) === workspace)
        XCTAssertFalse(secondWorkspace === workspace)
        XCTAssertEqual(shell.sessionWorkspaceCountForTesting, 2)
    }

    func testSessionStatusStaysLocalWhileDefaultWorkspaceStatusForwards() {
        let model = AppModel()
        let originalStatus = model.statusMessage
        let session = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/local.png"))
        let sessionWorkspace = model.appShell.workspace(for: session)
        let defaultWorkspace = model.appShell.workspace(for: nil)

        sessionWorkspace.send(.statusUpdated(EditorWorkspaceStatus(
            message: "Session-only status",
            severity: .informational
        )))

        XCTAssertEqual(sessionWorkspace.state.statusMessage, "Session-only status")
        XCTAssertEqual(model.statusMessage, originalStatus)

        defaultWorkspace.send(.statusUpdated(EditorWorkspaceStatus(
            message: "Default workspace status",
            severity: .informational
        )))

        XCTAssertEqual(model.statusMessage, "Default workspace status")
    }

    func testWorkspaceConfigurationCoversExistingAndFutureSessions() {
        let shell = AppShellDriver()
        let firstSession = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/first-config.mp4"))
        let secondSession = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/second-config.mp4"))
        let firstWorkspace = shell.workspace(for: firstSession)
        var configuredWorkspaces: [ObjectIdentifier] = []

        shell.configure(configureWorkspace: { workspace in
            configuredWorkspaces.append(ObjectIdentifier(workspace))
        })
        let secondWorkspace = shell.workspace(for: secondSession)

        XCTAssertEqual(Set(configuredWorkspaces), Set([
            ObjectIdentifier(shell.workspace(for: nil)),
            ObjectIdentifier(firstWorkspace),
            ObjectIdentifier(secondWorkspace)
        ]))
        XCTAssertEqual(configuredWorkspaces.count, 3)
    }

    func testClosingSessionDoesNotSilentlyCancelAnActiveExport() async {
        let shell = AppShellDriver()
        var cancellationTokens: [ObjectIdentifier: VideoExportCancellationToken] = [:]
        var deletedURLs: [URL] = []
        let rendersStarted = expectation(description: "Both workspace exports started")
        rendersStarted.expectedFulfillmentCount = 2
        shell.configure(configureWorkspace: { workspace in
            let workspaceID = ObjectIdentifier(workspace)
            let temporaryURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mov")
            workspace.videoExport.configure(
                renderVideo: { _, _, _, token, _, _ in
                    cancellationTokens[workspaceID] = token
                    rendersStarted.fulfill()
                    while !token.isCancelled && !Task.isCancelled {
                        await Task.yield()
                    }
                    throw CancellationError()
                },
                temporaryURL: { _ in temporaryURL },
                saveDestination: { _, _ -> URL? in nil },
                copyFile: { _, _ in },
                deleteFile: { deletedURLs.append($0) },
                revealFile: { _ in },
                setStatusMessage: { _ in }
            )
        })
        let firstSession = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/first-export.mp4"))
        let secondSession = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/second-export.mp4"))
        let firstWorkspace = shell.workspace(for: firstSession)
        let secondWorkspace = shell.workspace(for: secondSession)
        let firstID = ObjectIdentifier(firstWorkspace)
        let secondID = ObjectIdentifier(secondWorkspace)

        firstWorkspace.videoExport.export(sourceURL: firstSession.url, options: .default, edits: .empty)
        secondWorkspace.videoExport.export(sourceURL: secondSession.url, options: .default, edits: .empty)
        await fulfillment(of: [rendersStarted], timeout: 1)

        let closeOutcome = await shell.closeWorkspace(for: firstSession)
        let didDiscardActiveExport = shell.discardWorkspace(for: firstSession)

        XCTAssertEqual(closeOutcome, .canceled)
        XCTAssertFalse(didDiscardActiveExport)
        XCTAssertEqual(firstWorkspace.videoExport.state.phase, .exporting)
        XCTAssertFalse(cancellationTokens[firstID]?.isCancelled ?? true)
        XCTAssertEqual(deletedURLs, [])
        XCTAssertEqual(secondWorkspace.videoExport.state.phase, .exporting)
        XCTAssertFalse(cancellationTokens[secondID]?.isCancelled ?? true)

        firstWorkspace.videoExport.cancelExport()
        secondWorkspace.videoExport.cancelExport()
        await shell.closeWorkspace(for: secondSession)
    }

    func testCloseAndQuitPreserveFinishedExportUntilUserSavesOrCancelsIt() async {
        let shell = AppShellDriver()
        let session = EditorSession(kind: .video, url: URL(fileURLWithPath: "/tmp/save-pending.mp4"))
        let workspace = shell.workspace(for: session)
        let temporaryURL = URL(fileURLWithPath: "/tmp/save-pending-export.mov")
        var deletedURLs: [URL] = []
        workspace.videoExport.configure(
            renderVideo: { _, _, _, _, _, _ in },
            temporaryURL: { _ in temporaryURL },
            saveDestination: { _, _ in nil },
            copyFile: { _, _ in },
            deleteFile: { deletedURLs.append($0) },
            revealFile: { _ in },
            setStatusMessage: { _ in }
        )

        workspace.videoExport.export(sourceURL: session.url, options: .default, edits: .empty)
        await waitForCondition { workspace.videoExport.state.phase == .savePending }

        let closeWhilePending = await shell.closeWorkspace(for: session)
        let canTerminateWhilePending = await shell.prepareForTermination()
        let didDiscardFinishedExport = shell.discardWorkspace(for: session)
        XCTAssertEqual(closeWhilePending, .canceled)
        XCTAssertFalse(canTerminateWhilePending)
        XCTAssertFalse(didDiscardFinishedExport)
        XCTAssertEqual(workspace.videoExport.state.pendingTempURL, temporaryURL)
        XCTAssertEqual(deletedURLs, [])
        XCTAssertEqual(workspace.state.statusSeverity, .failure)

        workspace.videoExport.clear()
        XCTAssertEqual(deletedURLs, [temporaryURL])
        let closeAfterCancel = await shell.closeWorkspace(for: session)
        XCTAssertEqual(closeAfterCancel, .closed)
    }

    func testAppModelFacadeMirrorsShellRouting() {
        let model = AppModel()
        let session = EditorSession(kind: .screenshot, url: URL(fileURLWithPath: "/tmp/screen.png"), title: "Screen")

        model.selectedSection = .projects
        XCTAssertEqual(model.appShell.state.selectedSection, .projects)

        model.showEditor(for: session)

        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertEqual(model.currentScreenshotURL, session.url)
        XCTAssertNil(model.currentVideoURL)
        XCTAssertEqual(model.lastEditorSession, session)
        XCTAssertEqual(model.appShell.state.lastEditorSession, session)
        XCTAssertEqual(model.windowCommand?.action, .showStudio)
        XCTAssertEqual(model.windowCommand?.editorSession, session)
    }
}

@MainActor
final class RecordingPreferencesStoreTests: XCTestCase {
    func testPreferencesRoundTripThroughIsolatedDefaults() throws {
        let suiteName = "RecordingPreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RecordingPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.load(), RecordingPreferences(
            createsZoomsAutomatically: true,
            autoZoomAnimationPreset: .balanced
        ))

        store.setCreatesZoomsAutomatically(false)
        store.setAutoZoomAnimationPreset(.cinematic)

        XCTAssertEqual(store.load(), RecordingPreferences(
            createsZoomsAutomatically: false,
            autoZoomAnimationPreset: .cinematic
        ))
    }
}

@MainActor
final class CaptureDriverStateMachineTests: XCTestCase {
    func testDriverAppliesCaptureReducerAndEmitsEffects() {
        let driver = CaptureDriver()
        var transitions: [CaptureTransition] = []
        var effects: [[CaptureEffect]] = []
        var didDismissScreenSelection = false
        var didShowHUD = false
        driver.configure(
            transitionHandler: { transitions.append($0) },
            effectObserver: { effects.append($0) },
            effectHandlers: CaptureEffectHandlers(
                showHUD: {
                    didShowHUD = true
                },
                dismissScreenSelection: {
                    didDismissScreenSelection = true
                }
            )
        )

        let transition = driver.send(.beginCapture(.recording, runtimeIsRecording: false))

        XCTAssertEqual(driver.state.phase, .choosingSourceType(.recording))
        XCTAssertEqual(transition.statusMessage, "Choose a source type.")
        XCTAssertEqual(transitions.map(\.state.phase), [.choosingSourceType(.recording)])
        XCTAssertEqual(effects, [[.dismissScreenSelection, .showHUD]])
        XCTAssertTrue(didDismissScreenSelection)
        XCTAssertTrue(didShowHUD)
    }

    func testDriverOwnsRecordingStartTaskCancellation() async {
        let driver = CaptureDriver()
        let source = makeCaptureSource(id: "display-1", kind: .display)
        let outputURL = URL(fileURLWithPath: "/tmp/recording.mp4")
        var started = 0
        var canceled = false
        var cancelEffectRan = false

        driver.configure(
            effectHandlers: CaptureEffectHandlers(
                cancelRecordingStart: {
                    cancelEffectRan = true
                },
                runRecordingStart: { _, _ in
                    started += 1
                    await waitUntilCancelled()
                    canceled = true
                }
            )
        )

        _ = driver.send(.recordingFilePrepared(source, outputURL))
        await waitForCondition { started == 1 }

        _ = driver.send(.recordingStopRequested)
        await waitForCondition { canceled }

        XCTAssertTrue(cancelEffectRan)
        XCTAssertTrue(canceled)
    }

    func testDriverOwnsScreenshotCaptureTaskCancellation() async {
        let driver = CaptureDriver()
        let source = makeCaptureSource(id: "window-1", kind: .window)
        var started = 0
        var canceled = false
        var cancelEffectRan = false

        driver.configure(
            effectHandlers: CaptureEffectHandlers(
                cancelScreenshotCapture: {
                    cancelEffectRan = true
                },
                runScreenshotCapture: { _ in
                    started += 1
                    await waitUntilCancelled()
                    canceled = true
                }
            )
        )

        driver.setStateForTesting(CaptureState(
            phase: .ready(.screenshot, source),
            selectedSource: source,
            preferredSourceKind: source.kind
        ))
        _ = driver.send(.screenshotRequested)
        await waitForCondition { started == 1 }

        _ = driver.send(.cancelCapture)
        await waitForCondition { canceled }

        XCTAssertTrue(cancelEffectRan)
        XCTAssertTrue(canceled)
    }
}

private func waitUntilCancelled() async {
    for await _ in AsyncStream<Void>(Void.self, { _ in }) {}
}

@MainActor
private func waitForCondition(
    timeout: Duration = .seconds(5),
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await clock.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "Timed out waiting for condition after \(timeout)", file: file, line: line)
}

@MainActor
final class CaptureOptionsStateMachineTests: XCTestCase {
    func testBooleanBindingsRouteThroughCaptureOptionEvents() {
        let driver = CaptureOptionsDriver()

        driver.binding(\.includeMicrophone).wrappedValue = true
        driver.binding(\.includeSystemAudio).wrappedValue = true
        driver.binding(\.includeCamera).wrappedValue = true
        driver.binding(\.showCursor).wrappedValue = false
        driver.binding(\.showClicks).wrappedValue = true
        driver.binding(\.canChangeOptions).wrappedValue = false

        XCTAssertTrue(driver.state.includeMicrophone)
        XCTAssertTrue(driver.state.includeSystemAudio)
        XCTAssertTrue(driver.state.includeCamera)
        XCTAssertFalse(driver.state.showCursor)
        XCTAssertTrue(driver.state.showClicks)
        XCTAssertFalse(driver.state.canChangeOptions)
    }

    func testDeviceSelectionAndLockedSystemAudioAreReducerDriven() {
        var state = CaptureOptionsState(
            microphoneDevices: [CaptureDeviceInfo(id: "mic-1", name: "Studio Mic", isDefault: false)],
            cameraDevices: [CaptureDeviceInfo(id: "cam-1", name: "Desk Camera", isDefault: false)]
        )

        var effects = state.applying(.microphoneSelected("mic-1"))
        XCTAssertTrue(state.includeMicrophone)
        XCTAssertEqual(state.selectedMicrophoneDeviceName, "Studio Mic")
        XCTAssertEqual(effects, [.setStatusMessage("Microphone set to Studio Mic"), .closeMicrophoneSelector])

        state.includeSystemAudio = true
        state.canChangeOptions = false
        effects = state.applying(.systemAudioToggled)

        XCTAssertTrue(state.includeSystemAudio)
        XCTAssertEqual(state.statusMessage, "System audio is on for this recording.")
        XCTAssertEqual(effects, [.setStatusMessage("System audio is on for this recording.")])
    }

    func testLockedCaptureOptionsRejectEveryUserMutationButAllowRuntimeCameraFallback() {
        var state = CaptureOptionsState(
            includeMicrophone: true,
            includeSystemAudio: true,
            includeCamera: true,
            showCursor: true,
            showClicks: false,
            selectedMicrophoneDeviceID: "mic-original",
            selectedCameraDeviceID: "cam-original",
            canChangeOptions: false
        )
        let lockedEvents: [CaptureOptionsEvent] = [
            .microphoneEnabledChanged(false),
            .systemAudioChanged(false),
            .cameraEnabledChanged(false),
            .microphoneSelectionRequested,
            .cameraSelectionRequested,
            .microphoneSelected("mic-new"),
            .cameraSelected("cam-new"),
            .microphoneDisabled,
            .cameraDisabled,
            .cursorVisibilityChanged(false),
            .clickVisibilityChanged(true)
        ]

        for event in lockedEvents {
            let effects = state.applying(event)
            XCTAssertEqual(effects, [.setStatusMessage("Recording options are locked while capture is starting.")])
        }
        XCTAssertTrue(state.includeMicrophone)
        XCTAssertTrue(state.includeSystemAudio)
        XCTAssertTrue(state.includeCamera)
        XCTAssertTrue(state.showCursor)
        XCTAssertFalse(state.showClicks)
        XCTAssertEqual(state.selectedMicrophoneDeviceID, "mic-original")
        XCTAssertEqual(state.selectedCameraDeviceID, "cam-original")

        XCTAssertEqual(state.applying(.cameraDisabledForCaptureFailure), [])
        XCTAssertFalse(state.includeCamera)
    }

    func testDeviceRefreshPreservesExplicitUnavailableSelections() {
        var state = CaptureOptionsState(
            includeMicrophone: true,
            includeCamera: true,
            microphoneDevices: [CaptureDeviceInfo(id: "mic-old", name: "Old Mic", isDefault: true)],
            cameraDevices: [CaptureDeviceInfo(id: "cam-old", name: "Old Camera", isDefault: true)],
            selectedMicrophoneDeviceID: "mic-old",
            selectedCameraDeviceID: "cam-old"
        )

        XCTAssertEqual(state.applying(.devicesRefreshed(
            microphones: [CaptureDeviceInfo(id: "mic-new", name: "New Mic", isDefault: true)],
            cameras: []
        )), [])

        XCTAssertEqual(state.selectedMicrophoneDeviceID, "mic-old")
        XCTAssertEqual(state.selectedCameraDeviceID, "cam-old")
        XCTAssertEqual(state.selectedMicrophoneDeviceName, "Previously Selected (Unavailable)")
        XCTAssertEqual(state.selectedCameraDeviceName, "Previously Selected (Unavailable)")
        XCTAssertFalse(state.hasAvailableMicrophoneSelection)
        XCTAssertFalse(state.hasAvailableCameraSelection)
        XCTAssertEqual(state.deviceLoadPhase, .loaded)
    }

    func testDeviceLoadPhaseAndSystemDefaultsRequireARealDevice() {
        var state = CaptureOptionsState()

        XCTAssertEqual(state.applying(.deviceRefreshStarted), [])
        XCTAssertEqual(state.deviceLoadPhase, .loading)
        XCTAssertEqual(state.applying(.deviceRefreshFailed("Device service unavailable")), [])
        XCTAssertEqual(state.deviceLoadPhase, .failed("Device service unavailable"))
        XCTAssertFalse(state.hasAvailableMicrophoneSelection)
        XCTAssertFalse(state.hasAvailableCameraSelection)

        _ = state.applying(.devicesRefreshed(
            microphones: [CaptureDeviceInfo(id: "mic-1", name: "Mic", isDefault: true)],
            cameras: [CaptureDeviceInfo(id: "cam-1", name: "Camera", isDefault: true)]
        ))
        XCTAssertTrue(state.hasAvailableMicrophoneSelection)
        XCTAssertTrue(state.hasAvailableCameraSelection)
    }

    func testOpeningDeviceSelectorsDoesNotEnumerateDevicesTwice() {
        var state = CaptureOptionsState(
            microphoneDevices: [CaptureDeviceInfo(id: "mic-1", name: "Mic", isDefault: true)],
            cameraDevices: [CaptureDeviceInfo(id: "cam-1", name: "Camera", isDefault: true)],
            deviceLoadPhase: .loaded
        )

        XCTAssertEqual(state.applying(.microphoneSelectionRequested), [.showMicrophoneSelector])
        XCTAssertEqual(state.applying(.cameraSelectionRequested), [.showCameraSelector])
        XCTAssertEqual(state.deviceLoadPhase, .loaded)
    }
}

@MainActor
final class SourceSelectorStateMachineTests: XCTestCase {
    func testPreferredTabHeightAndEffectsAreReducerDriven() {
        var state = SourceSelectorState(sourceTab: .windows, visibleTabs: [.windows, .area])

        XCTAssertEqual(state.applying(.preferredSourceKindSynced(.area)), [])
        XCTAssertEqual(state.sourceTab, .area)

        XCTAssertEqual(state.applying(.visibleTabsChanged([.screens])), [])
        XCTAssertEqual(state.visibleTabs, [.screens])
        XCTAssertEqual(state.sourceTab, .screens)

        XCTAssertEqual(state.applying(.heightMeasured(500)), [])
        XCTAssertEqual(state.preferredHeight, 532)

        XCTAssertEqual(state.applying(.refreshRequested), [.refreshSources])
        XCTAssertEqual(state.loadPhase, .loading)
        XCTAssertEqual(state.applying(.sourcesChanged(["window-1"])), [])
        XCTAssertEqual(state.applying(.sourceSelected("window-1")), [])
        XCTAssertEqual(state.applying(.shareRequested), [.share("window-1")])
        XCTAssertEqual(state.applying(.drawAreaRequested), [.drawArea])
    }

    func testPreferredSourceKindDoesNotSelectHiddenTab() {
        var state = SourceSelectorState(sourceTab: .windows, visibleTabs: [.windows, .area])

        XCTAssertEqual(state.applying(.preferredSourceKindSynced(.display)), [])

        XCTAssertEqual(state.sourceTab, .windows)
    }

    func testFloatingSelectionRemainsPendingUntilExplicitShare() {
        var state = SourceSelectorState(sourceTab: .windows, visibleTabs: [.windows, .area])
        _ = state.applying(.sourcesChanged(["window-1", "window-2"]))
        _ = state.applying(.committedSelectionSynced("window-1"))

        XCTAssertEqual(state.applying(.sourceSelected("window-2")), [])
        XCTAssertEqual(state.committedSourceID, "window-1")
        XCTAssertEqual(state.pendingSourceID, "window-2")

        XCTAssertEqual(state.applying(.cancelRequested), [.cancel])
        XCTAssertEqual(state.pendingSourceID, "window-1")

        _ = state.applying(.sourceSelected("window-2"))
        XCTAssertEqual(state.applying(.shareRequested), [.share("window-2")])
        XCTAssertEqual(state.committedSourceID, "window-2")
    }

    func testSourceRefreshClearsUnavailablePendingChoiceAndReportsFailures() {
        var state = SourceSelectorState(sourceTab: .windows, visibleTabs: [.windows])
        _ = state.applying(.sourcesChanged(["window-1"]))
        _ = state.applying(.sourceSelected("window-1"))

        let effects = state.applying(.refreshCompleted(SourceSelectorRefreshResult(
            sourceIDs: [],
            errorMessage: "Screen Recording permission is required."
        )))

        XCTAssertEqual(effects, [])
        XCTAssertNil(state.pendingSourceID)
        XCTAssertFalse(state.canSharePendingSource)
        XCTAssertEqual(state.loadPhase, .failed("Screen Recording permission is required."))
        XCTAssertEqual(state.applying(.shareRequested), [])
    }

    func testDriverPublishesAsyncRefreshBeforeSharingExactPendingSource() async {
        let driver = SourceSelectorDriver(sourceTab: .windows, visibleTabs: [.windows])
        var sharedSourceID: String?
        driver.configure(
            refreshSources: {
                .loaded(sourceIDs: ["window-1"])
            },
            share: { sourceID in
                sharedSourceID = sourceID
            }
        )

        driver.send(.refreshRequested)
        XCTAssertEqual(driver.state.loadPhase, .loading)
        await waitForCondition {
            driver.state.loadPhase == .loaded
        }

        driver.send(.sourceSelected("window-1"))
        driver.send(.shareRequested)

        XCTAssertEqual(sharedSourceID, "window-1")
        XCTAssertEqual(driver.state.committedSourceID, "window-1")
    }

    func testDriverIgnoresCanceledRefreshResultWhenANewerRequestWins() async {
        let driver = SourceSelectorDriver(sourceTab: .windows, visibleTabs: [.windows])
        var refreshCount = 0
        driver.configure(refreshSources: {
            refreshCount += 1
            let currentRefresh = refreshCount
            if currentRefresh == 1 {
                try? await Task.sleep(for: .milliseconds(200))
                return .loaded(sourceIDs: ["stale-window"])
            }
            return .loaded(sourceIDs: ["fresh-window"])
        })

        driver.send(.refreshRequested)
        await waitForCondition { refreshCount == 1 }
        driver.send(.refreshRequested)
        await waitForCondition {
            driver.state.loadPhase == .loaded &&
                driver.state.availableSourceIDs == ["fresh-window"]
        }
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(driver.state.availableSourceIDs, ["fresh-window"])
    }
}

@MainActor
final class OnboardingAndSettingsStateMachineTests: XCTestCase {
    func testOnboardingPermissionAndContinueLifecycle() {
        var state = OnboardingMachineState(
            screenRecordingPermissionState: .requestAvailable,
            accessibilityPermissionState: .requestAvailable
        )

        XCTAssertEqual(state.applying(.continueRequested), [])
        XCTAssertEqual(state.statusMessage, "Screen Recording permission is required before continuing.")

        let effects = state.applying(.screenPermissionRequested(.granted))
        XCTAssertEqual(state.screenRecordingPermissionState, .granted)
        XCTAssertEqual(state.statusMessage, "Screen Recording is enabled.")
        XCTAssertEqual(effects, [.refreshPermissions])

        XCTAssertEqual(state.applying(.continueRequested), [.completeOnboarding])
    }

    func testSettingsPreferenceAndFolderEffects() {
        var state = SettingsMachineState(createZoomsAutomatically: false)

        XCTAssertEqual(state.applying(.autoZoomPreferenceChanged(true)), [.persistAutoZoomPreference(true)])
        XCTAssertTrue(state.createZoomsAutomatically)
        XCTAssertEqual(state.applying(.autoZoomPreferenceChanged(true)), [])
        XCTAssertEqual(state.applying(.autoZoomAnimationPresetChanged(.cinematic)), [.persistAutoZoomAnimationPreset(.cinematic)])
        XCTAssertEqual(state.autoZoomAnimationPreset, .cinematic)
        XCTAssertEqual(state.applying(.autoZoomAnimationPresetChanged(.cinematic)), [])
        XCTAssertEqual(state.applying(.autoZoomAnimationPresetSynced(.guided)), [])
        XCTAssertEqual(state.autoZoomAnimationPreset, .guided)
        XCTAssertEqual(state.applying(.folderOpenRequested("/tmp")), [.openFolder("/tmp")])

        XCTAssertEqual(state.applying(.serviceRefreshStarted), [])
        XCTAssertTrue(state.isRefreshingService)
        XCTAssertEqual(state.applying(.serviceRefreshSucceeded), [])
        XCTAssertFalse(state.isRefreshingService)
    }
}

@MainActor
final class VideoRuntimeStateMachineTests: XCTestCase {
    func testPlaybackReducerResetsLoadsAndAppliesSpeed() {
        var state = VideoPlaybackState()
        let url = URL(fileURLWithPath: "/tmp/demo.mov")

        XCTAssertEqual(state.applying(.load(url)), [.clearPlayer, .loadPlayer(url), .loadMetadata(url)])
        XCTAssertEqual(state.currentURL, url)
        XCTAssertEqual(state.previewPlaybackSpeed, 1)

        state.duration = 8
        state.previewPlaybackSpeed = 2
        state.timelineEdits = TimelineEditSnapshot(clipSplitTimes: [4], clipSpeeds: [1: 1.5])

        XCTAssertEqual(state.effectivePlaybackRate(at: 5), 3)
        XCTAssertEqual(state.applying(.previewSpeedCycled), [])
        XCTAssertEqual(state.previewPlaybackSpeed, 4)
    }

    func testPlaybackSeekWithoutDurationClampsLowerBoundOnly() {
        var state = VideoPlaybackState()

        XCTAssertEqual(state.applying(.seekRequested(-2)), [.seek(0)])
        XCTAssertEqual(state.currentTime, 0)

        XCTAssertEqual(state.applying(.seekRequested(12)), [.seek(12)])
        XCTAssertEqual(state.currentTime, 12)
    }

    func testCropReducerHandlesKeyboardAspectAndConfirm() {
        var state = VideoCropState(
            draftSelection: VideoCropSelection().withPixelRect(CGRect(x: 100, y: 100, width: 800, height: 600), in: CGSize(width: 1920, height: 1080)),
            sourceSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(state.applying(.keyboardAdjusted(.move(dx: 10, dy: -5))), [])
        XCTAssertEqual(state.currentPixelRect.minX, 110, accuracy: 0.001)
        XCTAssertEqual(state.currentPixelRect.minY, 95, accuracy: 0.001)

        XCTAssertEqual(state.applying(.aspectSelected(.square)), [])
        XCTAssertEqual(state.aspect, .square)
        XCTAssertEqual(state.currentPixelRect.width, state.currentPixelRect.height, accuracy: 0.001)

        XCTAssertEqual(state.applying(.confirmRequested), [.confirm(state.draftSelection)])
    }
}

private func makeProjectSummary(path: String) -> ProjectSummary {
    ProjectSummary(
        id: path,
        title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        path: path,
        recordingPath: "/tmp/demo.mp4",
        screenshotPath: nil,
        sourceName: "Display",
        createdAt: "2026-05-19T00:00:00Z",
        updatedAt: "2026-05-19T00:00:00Z",
        lastOpenedAt: "2026-05-19T00:00:00Z",
        missing: false
    )
}

private func makeWorkspaceAutosaveSnapshot(path: String, kind: EditorMediaKind) -> ProjectAutosaveSnapshot {
    ProjectAutosaveSnapshot(
        projectPath: path,
        title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        recordingPath: kind == .video ? "/tmp/demo.mp4" : nil,
        screenshotPath: kind == .screenshot ? "/tmp/demo.png" : nil,
        sourceName: nil,
        editorState: ProjectEditorState(
            timelineEdits: .empty,
            video: kind == .video ? .default : nil,
            screenshot: kind == .screenshot ? .default : nil
        ),
        recordingSession: nil
    )
}

private actor WorkspaceAutosaveGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private enum WorkspaceAutosaveError: LocalizedError {
    case failed

    var errorDescription: String? { "Save failed" }
}

private func makeCaptureSource(id: String, kind: CaptureSourceKind) -> CaptureSource {
    CaptureSource(
        id: id,
        kind: kind,
        name: kind == .display ? "Display" : "Window",
        subtitle: "",
        displayIndex: kind == .display ? 1 : nil,
        displayID: kind == .display ? 1 : nil,
        windowID: kind == .window ? 42 : nil,
        area: nil,
        thumbnailData: nil
    )
}
