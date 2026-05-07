@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum NativeScreenRecorderError: LocalizedError {
    case missingDisplay
    case missingWindow
    case unsupportedSource
    case recordingOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .missingDisplay:
            "The selected display is no longer available."
        case .missingWindow:
            "The selected window is no longer available."
        case .unsupportedSource:
            "Selected-area video recording is not implemented in the native recorder yet."
        case .recordingOutputUnavailable:
            "ScreenCaptureKit recording output is not available on this macOS version."
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
        includeMicrophone: Bool,
        showCursor: Bool,
        showClicks: Bool
    ) async throws {
        let content = try await shareableContent()
        let filterAndSize = try makeFilter(for: source, from: content)

        let configuration = SCStreamConfiguration()
        configuration.width = filterAndSize.width
        configuration.height = filterAndSize.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.showsCursor = showCursor
        configuration.capturesAudio = false
        configuration.captureMicrophone = includeMicrophone
        configuration.shouldBeOpaque = true
        configuration.captureDynamicRange = .SDR
        configuration.showMouseClicks = showClicks

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
    ) throws -> (filter: SCContentFilter, width: Int, height: Int) {
        switch source.kind {
        case .display:
            guard let displayID = source.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw NativeScreenRecorderError.missingDisplay
            }
            return (
                SCContentFilter(display: display, excludingWindows: []),
                max(display.width, 640),
                max(display.height, 360)
            )

        case .window:
            guard let windowID = source.windowID,
                  let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw NativeScreenRecorderError.missingWindow
            }
            let width = max(Int(window.frame.width), 640)
            let height = max(Int(window.frame.height), 360)
            return (
                SCContentFilter(desktopIndependentWindow: window),
                width,
                height
            )

        case .area:
            throw NativeScreenRecorderError.unsupportedSource
        }
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
