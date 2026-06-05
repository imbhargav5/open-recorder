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

struct VideoExportDraftState: Equatable {
    var resolution: VideoExportResolution = VideoExportResolution.defaultExportOption
    var format: VideoExportFormat = .mov
    var frameRate: VideoExportFrameRate = VideoExportFrameRate.defaultExportOption
    var baseOptions: VideoExportOptions = .default

    init(options: VideoExportOptions = .default) {
        applyInitialOptions(options)
    }

    var currentOptions: VideoExportOptions {
        VideoExportOptions(
            resolution: resolution,
            format: format,
            frameRate: frameRate,
            aspectPreset: baseOptions.aspectPreset,
            styling: .none,
            cropSelection: baseOptions.cropSelection,
            customOutputSize: resolution == .custom ? baseOptions.customOutputSize : nil,
            cursorOverlay: baseOptions.cursorOverlay,
            cursorTelemetryURL: baseOptions.cursorTelemetryURL
        )
    }

    mutating func applyInitialOptions(_ options: VideoExportOptions) {
        baseOptions = options
        resolution = VideoExportResolution.exportOptions.contains(options.resolution)
            ? options.resolution
            : VideoExportResolution.defaultExportOption
        format = options.format
        frameRate = VideoExportFrameRate.exportOptions.contains(options.frameRate)
            ? options.frameRate
            : VideoExportFrameRate.defaultExportOption
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
    var exportDraft = VideoExportDraftState()

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
            editorState: ProjectEditorState(timelineEdits: timelineEdits, video: video),
            recordingSession: recordingSession
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
    case exportResolutionChanged(VideoExportResolution)
    case exportFrameRateChanged(VideoExportFrameRate)
    case exportConfirmed(
        recordingURL: URL?,
        edits: TimelineEditSnapshot,
        snapshot: ProjectAutosaveSnapshot?,
        cursorTelemetryURL: URL?,
        facecamVideoURL: URL?,
        facecamOffsetMs: Int?,
        cameraFallback: FacecamSettings?
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
            exportDraft.applyInitialOptions(initialExportOptions)
            activeSheet = .export
            presentedSheet = .export
            return []

        case .exportResolutionChanged(let resolution):
            guard exportDraft.resolution != resolution else { return [] }
            exportDraft.resolution = resolution
            return []

        case .exportFrameRateChanged(let frameRate):
            guard exportDraft.frameRate != frameRate else { return [] }
            exportDraft.frameRate = frameRate
            return []

        case .exportConfirmed(let recordingURL, let edits, let snapshot, let cursorTelemetryURL, let facecamVideoURL, let facecamOffsetMs, let cameraFallback):
            let styledOptions = styledExportOptions(from: exportDraft.currentOptions, cursorTelemetryURL: cursorTelemetryURL)
                .withFacecam(url: facecamVideoURL, offsetMs: facecamOffsetMs, fallbackSettings: cameraFallback)
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
                styleID: defaults.cursorOverlay.styleID,
                clickEffect: defaults.cursorOverlay.clickEffect,
                idleBehavior: defaults.cursorOverlay.idleBehavior,
                motionEffect: defaults.cursorOverlay.motionEffect
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

    var exportResolutionBinding: Binding<VideoExportResolution> {
        Binding(
            get: { self.state.exportDraft.resolution },
            set: { self.send(.exportResolutionChanged($0)) }
        )
    }

    var exportFrameRateBinding: Binding<VideoExportFrameRate> {
        Binding(
            get: { self.state.exportDraft.frameRate },
            set: { self.send(.exportFrameRateChanged($0)) }
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

struct EditorExportRequest: Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var editorSessionID: UUID?
}

struct EditorWorkspaceState: Equatable {
    var selectedSection: AppSection = .editor
    var isShortcutsHelpPresented = false
    var videoExportRequest: EditorExportRequest?
    var screenshotExportRequest: EditorExportRequest?
}

enum EditorWorkspaceEvent: Equatable {
    case appSectionSynced(AppSection)
    case sectionSelected(AppSection)
    case shortcutsHelpToggled
    case shortcutsHelpPresented(Bool)
    case videoExportRequested(URL?, editorSessionID: UUID?)
    case screenshotExportRequested(URL?, editorSessionID: UUID?)
    case undoRequested(EditorMediaKind?)
    case redoRequested(EditorMediaKind?)
    case timelineSelectionClearRequested
}

enum EditorWorkspaceEffect: Equatable {
    case setAppSection(AppSection)
    case setStatusMessage(String)
    case undoTimeline
    case redoTimeline
    case undoScreenshot
    case redoScreenshot
    case clearTimelineSelection
}

extension EditorWorkspaceState {
    mutating func applying(_ event: EditorWorkspaceEvent) -> [EditorWorkspaceEffect] {
        switch event {
        case .appSectionSynced(let section):
            selectedSection = section
            return []

        case .sectionSelected(let section):
            guard selectedSection != section else { return [] }
            selectedSection = section
            return [.setAppSection(section)]

        case .shortcutsHelpToggled:
            isShortcutsHelpPresented.toggle()
            return []

        case .shortcutsHelpPresented(let isPresented):
            isShortcutsHelpPresented = isPresented
            return []

        case .videoExportRequested(let url, let editorSessionID):
            guard let url else {
                return [.setStatusMessage("Open a recording first.")]
            }
            videoExportRequest = EditorExportRequest(url: url, editorSessionID: editorSessionID)
            return []

        case .screenshotExportRequested(let url, let editorSessionID):
            guard let url else {
                return [.setStatusMessage("Open a screenshot first.")]
            }
            screenshotExportRequest = EditorExportRequest(url: url, editorSessionID: editorSessionID)
            return []

        case .undoRequested(let kind):
            guard selectedSection == .editor else { return [] }
            switch kind {
            case .video:
                return [.undoTimeline]
            case .screenshot:
                return [.undoScreenshot]
            case nil:
                return []
            }

        case .redoRequested(let kind):
            guard selectedSection == .editor else { return [] }
            switch kind {
            case .video:
                return [.redoTimeline]
            case .screenshot:
                return [.redoScreenshot]
            case nil:
                return []
            }

        case .timelineSelectionClearRequested:
            return [.clearTimelineSelection]
        }
    }
}

@Observable
@MainActor
final class EditorWorkspaceDriver {
    var state = EditorWorkspaceState()
    let video = VideoEditorDriver()
    let timeline = TimelineEditDriver()
    let screenshot = ScreenshotEditorDriver()

    @ObservationIgnored private var setAppSection: (AppSection) -> Void = { _ in }
    @ObservationIgnored private var setStatusMessage: (String) -> Void = { _ in }

    func configure(
        setAppSection: @escaping (AppSection) -> Void,
        setStatusMessage: @escaping (String) -> Void
    ) {
        self.setAppSection = setAppSection
        self.setStatusMessage = setStatusMessage
    }

    func send(_ event: EditorWorkspaceEvent) {
        perform(state.applying(event))
    }

    var shortcutsHelpBinding: Binding<Bool> {
        Binding(
            get: { self.state.isShortcutsHelpPresented },
            set: { self.send(.shortcutsHelpPresented($0)) }
        )
    }

    func canUndo(kind: EditorMediaKind?) -> Bool {
        guard state.selectedSection == .editor else { return false }
        switch kind {
        case .video:
            return timeline.canUndo
        case .screenshot:
            return screenshot.canUndo
        case nil:
            return false
        }
    }

    func canRedo(kind: EditorMediaKind?) -> Bool {
        guard state.selectedSection == .editor else { return false }
        switch kind {
        case .video:
            return timeline.canRedo
        case .screenshot:
            return screenshot.canRedo
        case nil:
            return false
        }
    }

    @discardableResult
    func undoActiveEditor(kind: EditorMediaKind?) -> Bool {
        guard canUndo(kind: kind) else { return false }
        send(.undoRequested(kind))
        return true
    }

    @discardableResult
    func redoActiveEditor(kind: EditorMediaKind?) -> Bool {
        guard canRedo(kind: kind) else { return false }
        send(.redoRequested(kind))
        return true
    }

    private func perform(_ effects: [EditorWorkspaceEffect]) {
        for effect in effects {
            switch effect {
            case .setAppSection(let section):
                setAppSection(section)
            case .setStatusMessage(let message):
                setStatusMessage(message)
            case .undoTimeline:
                timeline.undo()
            case .redoTimeline:
                timeline.redo()
            case .undoScreenshot:
                screenshot.undo()
            case .redoScreenshot:
                screenshot.redo()
            case .clearTimelineSelection:
                timeline.clearSelection()
            }
        }
    }
}
