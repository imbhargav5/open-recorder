@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum NativeScreenRecorderError: LocalizedError {
    case missingDisplay
    case missingWindow
    case windowIdentityChanged(expected: String?, actual: String?)
    case unsupportedSource
    case recordingOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .missingDisplay:
            return "The selected display is no longer available. Refresh sources and pick again."
        case .missingWindow:
            return "The selected window is no longer available. Refresh sources and pick again."
        case .windowIdentityChanged(let expected, let actual):
            let expectedLabel = expected ?? "the selected window"
            let actualLabel = actual.map { " (now belongs to \($0))" } ?? ""
            return "The selected window has been replaced\(actualLabel). Refresh sources and pick \(expectedLabel) again."
        case .unsupportedSource:
            return "Selected-area video recording is not implemented in the native recorder yet."
        case .recordingOutputUnavailable:
            return "ScreenCaptureKit recording output is not available on this macOS version."
        }
    }
}

@MainActor
final class NativeScreenRecorder: NSObject {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var recordingDelegate: RecordingOutputDelegate?

    func start(
        source: CaptureSource,
        outputURL: URL,
        options: RecordingCaptureOptions
    ) async throws {
        let content = try await shareableContent()
        let filterAndSize = try makeFilter(for: source, from: content)

        let configuration = SCStreamConfiguration()
        configuration.width = filterAndSize.width
        configuration.height = filterAndSize.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.showsCursor = options.showCursor
        configuration.capturesAudio = options.includeSystemAudio
        configuration.captureMicrophone = options.includeMicrophone
        configuration.microphoneCaptureDeviceID = options.microphoneDeviceID
        configuration.shouldBeOpaque = true
        configuration.captureDynamicRange = .SDR
        configuration.showMouseClicks = options.showClicks
        if let sourceRect = filterAndSize.sourceRect {
            configuration.sourceRect = sourceRect
        }

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let recordingDelegate = RecordingOutputDelegate()
        let recordingOutput = SCRecordingOutput(
            configuration: outputConfiguration,
            delegate: recordingDelegate
        )
        let stream = SCStream(
            filter: filterAndSize.filter,
            configuration: configuration,
            delegate: nil
        )

        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.recordingDelegate = recordingDelegate

        try await startCapture(stream)
        try await recordingDelegate.waitForStart()
    }

    func stop() async throws {
        guard let stream else {
            return
        }

        try await stopCapture(stream)
        try await recordingDelegate?.waitForFinish()

        self.stream = nil
        self.recordingOutput = nil
        self.recordingDelegate = nil
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
                    continuation.resume(throwing: NativeScreenRecorderError.unsupportedSource)
                }
            }
        }
    }

    private func makeFilter(
        for source: CaptureSource,
        from content: SCShareableContent
    ) throws -> (filter: SCContentFilter, width: Int, height: Int, sourceRect: CGRect?) {
        switch source.kind {
        case .display:
            guard let displayID = source.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw NativeScreenRecorderError.missingDisplay
            }
            return (
                SCContentFilter(display: display, excludingWindows: []),
                max(display.width, 640),
                max(display.height, 360),
                nil
            )

        case .window:
            guard let window = resolveWindow(for: source, in: content) else {
                throw NativeScreenRecorderError.missingWindow
            }
            try verifyWindowIdentity(source: source, window: window)
            let width = max(Int(window.frame.width), 640)
            let height = max(Int(window.frame.height), 360)
            return (
                SCContentFilter(desktopIndependentWindow: window),
                width,
                height,
                nil
            )

        case .area:
            guard let area = source.area else {
                throw NativeScreenRecorderError.unsupportedSource
            }
            let displayID = area.displayID ?? source.displayID
            let display = displayID.flatMap { id in
                content.displays.first(where: { $0.displayID == id })
            } ?? content.displays.first
            guard let display else {
                throw NativeScreenRecorderError.missingDisplay
            }

            let sourceRect = sourceRect(for: area, display: display)
            return (
                SCContentFilter(display: display, excludingWindows: []),
                max(Int(sourceRect.width.rounded()), 2),
                max(Int(sourceRect.height.rounded()), 2),
                sourceRect
            )
        }
    }

    private func resolveWindow(for source: CaptureSource, in content: SCShareableContent) -> SCWindow? {
        if let windowID = source.windowID,
           let window = content.windows.first(where: { $0.windowID == windowID }) {
            if let expectedBundleID = source.ownerBundleID,
               let actualBundleID = window.owningApplication?.bundleIdentifier,
               expectedBundleID != actualBundleID {
                if let recovered = findWindowByIdentity(source: source, in: content) {
                    return recovered
                }
                return window
            }
            return window
        }

        return findWindowByIdentity(source: source, in: content)
    }

    private func findWindowByIdentity(source: CaptureSource, in content: SCShareableContent) -> SCWindow? {
        guard let bundleID = source.ownerBundleID else {
            return nil
        }
        return content.windows.first {
            $0.owningApplication?.bundleIdentifier == bundleID && $0.title == source.name
        }
    }

    private func verifyWindowIdentity(source: CaptureSource, window: SCWindow) throws {
        guard let expectedBundleID = source.ownerBundleID else {
            return
        }
        let actualBundleID = window.owningApplication?.bundleIdentifier
        guard expectedBundleID != actualBundleID else {
            return
        }
        throw NativeScreenRecorderError.windowIdentityChanged(
            expected: source.ownerName ?? source.name,
            actual: window.owningApplication?.applicationName
        )
    }

    private func sourceRect(for area: CaptureArea, display: SCDisplay) -> CGRect {
        guard let screen = NSScreen.screen(displayID: display.displayID) else {
            return CGRect(
                x: area.x,
                y: area.y,
                width: max(area.width, 1),
                height: max(area.height, 1)
            )
        }

        let frame = screen.frame
        let scaleX = CGFloat(display.width) / max(frame.width, 1)
        let scaleY = CGFloat(display.height) / max(frame.height, 1)
        let localX = CGFloat(area.x) - frame.minX
        let localBottomY = CGFloat(area.y) - frame.minY
        let width = CGFloat(area.width) * scaleX
        let height = CGFloat(area.height) * scaleY
        let topY = (frame.height - localBottomY - CGFloat(area.height)) * scaleY

        return CGRect(
            x: max(0, localX * scaleX),
            y: max(0, topY),
            width: max(width, 2),
            height: max(height, 2)
        )
    }

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

@available(macOS 15.0, *)
private final class RecordingOutputDelegate: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var didStart = false
    private var didFinish = false
    private var failure: Error?

    func waitForStart() async throws {
        if let failure {
            throw failure
        }
        if didStart {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    func waitForFinish() async throws {
        if let failure {
            throw failure
        }
        if didFinish {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func fail(_ error: Error) {
        failure = error
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        didFinish = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        fail(error)
    }
}
