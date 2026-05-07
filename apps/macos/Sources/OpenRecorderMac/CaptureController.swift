import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum CaptureControllerError: LocalizedError {
    case unsupportedSource
    case recordingAlreadyRunning
    case noActiveRecording
    case commandFailed(String)
    case screenRecordingPermissionDenied

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "That source cannot be captured yet."
        case .recordingAlreadyRunning:
            "A recording is already running."
        case .noActiveRecording:
            "No recording is currently running."
        case .commandFailed(let message):
            message
        case .screenRecordingPermissionDenied:
            "Screen Recording permission is required. If Open Recorder is already enabled, toggle it off and on in System Settings after rebuilding, then relaunch the app."
        }
    }
}

@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var sources: [CaptureSource] = []
    @Published private(set) var isRecording = false
    @Published private(set) var activeRecordingURL: URL?

    private var recordingProcess: Process?
    private var nativeRecorder: NativeScreenRecorder?

    func reloadSources() async {
        do {
            let content = try await shareableContent()
            var nextSources = await displaySources(from: content)
            nextSources.append(contentsOf: await windowSources(from: content))
            sources = nextSources
        } catch {
            var nextSources = legacyDisplaySources()
            nextSources.append(contentsOf: legacyWindowSources())
            sources = nextSources
        }
    }

    func startRecording(
        source: CaptureSource,
        outputURL: URL,
        includeMicrophone: Bool,
        showCursor: Bool,
        showClicks: Bool
    ) async throws {
        guard !isRecording else { throw CaptureControllerError.recordingAlreadyRunning }
        try ensureScreenRecordingPermission()

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if source.kind == .display || source.kind == .window {
            let recorder = NativeScreenRecorder()
            try await recorder.start(
                source: source,
                outputURL: outputURL,
                includeMicrophone: includeMicrophone,
                showCursor: showCursor,
                showClicks: showClicks
            )
            nativeRecorder = recorder
            activeRecordingURL = outputURL
            isRecording = true
            return
        }

        var arguments = ["-x", "-v"]
        if showCursor {
            arguments.append("-C")
        }
        if includeMicrophone {
            arguments.append("-g")
        }
        if showClicks {
            arguments.append("-k")
        }
        arguments.append(contentsOf: argumentsForSource(source, interactiveAreaMode: "video"))
        arguments.append(outputURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.standardError = Pipe()
        try process.run()

        recordingProcess = process
        activeRecordingURL = outputURL
        isRecording = true
    }

    func stopRecording() async throws -> URL {
        guard let outputURL = activeRecordingURL else {
            throw CaptureControllerError.noActiveRecording
        }

        if let nativeRecorder {
            try await nativeRecorder.stop()
            self.nativeRecorder = nil
            activeRecordingURL = nil
            isRecording = false
            return outputURL
        }

        guard let process = recordingProcess else {
            throw CaptureControllerError.noActiveRecording
        }

        process.interrupt()
        if process.isRunning {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                if process.isRunning {
                    process.terminate()
                }
            }
            process.waitUntilExit()
        }

        recordingProcess = nil
        activeRecordingURL = nil
        isRecording = false

        return outputURL
    }

    func takeScreenshot(source: CaptureSource, outputURL: URL) throws {
        try ensureScreenRecordingPermission()

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var arguments = ["-x"]
        arguments.append(contentsOf: argumentsForSource(source, interactiveAreaMode: "selection"))
        arguments.append(outputURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CaptureControllerError.commandFailed(message ?? "Screenshot capture failed or was cancelled.")
        }
    }

    private func ensureScreenRecordingPermission() throws {
        if CGPreflightScreenCaptureAccess() {
            return
        }

        if CGRequestScreenCaptureAccess() {
            return
        }

        throw CaptureControllerError.screenRecordingPermissionDenied
    }

    private func argumentsForSource(_ source: CaptureSource, interactiveAreaMode: String) -> [String] {
        switch source.kind {
        case .display:
            return source.displayIndex.map { ["-D\($0)"] } ?? []
        case .window:
            return source.windowID.map { ["-l\($0)"] } ?? []
        case .area:
            if interactiveAreaMode == "video" {
                return ["-i", "-Jvideo"]
            }
            return ["-i", "-s"]
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            ) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: CaptureControllerError.unsupportedSource)
                }
            }
        }
    }

    private func displaySources(from content: SCShareableContent) async -> [CaptureSource] {
        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (UInt32, NSScreen)? in
            guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
                return nil
            }
            return (displayID, screen)
        })

        var displaySources: [CaptureSource] = []
        for (index, display) in content.displays.enumerated() {
            let displayIndex = index + 1
            let screen = screensByID[display.displayID]
            displaySources.append(CaptureSource(
                id: "display:\(displayIndex)",
                kind: .display,
                name: screen?.localizedName ?? "Display \(displayIndex)",
                subtitle: "\(display.width) x \(display.height)",
                displayIndex: displayIndex,
                displayID: display.displayID,
                windowID: nil,
                thumbnailData: await thumbnailDataForDisplay(display)
            ))
        }
        return displaySources
    }

    private func windowSources(from content: SCShareableContent) async -> [CaptureSource] {
        let currentProcessName = ProcessInfo.processInfo.processName
        var windowSources: [CaptureSource] = []
        for window in content.windows {
            let owner = window.owningApplication?.applicationName ?? "Window"
            guard owner != currentProcessName else {
                continue
            }

            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = title?.isEmpty == false ? title! : owner
            guard !name.isEmpty else { continue }

            windowSources.append(CaptureSource(
                id: "window:\(window.windowID)",
                kind: .window,
                name: name,
                subtitle: owner,
                displayIndex: nil,
                displayID: nil,
                windowID: window.windowID,
                thumbnailData: await thumbnailDataForWindow(window)
            ))
        }
        return windowSources
    }

    private func legacyDisplaySources() -> [CaptureSource] {
        NSScreen.screens.enumerated().map { index, screen in
            let displayIndex = index + 1
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value
            let frame = screen.frame
            return CaptureSource(
                id: "display:\(displayIndex)",
                kind: .display,
                name: screen.localizedName,
                subtitle: "\(Int(frame.width)) x \(Int(frame.height))",
                displayIndex: displayIndex,
                displayID: displayID,
                windowID: nil,
                thumbnailData: nil
            )
        }
    }

    private func legacyWindowSources() -> [CaptureSource] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentProcessName = ProcessInfo.processInfo.processName
        return rawWindows.compactMap { window in
            guard let windowNumber = window[kCGWindowNumber as String] as? NSNumber,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  owner != currentProcessName else {
                return nil
            }
            let windowID = windowNumber.uint32Value

            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard layer == 0, alpha > 0 else { return nil }

            let title = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = title?.isEmpty == false ? title! : owner

            guard !name.isEmpty else { return nil }

            return CaptureSource(
                id: "window:\(windowID)",
                kind: .window,
                name: name,
                subtitle: owner,
                displayIndex: nil,
                displayID: nil,
                windowID: windowID,
                thumbnailData: nil
            )
        }
    }

    private func thumbnailDataForDisplay(_ display: SCDisplay) async -> Data? {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let size = thumbnailSize(sourceWidth: display.width, sourceHeight: display.height)
        return await thumbnailData(contentFilter: filter, size: size, ignoreWindowShadow: false)
    }

    private func thumbnailDataForWindow(_ window: SCWindow) async -> Data? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let size = thumbnailSize(
            sourceWidth: max(Int(window.frame.width), 1),
            sourceHeight: max(Int(window.frame.height), 1)
        )
        return await thumbnailData(contentFilter: filter, size: size, ignoreWindowShadow: true)
    }

    private func thumbnailData(contentFilter: SCContentFilter, size: CGSize, ignoreWindowShadow: Bool) async -> Data? {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(size.width), 1)
        configuration.height = max(Int(size.height), 1)
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.shouldBeOpaque = true
        configuration.ignoreShadowsSingleWindow = ignoreWindowShadow
        configuration.ignoreShadowsDisplay = ignoreWindowShadow
        configuration.backgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1).cgColor

        guard let image = try? await captureImage(contentFilter: contentFilter, configuration: configuration) else {
            return nil
        }
        return thumbnailData(from: image, maxSize: CGSize(width: 320, height: 180))
    }

    private func captureImage(contentFilter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: CaptureControllerError.unsupportedSource)
                }
            }
        }
    }

    private func thumbnailSize(sourceWidth: Int, sourceHeight: Int) -> CGSize {
        let maxSize = CGSize(width: 320, height: 180)
        let width = max(CGFloat(sourceWidth), 1)
        let height = max(CGFloat(sourceHeight), 1)
        let scale = min(maxSize.width / width, maxSize.height / height, 1)
        return CGSize(width: max(1, width * scale), height: max(1, height * scale))
    }

    private func thumbnailData(from image: CGImage, maxSize: CGSize) -> Data? {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let scale = min(maxSize.width / sourceSize.width, maxSize.height / sourceSize.height, 1)
        let targetSize = CGSize(width: max(1, sourceSize.width * scale), height: max(1, sourceSize.height * scale))
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSImage(cgImage: image, size: sourceSize).draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: CGRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()

        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }
}
