import Foundation
import Observation
import SwiftUI

enum VideoEditorSheet: Identifiable, Equatable, Hashable {
    case export
    case crop(URL)

    var id: String {
        switch self {
        case .export:
            "export"
        case .crop(let videoURL):
            "crop:\(videoURL.path)"
        }
    }
}

struct VideoEditorSessionContext: Equatable {
    var videoURL: URL?
    var projectPath: String?
    var editorTitle: String?
    var recordingSession: RecordingSession?
    var initialTimelineEdits: TimelineEditSnapshot?
    var initialVideoState: ProjectVideoEditorState?
    var editorSessionID: UUID?
    var defaultShowCursor: Bool

    var identity: String {
        projectPath ?? videoURL?.path ?? editorSessionID?.uuidString ?? "empty"
    }
}

struct VideoEditorState: Equatable {
    var video = ProjectVideoEditorState.default
    var previewAspectPreset: VideoPreviewAspectPreset = .auto
    var activeSheet: VideoEditorSheet?
    var presentedSheet: VideoEditorSheet?
    var appliedTimelineIdentity: String?
    var appliedVideoStateIdentity: String?
    var hasRecordedCamera = false

    var initialExportOptions: VideoExportOptions {
        VideoExportOptions.default.withCropSelection(video.cropSelection)
    }

    var cursorOverlaySettings: CursorOverlaySettings {
        video.cursorOverlay.clamped
    }

    var currentFacecamSettings: FacecamSettings? {
        hasRecordedCamera ? video.facecamSettings?.clamped : nil
    }

    func styledExportOptions(from options: VideoExportOptions, cursorTelemetryURL: URL?) -> VideoExportOptions {
        options.with(
            background: video.background,
            padding: video.padding,
            borderRadius: video.borderRadius,
            shadow: video.shadow,
            backgroundBlur: video.backgroundBlur,
            inset: video.inset,
            insetColor: video.insetColor,
            insetOpacity: video.insetOpacity,
            insetBalance: video.insetBalance
        )
        .withAspectPreset(previewAspectPreset)
        .withCursorOverlay(cursorOverlaySettings, telemetryURL: cursorTelemetryURL)
    }

    func autosaveSnapshot(
        projectPath: String?,
        videoURL: URL?,
        editorTitle: String?,
        recordingSession: RecordingSession?,
        timelineEdits: TimelineEditSnapshot
    ) -> ProjectAutosaveSnapshot? {
        guard let projectPath, let videoURL else { return nil }
        return ProjectAutosaveSnapshot(
            projectPath: projectPath,
            title: editorTitle ?? EditorMediaKind.video.displayTitle(for: videoURL),
            recordingPath: videoURL.path,
            screenshotPath: nil,
            sourceName: recordingSession?.sourceName,
            editorState: ProjectEditorState(timelineEdits: timelineEdits, video: video)
        )
    }
}

enum VideoEditorEvent: Equatable {
    case sessionChanged(VideoEditorSessionContext)
    case videoStateChanged(ProjectVideoEditorState)
    case previewAspectChanged(VideoPreviewAspectPreset)
    case cropRequested(URL)
    case cropConfirmed(VideoCropSelection)
    case cropCanceled
    case exportRequested
    case exportConfirmed(
        recordingURL: URL?,
        options: VideoExportOptions,
        edits: TimelineEditSnapshot,
        snapshot: ProjectAutosaveSnapshot?,
        cursorTelemetryURL: URL?
    )
    case sheetDismissed(exportIsBusy: Bool)
    case autosaveSnapshotChanged(ProjectAutosaveSnapshot?)
    case disappeared(ProjectAutosaveSnapshot?)
}

enum VideoEditorEffect: Equatable {
    case applyTimelineSnapshot(TimelineEditSnapshot)
    case markAutosaved(ProjectAutosaveSnapshot?)
    case scheduleAutosave(ProjectAutosaveSnapshot?)
    case flushAutosave(ProjectAutosaveSnapshot?)
    case pausePlayback
    case startVideoExport(
        recordingURL: URL?,
        options: VideoExportOptions,
        edits: TimelineEditSnapshot,
        snapshot: ProjectAutosaveSnapshot?
    )
    case clearVideoExportDialogState
}

extension VideoEditorState {
    mutating func applying(_ event: VideoEditorEvent) -> [VideoEditorEffect] {
        switch event {
        case .sessionChanged(let context):
            return apply(context)

        case .videoStateChanged(let nextVideo):
            guard video != nextVideo else { return [] }
            video = Self.normalized(nextVideo, hasRecordedCamera: hasRecordedCamera)
            return []

        case .previewAspectChanged(let nextPreset):
            guard previewAspectPreset != nextPreset else { return [] }
            previewAspectPreset = nextPreset
            return []

        case .cropRequested(let videoURL):
            activeSheet = .crop(videoURL)
            presentedSheet = .crop(videoURL)
            return [.pausePlayback]

        case .cropConfirmed(let selection):
            video.cropSelection = selection
            activeSheet = nil
            presentedSheet = nil
            return []

        case .cropCanceled:
            activeSheet = nil
            presentedSheet = nil
            return []

        case .exportRequested:
            activeSheet = .export
            presentedSheet = .export
            return []

        case .exportConfirmed(let recordingURL, let options, let edits, let snapshot, let cursorTelemetryURL):
            let styledOptions = styledExportOptions(from: options, cursorTelemetryURL: cursorTelemetryURL)
            return [.startVideoExport(recordingURL: recordingURL, options: styledOptions, edits: edits, snapshot: snapshot)]

        case .sheetDismissed(let exportIsBusy):
            let shouldClearExport = presentedSheet == .export && !exportIsBusy
            if !exportIsBusy {
                activeSheet = nil
                presentedSheet = nil
            }
            return shouldClearExport ? [.clearVideoExportDialogState] : []

        case .autosaveSnapshotChanged(let snapshot):
            return [.scheduleAutosave(snapshot)]

        case .disappeared(let snapshot):
            return [.flushAutosave(snapshot)]
        }
    }

    private mutating func apply(_ context: VideoEditorSessionContext) -> [VideoEditorEffect] {
        let identity = context.identity
        var effects: [VideoEditorEffect] = []
        var didApplyState = false

        hasRecordedCamera = context.recordingSession?.hasRecordedCamera == true

        if appliedTimelineIdentity != identity {
            appliedTimelineIdentity = identity
            effects.append(.applyTimelineSnapshot(context.initialTimelineEdits ?? .empty))
            didApplyState = true
        }

        if appliedVideoStateIdentity != identity {
            appliedVideoStateIdentity = identity
            video = Self.initialVideoState(for: context)
            previewAspectPreset = .auto
            didApplyState = true
        }

        if didApplyState {
            effects.append(.markAutosaved(autosaveSnapshot(
                projectPath: context.projectPath,
                videoURL: context.videoURL,
                editorTitle: context.editorTitle,
                recordingSession: context.recordingSession,
                timelineEdits: context.initialTimelineEdits ?? .empty
            )))
        }

        return effects
    }

    private static func initialVideoState(for context: VideoEditorSessionContext) -> ProjectVideoEditorState {
        var next = context.initialVideoState ?? .default
        let defaults = ProjectVideoEditorState.default

        if context.initialVideoState == nil {
            next.cursorOverlay = CursorOverlaySettings(
                isVisible: context.recordingSession?.showCursorOverlay ?? context.defaultShowCursor,
                loops: defaults.cursorOverlay.loops,
                size: defaults.cursorOverlay.size,
                smoothing: defaults.cursorOverlay.smoothing,
                style: defaults.cursorOverlay.style,
                variant: defaults.cursorOverlay.variant
            )
        }

        if context.recordingSession?.hasRecordedCamera == true {
            next.facecamSettings = (context.initialVideoState?.facecamSettings
                ?? context.recordingSession?.facecamSettings
                ?? defaultFacecamSettings(enabled: true))
                .clamped
        } else {
            next.facecamSettings = nil
        }

        return normalized(next, hasRecordedCamera: context.recordingSession?.hasRecordedCamera == true)
    }

    private static func normalized(_ video: ProjectVideoEditorState, hasRecordedCamera: Bool) -> ProjectVideoEditorState {
        var next = video
        next.cursorOverlay = video.cursorOverlay.clamped
        next.insetBalance = video.insetBalance.clamped
        next.facecamSettings = hasRecordedCamera ? (video.facecamSettings ?? defaultFacecamSettings(enabled: true)).clamped : nil
        return next
    }
}

@Observable
@MainActor
final class VideoEditorDriver {
    var state = VideoEditorState()

    @ObservationIgnored private let autosave = ProjectAutosaveCoordinator()
    @ObservationIgnored private var applyTimelineSnapshot: (TimelineEditSnapshot) -> Void = { _ in }
    @ObservationIgnored private var pausePlayback: () -> Void = {}
    @ObservationIgnored private var exportVideo: (URL?, VideoExportOptions, TimelineEditSnapshot) -> Void = { _, _, _ in }
    @ObservationIgnored private var clearVideoExportDialogState: () -> Void = {}

    func configure(
        applyTimelineSnapshot: @escaping (TimelineEditSnapshot) -> Void,
        saveHandler: @escaping ProjectAutosaveCoordinator.SaveHandler,
        statusHandler: @escaping ProjectAutosaveCoordinator.StatusHandler,
        pausePlayback: @escaping () -> Void,
        exportVideo: @escaping (URL?, VideoExportOptions, TimelineEditSnapshot) -> Void,
        clearVideoExportDialogState: @escaping () -> Void
    ) {
        self.applyTimelineSnapshot = applyTimelineSnapshot
        self.pausePlayback = pausePlayback
        self.exportVideo = exportVideo
        self.clearVideoExportDialogState = clearVideoExportDialogState
        autosave.configure(saveHandler: saveHandler, statusHandler: statusHandler)
    }

    func send(_ event: VideoEditorEvent) {
        let effects = state.applying(event)
        perform(effects)
    }

    func binding<Value: Equatable>(_ keyPath: WritableKeyPath<ProjectVideoEditorState, Value>) -> Binding<Value> {
        Binding(
            get: { self.state.video[keyPath: keyPath] },
            set: { self.updateVideoValue(keyPath, to: $0) }
        )
    }

    func facecamBinding<Value: Equatable>(
        _ keyPath: WritableKeyPath<FacecamSettings, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: { self.state.video.facecamSettings?[keyPath: keyPath] ?? defaultValue },
            set: { self.updateFacecamValue(keyPath, to: $0) }
        )
    }

    var previewAspectPresetBinding: Binding<VideoPreviewAspectPreset> {
        Binding(
            get: { self.state.previewAspectPreset },
            set: { self.send(.previewAspectChanged($0)) }
        )
    }

    func activeSheetBinding(exportIsBusy: Bool) -> Binding<VideoEditorSheet?> {
        Binding(
            get: { self.state.activeSheet },
            set: { nextSheet in
                switch nextSheet {
                case .export:
                    self.send(.exportRequested)
                case .crop(let url):
                    self.send(.cropRequested(url))
                case nil:
                    self.send(.sheetDismissed(exportIsBusy: exportIsBusy))
                }
            }
        )
    }

    func autosaveSnapshot(
        projectPath: String?,
        videoURL: URL?,
        editorTitle: String?,
        recordingSession: RecordingSession?,
        timelineEdits: TimelineEditSnapshot
    ) -> ProjectAutosaveSnapshot? {
        state.autosaveSnapshot(
            projectPath: projectPath,
            videoURL: videoURL,
            editorTitle: editorTitle,
            recordingSession: recordingSession,
            timelineEdits: timelineEdits
        )
    }

    private func updateVideoValue<Value: Equatable>(
        _ keyPath: WritableKeyPath<ProjectVideoEditorState, Value>,
        to value: Value
    ) {
        var next = state.video
        guard next[keyPath: keyPath] != value else { return }
        next[keyPath: keyPath] = value
        send(.videoStateChanged(next))
    }

    private func updateFacecamValue<Value: Equatable>(
        _ keyPath: WritableKeyPath<FacecamSettings, Value>,
        to value: Value
    ) {
        var next = state.video
        var facecam = next.facecamSettings ?? defaultFacecamSettings(enabled: state.hasRecordedCamera)
        guard facecam[keyPath: keyPath] != value else { return }
        facecam[keyPath: keyPath] = value
        next.facecamSettings = facecam.clamped
        send(.videoStateChanged(next))
    }

    private func perform(_ effects: [VideoEditorEffect]) {
        for effect in effects {
            switch effect {
            case .applyTimelineSnapshot(let snapshot):
                applyTimelineSnapshot(snapshot)
            case .markAutosaved(let snapshot):
                autosave.markSaved(snapshot)
            case .scheduleAutosave(let snapshot):
                autosave.schedule(snapshot)
            case .flushAutosave(let snapshot):
                Task { [weak self] in
                    await self?.flushAutosave(snapshot)
                }
            case .pausePlayback:
                pausePlayback()
            case .startVideoExport(let recordingURL, let options, let edits, let snapshot):
                Task { [weak self] in
                    await self?.flushAndExport(recordingURL: recordingURL, options: options, edits: edits, snapshot: snapshot)
                }
            case .clearVideoExportDialogState:
                clearVideoExportDialogState()
            }
        }
    }

    private func flushAutosave(_ snapshot: ProjectAutosaveSnapshot?) async {
        await autosave.flush(snapshot)
    }

    private func flushAndExport(
        recordingURL: URL?,
        options: VideoExportOptions,
        edits: TimelineEditSnapshot,
        snapshot: ProjectAutosaveSnapshot?
    ) async {
        await autosave.flush(snapshot)
        exportVideo(recordingURL, options, edits)
    }
}

struct ScreenshotEditorSessionContext: Equatable {
    var screenshotURL: URL?
    var projectPath: String?
    var editorTitle: String?
    var initialScreenshotState: ScreenshotEditorState?
    var editorSessionID: UUID?

    var identity: String {
        projectPath ?? screenshotURL?.path ?? editorSessionID?.uuidString ?? "empty"
    }
}

struct ScreenshotEditorPresentationState: Equatable {
    var isExportDialogPresented = false
    var appliedScreenshotStateIdentity: String?

    func autosaveSnapshot(
        projectPath: String?,
        screenshotURL: URL?,
        editorTitle: String?,
        editorState: ScreenshotEditorState
    ) -> ProjectAutosaveSnapshot? {
        guard let projectPath, let screenshotURL else { return nil }
        return ProjectAutosaveSnapshot(
            projectPath: projectPath,
            title: editorTitle ?? EditorMediaKind.screenshot.displayTitle(for: screenshotURL),
            recordingPath: nil,
            screenshotPath: screenshotURL.path,
            sourceName: nil,
            editorState: ProjectEditorState(screenshot: editorState)
        )
    }
}

enum ScreenshotEditorPresentationEvent: Equatable {
    case sessionChanged(ScreenshotEditorSessionContext)
    case exportRequested
    case exportDialogDismissed
    case autosaveSnapshotChanged(ProjectAutosaveSnapshot?)
    case disappeared(ProjectAutosaveSnapshot?)
    case saveFailed(String)
    case saveSucceeded(URL)
    case copyFailed(String)
    case copySucceeded
}

enum ScreenshotEditorPresentationEffect: Equatable {
    case applyScreenshotState(ScreenshotEditorState)
    case markAutosaved(ProjectAutosaveSnapshot?)
    case scheduleAutosave(ProjectAutosaveSnapshot?)
    case flushAutosave(ProjectAutosaveSnapshot?)
    case setStatusMessage(String)
}

extension ScreenshotEditorPresentationState {
    mutating func applying(_ event: ScreenshotEditorPresentationEvent) -> [ScreenshotEditorPresentationEffect] {
        switch event {
        case .sessionChanged(let context):
            guard appliedScreenshotStateIdentity != context.identity else { return [] }
            appliedScreenshotStateIdentity = context.identity
            let nextState = context.initialScreenshotState ?? .default
            return [
                .applyScreenshotState(nextState),
                .markAutosaved(autosaveSnapshot(
                    projectPath: context.projectPath,
                    screenshotURL: context.screenshotURL,
                    editorTitle: context.editorTitle,
                    editorState: nextState
                ))
            ]

        case .exportRequested:
            isExportDialogPresented = true
            return []

        case .exportDialogDismissed:
            isExportDialogPresented = false
            return []

        case .autosaveSnapshotChanged(let snapshot):
            return [.scheduleAutosave(snapshot)]

        case .disappeared(let snapshot):
            return [.flushAutosave(snapshot)]

        case .saveFailed(let message):
            return [.setStatusMessage(message)]

        case .saveSucceeded(let url):
            return [.setStatusMessage("Exported \(url.lastPathComponent)")]

        case .copyFailed(let message):
            return [.setStatusMessage(message)]

        case .copySucceeded:
            return [.setStatusMessage("Screenshot PNG copied")]
        }
    }
}

@Observable
@MainActor
final class ScreenshotEditorPresentationDriver {
    var state = ScreenshotEditorPresentationState()

    @ObservationIgnored private let autosave = ProjectAutosaveCoordinator()
    @ObservationIgnored private var applyScreenshotState: (ScreenshotEditorState) -> Void = { _ in }
    @ObservationIgnored private var setStatusMessage: (String) -> Void = { _ in }

    func configure(
        applyScreenshotState: @escaping (ScreenshotEditorState) -> Void,
        saveHandler: @escaping ProjectAutosaveCoordinator.SaveHandler,
        statusHandler: @escaping ProjectAutosaveCoordinator.StatusHandler,
        setStatusMessage: @escaping (String) -> Void
    ) {
        self.applyScreenshotState = applyScreenshotState
        self.setStatusMessage = setStatusMessage
        autosave.configure(saveHandler: saveHandler, statusHandler: statusHandler)
    }

    func send(_ event: ScreenshotEditorPresentationEvent) {
        let effects = state.applying(event)
        perform(effects)
    }

    var exportDialogBinding: Binding<Bool> {
        Binding(
            get: { self.state.isExportDialogPresented },
            set: { isPresented in
                if isPresented {
                    self.send(.exportRequested)
                } else {
                    self.send(.exportDialogDismissed)
                }
            }
        )
    }

    func autosaveSnapshot(
        projectPath: String?,
        screenshotURL: URL?,
        editorTitle: String?,
        editorState: ScreenshotEditorState
    ) -> ProjectAutosaveSnapshot? {
        state.autosaveSnapshot(
            projectPath: projectPath,
            screenshotURL: screenshotURL,
            editorTitle: editorTitle,
            editorState: editorState
        )
    }

    private func perform(_ effects: [ScreenshotEditorPresentationEffect]) {
        for effect in effects {
            switch effect {
            case .applyScreenshotState(let state):
                applyScreenshotState(state)
            case .markAutosaved(let snapshot):
                autosave.markSaved(snapshot)
            case .scheduleAutosave(let snapshot):
                autosave.schedule(snapshot)
            case .flushAutosave(let snapshot):
                Task { [weak self] in
                    await self?.flushAutosave(snapshot)
                }
            case .setStatusMessage(let message):
                setStatusMessage(message)
            }
        }
    }

    private func flushAutosave(_ snapshot: ProjectAutosaveSnapshot?) async {
        await autosave.flush(snapshot)
    }
}
