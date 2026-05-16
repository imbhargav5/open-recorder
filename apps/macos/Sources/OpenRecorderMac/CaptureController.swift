import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum CaptureControllerError: LocalizedError {
    case unsupportedSource
    case recordingAlreadyRunning
    case noActiveRecording
    case commandFailed(String)
    case screenRecordingPermissionRequired
    case screenRecordingPermissionUnavailableAfterRequest

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
        case .screenRecordingPermissionRequired:
            "Screen Recording permission is required. Enable Open Recorder in System Settings, then quit and reopen the app."
        case .screenRecordingPermissionUnavailableAfterRequest:
            "Screen Recording permission is still unavailable. If Open Recorder is already enabled in System Settings, quit and reopen the app."
        }
    }
}

struct WindowSourceMetadata: Equatable {
    var title: String?
    var ownerName: String?
    var bundleIdentifier: String?
    var frame: CGRect
    var layer: Int?
    var alpha: Double?
}

struct WindowSourceDisplayInfo: Equatable {
    var name: String
    var subtitle: String
}

enum ScreencaptureRegionMapper {
    @MainActor
    static func screencaptureArea(from area: CaptureArea) -> CaptureArea {
        screencaptureArea(from: area, primaryDisplayFrame: primaryDisplayFrame())
    }

    static func screencaptureArea(
        from area: CaptureArea,
        primaryDisplayFrame: CGRect
    ) -> CaptureArea {
        CaptureArea(
            x: area.x,
            y: Int((primaryDisplayFrame.maxY - CGFloat(area.y + area.height)).rounded()),
            width: area.width,
            height: area.height,
            displayID: area.displayID
        )
    }

    static func regionArgument(forDisplayBounds bounds: CGRect) -> String? {
        guard !bounds.isEmpty else { return nil }
        return "-R\(Int(bounds.origin.x.rounded())),\(Int(bounds.origin.y.rounded())),\(Int(bounds.width.rounded())),\(Int(bounds.height.rounded()))"
    }

    @MainActor
    private static func primaryDisplayFrame() -> CGRect {
        NSScreen.screens.first { screen in
            screen.frame.origin == .zero
        }?.frame ?? NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? .zero
    }
}

enum WindowSourceFilter {
    static func displayInfo(
        for metadata: WindowSourceMetadata,
        currentProcessName: String,
        currentApplicationName: String? = nil,
        currentBundleIdentifier: String? = nil
    ) -> WindowSourceDisplayInfo? {
        let title = cleaned(metadata.title)
        let ownerName = cleaned(metadata.ownerName)
        let bundleIdentifier = cleaned(metadata.bundleIdentifier)
        let currentApplicationNames = [
            cleaned(currentProcessName),
            cleaned(currentApplicationName)
        ].compactMap(\.self)

        if let ownerName,
           currentApplicationNames.contains(where: { ownerName.caseInsensitiveCompare($0) == .orderedSame }) {
            return nil
        }

        if let bundleIdentifier,
           let currentBundleIdentifier = cleaned(currentBundleIdentifier),
           bundleIdentifier.caseInsensitiveCompare(currentBundleIdentifier) == .orderedSame {
            return nil
        }

        if let layer = metadata.layer, layer != 0 {
            return nil
        }

        if let alpha = metadata.alpha, alpha <= 0.05 {
            return nil
        }

        guard metadata.frame.width >= 96, metadata.frame.height >= 64 else {
            return nil
        }

        guard !isBlockedSystemWindow(title: title, ownerName: ownerName, bundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let titleName = title.flatMap { isBundleLikeIdentifier($0) ? nil : $0 }
        let ownerNameForDisplay = ownerName.flatMap { isBundleLikeIdentifier($0) ? nil : $0 }
        guard let name = titleName ?? ownerNameForDisplay else {
            return nil
        }

        return WindowSourceDisplayInfo(
            name: name,
            subtitle: ownerNameForDisplay ?? "Window"
        )
    }

    private static let blockedOwnerNames: Set<String> = [
        "control center",
        "dock",
        "loginwindow",
        "notification center",
        "spotlight",
        "systemuiserver",
        "textinputmenuagent",
        "wallpaper",
        "window server"
    ]

    private static let blockedTitleNames: Set<String> = [
        "control center",
        "notification center",
        "spotlight"
    ]

    private static let blockedBundlePrefixes = [
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.notificationcenterui",
        "com.apple.spotlight",
        "com.apple.systemuiserver",
        "com.apple.textinputmenuagent",
        "com.apple.wallpaper",
        "com.apple.windowmanager"
    ]

    private static func isBlockedSystemWindow(
        title: String?,
        ownerName: String?,
        bundleIdentifier: String?
    ) -> Bool {
        if let ownerName, blockedOwnerNames.contains(ownerName.lowercased()) {
            return true
        }

        if let title, blockedTitleNames.contains(title.lowercased()) {
            return true
        }

        if let bundleIdentifier {
            let normalizedBundleIdentifier = bundleIdentifier.lowercased()
            return blockedBundlePrefixes.contains { normalizedBundleIdentifier.hasPrefix($0) }
        }

        return false
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func isBundleLikeIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count >= 3 else {
            return false
        }

        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_"
            }
        }
    }
}

@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var sources: [CaptureSource] = []
    @Published private(set) var isRecording = false
    @Published private(set) var activeRecordingURL: URL?

    private let screenRecordingPermission: ScreenRecordingPermission
    private var recordingProcess: Process?
    private var nativeRecorder: NativeScreenRecorder?
    private var activeStagedRecordingURL: URL?

    init(screenRecordingPermission: ScreenRecordingPermission = ScreenRecordingPermission()) {
        self.screenRecordingPermission = screenRecordingPermission
    }

    #if DEBUG
    func setRecordingForTesting(_ isRecording: Bool) {
        self.isRecording = isRecording
    }

    func setSourcesForTesting(_ sources: [CaptureSource]) {
        self.sources = sources
    }

    func ensureScreenRecordingPermissionForTesting() throws {
        try ensureScreenRecordingPermission()
    }
    #endif

    func reloadSources(requestScreenRecordingPermission: Bool = false) async {
        guard canLoadPreviewSources(requestScreenRecordingPermission: requestScreenRecordingPermission) else {
            var nextSources = legacyDisplaySources()
            nextSources.append(contentsOf: legacyWindowSources())
            sources = nextSources
            return
        }

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
        options: RecordingCaptureOptions
    ) async throws {
        guard !isRecording else { throw CaptureControllerError.recordingAlreadyRunning }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if source.kind == .display || source.kind == .window || source.kind == .area {
            try ensureScreenRecordingPermission()
            do {
                try await startNativeRecording(
                    source: source,
                    outputURL: outputURL,
                    options: options
                )
            } catch {
                guard isLikelyScreenRecordingPermissionError(error) else {
                    throw error
                }

                try ensureScreenRecordingPermission()
                try await startNativeRecording(
                    source: source,
                    outputURL: outputURL,
                    options: options
                )
            }
            return
        }

        try ensureScreenRecordingPermission()

        var arguments = ["-x", "-v"]
        if options.includeMicrophone {
            arguments.append("-g")
        }
        if options.showClicks {
            arguments.append("-k")
        }
        arguments.append(contentsOf: argumentsForSource(source, interactiveAreaMode: "video"))
        arguments.append(outputURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()

        try await Task.sleep(nanoseconds: 300_000_000)
        if !process.isRunning {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CaptureControllerError.commandFailed(message ?? "Recording capture failed or was cancelled.")
        }

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
            try finalizeStagedRecording()
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
        try finalizeStagedRecording()
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
        switch screenRecordingPermission.requestGrant() {
        case .granted:
            return
        case .promptAlreadyShown:
            throw CaptureControllerError.screenRecordingPermissionUnavailableAfterRequest
        case .promptShownWithoutGrant:
            throw CaptureControllerError.screenRecordingPermissionRequired
        }
    }

    private func hasScreenRecordingPermission() -> Bool {
        screenRecordingPermission.currentState() == .granted
    }

    private func canLoadPreviewSources(requestScreenRecordingPermission: Bool) -> Bool {
        guard !hasScreenRecordingPermission() else {
            return true
        }

        guard requestScreenRecordingPermission else {
            return false
        }

        return screenRecordingPermission.requestGrant(allowRepeatedRequest: true) == .granted
    }

    private func startNativeRecording(
        source: CaptureSource,
        outputURL: URL,
        options: RecordingCaptureOptions
    ) async throws {
        let recorder = NativeScreenRecorder()
        let stagedURL = stagedRecordingURL(for: outputURL)
        try await recorder.start(
            source: source,
            outputURL: stagedURL,
            options: options
        )
        nativeRecorder = recorder
        activeRecordingURL = outputURL
        activeStagedRecordingURL = stagedURL
        isRecording = true
    }

    private func stagedRecordingURL(for outputURL: URL) -> URL {
        outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).partial.mp4")
    }

    private func finalizeStagedRecording() throws {
        guard let stagedURL = activeStagedRecordingURL,
              let outputURL = activeRecordingURL else {
            activeStagedRecordingURL = nil
            return
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: stagedURL, to: outputURL)
        activeStagedRecordingURL = nil
    }

    private func isLikelyScreenRecordingPermissionError(_ error: Error) -> Bool {
        if error is NativeScreenRecorderError {
            return false
        }

        let nsError = error as NSError
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let searchableText = [
            nsError.domain,
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion,
            underlyingError?.domain,
            underlyingError?.localizedDescription
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        let permissionTerms = [
            "permission",
            "screen recording",
            "not authorized",
            "not authorised",
            "denied",
            "declined",
            "tcc"
        ]
        if permissionTerms.contains(where: { searchableText.contains($0) }) {
            return true
        }

        return searchableText.contains("screencapturekit") && !CGPreflightScreenCaptureAccess()
    }

    private func argumentsForSource(_ source: CaptureSource, interactiveAreaMode: String) -> [String] {
        switch source.kind {
        case .display:
            if let displayID = source.displayID,
               let regionArg = ScreencaptureRegionMapper.regionArgument(forDisplayBounds: CGDisplayBounds(displayID)) {
                return [regionArg]
            }
            return source.displayIndex.map { ["-D\($0)"] } ?? []
        case .window:
            return source.windowID.map { ["-l\($0)"] } ?? []
        case .area:
            if let area = source.area {
                let screencaptureArea = ScreencaptureRegionMapper.screencaptureArea(from: area)
                return ["-R\(screencaptureArea.x),\(screencaptureArea.y),\(screencaptureArea.width),\(screencaptureArea.height)"]
            }
            if interactiveAreaMode == "video" {
                return ["-Jvideo"]
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
                id: "display:\(display.displayID)",
                kind: .display,
                name: screen?.localizedName ?? "Display \(displayIndex)",
                subtitle: "\(display.width) x \(display.height)",
                displayIndex: displayIndex,
                displayID: display.displayID,
                windowID: nil,
                area: nil,
                thumbnailData: await thumbnailDataForDisplay(display)
            ))
        }
        return displaySources
    }

    private func windowSources(from content: SCShareableContent) async -> [CaptureSource] {
        let currentProcessName = ProcessInfo.processInfo.processName
        let currentApplicationName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        var windowSources: [CaptureSource] = []
        for window in content.windows {
            let metadata = WindowSourceMetadata(
                title: window.title,
                ownerName: window.owningApplication?.applicationName,
                bundleIdentifier: window.owningApplication?.bundleIdentifier,
                frame: window.frame,
                layer: nil,
                alpha: nil
            )
            guard let displayInfo = WindowSourceFilter.displayInfo(
                for: metadata,
                currentProcessName: currentProcessName,
                currentApplicationName: currentApplicationName,
                currentBundleIdentifier: currentBundleIdentifier
            ) else { continue }

            windowSources.append(CaptureSource(
                id: "window:\(window.windowID)",
                kind: .window,
                name: displayInfo.name,
                subtitle: displayInfo.subtitle,
                displayIndex: nil,
                displayID: nil,
                windowID: window.windowID,
                area: nil,
                thumbnailData: await thumbnailDataForWindow(window),
                ownerBundleID: window.owningApplication?.bundleIdentifier,
                ownerName: window.owningApplication?.applicationName
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
                id: displayID.map { "display:\($0)" } ?? "display:\(displayIndex)",
                kind: .display,
                name: screen.localizedName,
                subtitle: "\(Int(frame.width)) x \(Int(frame.height))",
                displayIndex: displayIndex,
                displayID: displayID,
                windowID: nil,
                area: nil,
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
        let currentApplicationName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        return rawWindows.compactMap { window in
            guard let windowNumber = window[kCGWindowNumber as String] as? NSNumber else {
                return nil
            }
            let windowID = windowNumber.uint32Value
            let ownerName = window[kCGWindowOwnerName as String] as? String
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let runningApp = ownerPID.flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
            let bundleID = runningApp?.bundleIdentifier

            let metadata = WindowSourceMetadata(
                title: window[kCGWindowName as String] as? String,
                ownerName: ownerName,
                bundleIdentifier: bundleID,
                frame: legacyWindowFrame(from: window),
                layer: (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                alpha: (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
            )
            guard let displayInfo = WindowSourceFilter.displayInfo(
                for: metadata,
                currentProcessName: currentProcessName,
                currentApplicationName: currentApplicationName,
                currentBundleIdentifier: currentBundleIdentifier
            ) else { return nil }

            return CaptureSource(
                id: "window:\(windowID)",
                kind: .window,
                name: displayInfo.name,
                subtitle: displayInfo.subtitle,
                displayIndex: nil,
                displayID: nil,
                windowID: windowID,
                area: nil,
                thumbnailData: nil,
                ownerBundleID: bundleID,
                ownerName: ownerName
            )
        }
    }

    private func legacyWindowFrame(from window: [String: Any]) -> CGRect {
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else {
            return .zero
        }

        let x = (bounds["X"] as? NSNumber)?.doubleValue ?? 0
        let y = (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
        let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
        let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
        return CGRect(x: x, y: y, width: width, height: height)
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

        let image: CGImage
        do {
            image = try await captureImage(contentFilter: contentFilter, configuration: configuration)
        } catch {
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
