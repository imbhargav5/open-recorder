import Foundation
import Observation

struct VideoExportState: Equatable {
    var phase: VideoExportPhase = .idle
    var progress = 0.0
    var errorMessage: String?
    var exportedURL: URL?
    var pendingTempURL: URL?
    var pendingSourceURL: URL?
    var pendingOptions: VideoExportOptions?

    var isExporting: Bool {
        phase == .exporting
    }

    var exportedFileName: String? {
        exportedURL?.lastPathComponent
    }
}

enum VideoExportEvent: Equatable {
    case exportRequested(sourceURL: URL?, targetURL: URL, options: VideoExportOptions, edits: TimelineEditSnapshot)
    case progressChanged(Double)
    case renderSucceeded
    case renderFailed(String)
    case retrySaveRequested
    case savePanelCanceled
    case saveSucceeded(URL)
    case saveFailed(String)
    case cancelRequested
    case clearRequested
    case revealRequested
}

enum VideoExportEffect: Equatable {
    case cancelRender
    case deleteFile(URL)
    case render(sourceURL: URL, targetURL: URL, options: VideoExportOptions, edits: TimelineEditSnapshot)
    case presentSavePanel(sourceURL: URL, tempURL: URL, options: VideoExportOptions)
    case copyFile(sourceURL: URL, targetURL: URL, tempURL: URL)
    case reveal(URL)
    case setStatusMessage(String)
}

enum VideoExportCopy {
    static let saveDialogCanceled = "Save dialog canceled. Click Save Again to save without re-rendering."
    static let exportReadyToSave = "Export ready to save."
}

extension VideoExportState {
    mutating func applying(_ event: VideoExportEvent) -> [VideoExportEffect] {
        switch event {
        case .exportRequested(let sourceURL, let targetURL, let options, let edits):
            guard let sourceURL else {
                errorMessage = "Open a recording first."
                phase = .failed
                return [.setStatusMessage("Open a recording first.")]
            }

            var effects: [VideoExportEffect] = [.cancelRender]
            if let pendingTempURL {
                effects.append(.deleteFile(pendingTempURL))
            }

            pendingTempURL = targetURL
            pendingSourceURL = sourceURL
            pendingOptions = options
            exportedURL = nil
            errorMessage = nil
            progress = 0
            phase = .exporting
            effects.append(.setStatusMessage("Exporting \(options.summaryTitle)..."))
            effects.append(.render(sourceURL: sourceURL, targetURL: targetURL, options: options, edits: edits))
            return effects

        case .progressChanged(let value):
            guard phase == .exporting else { return [] }
            progress = VideoExportProgressPresentation.clamped(value)
            return []

        case .renderSucceeded:
            guard let sourceURL = pendingSourceURL,
                  let tempURL = pendingTempURL,
                  let options = pendingOptions else {
                phase = .failed
                errorMessage = "No completed export is waiting to be saved."
                return [.setStatusMessage("No completed export is waiting to be saved.")]
            }
            progress = 1
            phase = .saving
            errorMessage = nil
            return [
                .setStatusMessage("Choose where to save \(options.summaryTitle)."),
                .presentSavePanel(sourceURL: sourceURL, tempURL: tempURL, options: options)
            ]

        case .renderFailed(let message):
            phase = .failed
            errorMessage = message
            return [.setStatusMessage(message)]

        case .retrySaveRequested:
            guard let sourceURL = pendingSourceURL,
                  let tempURL = pendingTempURL,
                  let options = pendingOptions else {
                phase = .failed
                errorMessage = "No completed export is waiting to be saved."
                return [.setStatusMessage("No completed export is waiting to be saved.")]
            }
            phase = .saving
            errorMessage = nil
            return [.presentSavePanel(sourceURL: sourceURL, tempURL: tempURL, options: options)]

        case .savePanelCanceled:
            phase = .savePending
            errorMessage = VideoExportCopy.saveDialogCanceled
            return [.setStatusMessage(VideoExportCopy.exportReadyToSave)]

        case .saveSucceeded(let targetURL):
            pendingTempURL = nil
            pendingSourceURL = nil
            pendingOptions = nil
            exportedURL = targetURL
            errorMessage = nil
            progress = 1
            phase = .success
            return [.setStatusMessage("Exported \(targetURL.lastPathComponent)")]

        case .saveFailed(let message):
            phase = .failed
            errorMessage = message
            return [.setStatusMessage(message)]

        case .cancelRequested:
            guard phase == .exporting else { return [] }
            let tempURL = pendingTempURL
            pendingTempURL = nil
            progress = 0
            phase = .failed
            errorMessage = "Export canceled."
            var effects: [VideoExportEffect] = [.cancelRender, .setStatusMessage("Export canceled.")]
            if let tempURL {
                effects.append(.deleteFile(tempURL))
            }
            return effects

        case .clearRequested:
            let shouldCancel = phase.isBusy
            let tempURL = pendingTempURL
            pendingTempURL = nil
            pendingSourceURL = nil
            pendingOptions = nil
            exportedURL = nil
            errorMessage = nil
            progress = 0
            phase = .idle
            var effects: [VideoExportEffect] = []
            if shouldCancel {
                effects.append(.cancelRender)
            }
            if let tempURL {
                effects.append(.deleteFile(tempURL))
            }
            return effects

        case .revealRequested:
            guard let exportedURL else { return [] }
            return [.reveal(exportedURL)]
        }
    }
}

@Observable
@MainActor
final class VideoExportDriver {
    var state = VideoExportState()

    @ObservationIgnored private var renderVideo: (
        _ sourceURL: URL,
        _ targetURL: URL,
        _ options: VideoExportOptions,
        _ cancellationToken: VideoExportCancellationToken,
        _ edits: TimelineEditSnapshot,
        _ progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws -> Void = { _, _, _, _, _, _ in }
    @ObservationIgnored private var temporaryURL: (VideoExportOptions) -> URL = { options in
        FileManager.default.temporaryDirectory
            .appendingPathComponent("open-recorder-export-\(UUID().uuidString)")
            .appendingPathExtension(options.format.fileExtension)
    }
    @ObservationIgnored private var saveDestination: (URL, VideoExportOptions) -> URL? = { _, _ in nil }
    @ObservationIgnored private var copyFile: (URL, URL) throws -> Void = { sourceURL, targetURL in
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
    }
    @ObservationIgnored private var deleteFile: (URL) -> Void = { url in
        try? FileManager.default.removeItem(at: url)
    }
    @ObservationIgnored private var revealFile: (URL) -> Void = { _ in }
    @ObservationIgnored private var setStatusMessage: (String) -> Void = { _ in }
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var cancellationToken: VideoExportCancellationToken?

    func configure(
        renderVideo: @escaping (
            _ sourceURL: URL,
            _ targetURL: URL,
            _ options: VideoExportOptions,
            _ cancellationToken: VideoExportCancellationToken,
            _ edits: TimelineEditSnapshot,
            _ progressHandler: @escaping @MainActor (Double) -> Void
        ) async throws -> Void,
        temporaryURL: @escaping (VideoExportOptions) -> URL,
        saveDestination: @escaping (URL, VideoExportOptions) -> URL?,
        copyFile: @escaping (URL, URL) throws -> Void,
        deleteFile: @escaping (URL) -> Void,
        revealFile: @escaping (URL) -> Void,
        setStatusMessage: @escaping (String) -> Void
    ) {
        self.renderVideo = renderVideo
        self.temporaryURL = temporaryURL
        self.saveDestination = saveDestination
        self.copyFile = copyFile
        self.deleteFile = deleteFile
        self.revealFile = revealFile
        self.setStatusMessage = setStatusMessage
    }

    func export(sourceURL: URL?, options: VideoExportOptions, edits: TimelineEditSnapshot) {
        send(.exportRequested(
            sourceURL: sourceURL,
            targetURL: temporaryURL(options),
            options: options,
            edits: edits
        ))
    }

    func retrySave() {
        send(.retrySaveRequested)
    }

    func revealExportedFile() {
        send(.revealRequested)
    }

    func cancelExport() {
        send(.cancelRequested)
    }

    func clear() {
        send(.clearRequested)
    }

    func send(_ event: VideoExportEvent) {
        perform(state.applying(event))
    }

    private func perform(_ effects: [VideoExportEffect]) {
        for effect in effects {
            switch effect {
            case .cancelRender:
                exportTask?.cancel()
                exportTask = nil
                cancellationToken?.cancel()
                cancellationToken = nil

            case .deleteFile(let url):
                deleteFile(url)

            case .render(let sourceURL, let targetURL, let options, let edits):
                let token = VideoExportCancellationToken()
                cancellationToken = token
                exportTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await renderVideo(sourceURL, targetURL, options, token, edits) { [weak self] progress in
                            self?.send(.progressChanged(progress))
                        }
                        guard !Task.isCancelled else { return }
                        exportTask = nil
                        cancellationToken = nil
                        send(.renderSucceeded)
                    } catch {
                        guard !Task.isCancelled else { return }
                        exportTask = nil
                        cancellationToken = nil
                        send(.renderFailed(error.localizedDescription))
                    }
                }

            case .presentSavePanel(let sourceURL, let tempURL, let options):
                guard let targetURL = saveDestination(sourceURL, options) else {
                    send(.savePanelCanceled)
                    continue
                }
                perform([.copyFile(sourceURL: sourceURL, targetURL: targetURL, tempURL: tempURL)])

            case .copyFile(_, let targetURL, let tempURL):
                do {
                    try copyFile(tempURL, targetURL)
                    deleteFile(tempURL)
                    send(.saveSucceeded(targetURL))
                } catch {
                    send(.saveFailed(error.localizedDescription))
                }

            case .reveal(let url):
                revealFile(url)

            case .setStatusMessage(let message):
                setStatusMessage(message)
            }
        }
    }
}
