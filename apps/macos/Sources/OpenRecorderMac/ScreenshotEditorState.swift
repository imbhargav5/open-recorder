import AppKit
import Foundation
import Observation
import SwiftUI

struct ScreenshotEditorState: Codable, Equatable, Hashable {
    var background: BackgroundStyle = BackgroundPresets.default
    var padding = 56.0
    var backgroundRoundness = 28.0
    var backgroundShadow = 0.0
    var imageRoundness = 10.0
    var imageShadow = 0.45

    static let `default` = ScreenshotEditorState()

    init(
        background: BackgroundStyle = BackgroundPresets.default,
        padding: Double = 56.0,
        backgroundRoundness: Double = 28.0,
        backgroundShadow: Double = 0.0,
        imageRoundness: Double = 10.0,
        imageShadow: Double = 0.45
    ) {
        self.background = background
        self.padding = padding
        self.backgroundRoundness = backgroundRoundness
        self.backgroundShadow = backgroundShadow
        self.imageRoundness = imageRoundness
        self.imageShadow = imageShadow
    }

    private enum CodingKeys: String, CodingKey {
        case background
        case padding
        case backgroundRoundness
        case backgroundShadow
        case imageRoundness
        case imageShadow
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = try container.decodeIfPresent(BackgroundStyle.self, forKey: .background) ?? defaults.background
        padding = try container.decodeIfPresent(Double.self, forKey: .padding) ?? defaults.padding
        backgroundRoundness = try container.decodeIfPresent(Double.self, forKey: .backgroundRoundness) ?? defaults.backgroundRoundness
        backgroundShadow = try container.decodeIfPresent(Double.self, forKey: .backgroundShadow) ?? defaults.backgroundShadow
        imageRoundness = try container.decodeIfPresent(Double.self, forKey: .imageRoundness) ?? defaults.imageRoundness
        imageShadow = try container.decodeIfPresent(Double.self, forKey: .imageShadow) ?? defaults.imageShadow
    }
}

struct ScreenshotEditorMachineState: Equatable {
    var screenshot = ScreenshotEditorState.default
    var isExportDialogPresented = false
    var appliedScreenshotStateIdentity: String?

    func autosaveSnapshot(
        projectPath: String?,
        screenshotURL: URL?,
        editorTitle: String?
    ) -> ProjectAutosaveSnapshot? {
        guard let projectPath, let screenshotURL else { return nil }
        return ProjectAutosaveSnapshot(
            projectPath: projectPath,
            title: editorTitle ?? EditorMediaKind.screenshot.displayTitle(for: screenshotURL),
            recordingPath: nil,
            screenshotPath: screenshotURL.path,
            sourceName: nil,
            editorState: ProjectEditorState(screenshot: screenshot)
        )
    }
}

enum ScreenshotEditorEvent: Equatable {
    case sessionChanged(ScreenshotEditorSessionContext)
    case styleChanged(ScreenshotEditorState)
    case exportRequested
    case exportDialogDismissed
    case autosaveSnapshotChanged(ProjectAutosaveSnapshot?)
    case disappeared(ProjectAutosaveSnapshot?)
    case saveFailed(String)
    case saveSucceeded(URL)
    case copyFailed(String)
    case copySucceeded
}

enum ScreenshotEditorEffect: Equatable {
    case markAutosaved(ProjectAutosaveSnapshot?)
    case scheduleAutosave(ProjectAutosaveSnapshot?)
    case flushAutosave(ProjectAutosaveSnapshot?)
    case setStatusMessage(String)
}

extension ScreenshotEditorMachineState {
    mutating func applying(_ event: ScreenshotEditorEvent) -> [ScreenshotEditorEffect] {
        switch event {
        case .sessionChanged(let context):
            guard appliedScreenshotStateIdentity != context.identity else { return [] }
            appliedScreenshotStateIdentity = context.identity
            screenshot = context.initialScreenshotState ?? .default
            return [
                .markAutosaved(autosaveSnapshot(
                    projectPath: context.projectPath,
                    screenshotURL: context.screenshotURL,
                    editorTitle: context.editorTitle
                ))
            ]

        case .styleChanged(let nextState):
            guard screenshot != nextState else { return [] }
            screenshot = nextState
            return []

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
final class ScreenshotEditorDriver {
    var state = ScreenshotEditorMachineState()
    private var historyRevision = 0

    @ObservationIgnored private var history = EditorHistory<ScreenshotEditorState>()
    @ObservationIgnored private let autosave = ProjectAutosaveCoordinator()
    @ObservationIgnored private var setStatusMessage: (String) -> Void = { _ in }
    @ObservationIgnored private var renderPNG: (NSImage, ScreenshotEditorState) -> Data? = { image, state in
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: state.background,
            padding: state.padding,
            backgroundRoundness: state.backgroundRoundness,
            backgroundShadow: state.backgroundShadow,
            imageRoundness: state.imageRoundness,
            imageShadow: state.imageShadow
        ))
        return renderer.renderPNG(from: image)
    }
    @ObservationIgnored private var presentSaveURL: (String) -> URL? = { suggestedFileName in
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName
        guard panel.runModal() == .OK, let targetURL = panel.url else { return nil }
        return targetURL.pathExtension.isEmpty ? targetURL.appendingPathExtension("png") : targetURL
    }
    @ObservationIgnored private var writePNG: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }
    @ObservationIgnored private var copyPNG: (Data) -> Bool = { data in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        if let image = NSImage(data: data), let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }
        return true
    }

    var canUndo: Bool {
        _ = historyRevision
        return history.canUndo
    }

    var canRedo: Bool {
        _ = historyRevision
        return history.canRedo
    }

    func configure(
        saveHandler: @escaping ProjectAutosaveCoordinator.SaveHandler,
        statusHandler: @escaping ProjectAutosaveCoordinator.StatusHandler,
        setStatusMessage: @escaping (String) -> Void,
        renderPNG: ((NSImage, ScreenshotEditorState) -> Data?)? = nil,
        presentSaveURL: ((String) -> URL?)? = nil,
        writePNG: ((Data, URL) throws -> Void)? = nil,
        copyPNG: ((Data) -> Bool)? = nil
    ) {
        self.setStatusMessage = setStatusMessage
        if let renderPNG {
            self.renderPNG = renderPNG
        }
        if let presentSaveURL {
            self.presentSaveURL = presentSaveURL
        }
        if let writePNG {
            self.writePNG = writePNG
        }
        if let copyPNG {
            self.copyPNG = copyPNG
        }
        autosave.configure(saveHandler: saveHandler, statusHandler: statusHandler)
    }

    func send(_ event: ScreenshotEditorEvent) {
        let previousScreenshot = state.screenshot
        let effects = state.applying(event)
        if case .sessionChanged = event, previousScreenshot != state.screenshot {
            resetHistory()
        }
        perform(effects)
    }

    func undo() {
        guard let previous = history.undo(current: state.screenshot) else { return }
        state.screenshot = previous
        historyRevision += 1
    }

    func redo() {
        guard let next = history.redo(current: state.screenshot) else { return }
        state.screenshot = next
        historyRevision += 1
    }

    func resetHistory() {
        history.reset()
        historyRevision += 1
    }

    func apply(_ nextState: ScreenshotEditorState) {
        state.screenshot = nextState
        resetHistory()
    }

    func beginUndoTransaction() {
        history.beginTransaction(current: state.screenshot)
    }

    func endUndoTransaction() {
        if history.commitTransaction(current: state.screenshot) {
            historyRevision += 1
        }
    }

    func update<Value: Equatable>(_ keyPath: WritableKeyPath<ScreenshotEditorState, Value>, to value: Value) {
        var next = state.screenshot
        guard next[keyPath: keyPath] != value else { return }
        let before = state.screenshot
        next[keyPath: keyPath] = value
        send(.styleChanged(next))
        history.recordChange(from: before, to: next)
        historyRevision += 1
    }

    func binding<Value: Equatable>(for keyPath: WritableKeyPath<ScreenshotEditorState, Value>) -> Binding<Value> {
        Binding(
            get: { self.state.screenshot[keyPath: keyPath] },
            set: { self.update(keyPath, to: $0) }
        )
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
        editorTitle: String?
    ) -> ProjectAutosaveSnapshot? {
        state.autosaveSnapshot(
            projectPath: projectPath,
            screenshotURL: screenshotURL,
            editorTitle: editorTitle
        )
    }

    func saveComposedPNG(image: NSImage?, suggestedFileName: String) {
        guard let image, let data = renderPNG(image, state.screenshot) else {
            send(.saveFailed("Failed to render screenshot."))
            return
        }

        guard let targetURL = presentSaveURL(suggestedFileName) else { return }

        do {
            try writePNG(data, targetURL)
            send(.saveSucceeded(targetURL))
        } catch {
            send(.saveFailed(error.localizedDescription))
        }
    }

    func copyComposedPNG(image: NSImage?) {
        guard let image, let data = renderPNG(image, state.screenshot) else {
            send(.copyFailed("Failed to render screenshot."))
            return
        }

        if copyPNG(data) {
            send(.copySucceeded)
        } else {
            send(.copyFailed("Failed to copy screenshot."))
        }
    }

    private func perform(_ effects: [ScreenshotEditorEffect]) {
        for effect in effects {
            switch effect {
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
