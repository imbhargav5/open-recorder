@preconcurrency import AVFoundation
import Foundation
import os

let facecamLog = Logger(subsystem: "dev.openrecorder.app", category: "facecam")

enum FacecamRecorderError: LocalizedError {
    case cameraUnavailable
    case cannotAddCameraInput
    case cannotAddMovieOutput
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "The selected camera is not available."
        case .cannotAddCameraInput:
            "The selected camera cannot be used for recording."
        case .cannotAddMovieOutput:
            "Facecam recording output is unavailable."
        case .recordingFailed(let message):
            message
        }
    }
}

@MainActor
final class FacecamRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private var session: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var preparedCameraDeviceID: String?
    private var outputURL: URL?
    private var startedAt: Date?
    private var startContinuation: CheckedContinuation<Date, Error>?
    private var finishContinuation: CheckedContinuation<URL?, Error>?
    private var finishResult: Result<URL?, Error>?
    private var preparationGeneration = 0

    var isRecording: Bool {
        movieOutput?.isRecording == true
    }

    var isPrepared: Bool {
        session?.isRunning == true && movieOutput != nil
    }

    var captureSession: AVCaptureSession? {
        session
    }

    func prepare(cameraDeviceID: String?) async throws {
        if preparedCameraDeviceID == cameraDeviceID,
           let session,
           session.isRunning {
            return
        }

        cleanup()
        let generation = preparationGeneration
        let (session, output) = try buildSession(cameraDeviceID: cameraDeviceID)
        facecamLog.notice("prepare(gen=\(generation)) building session for device=\(cameraDeviceID ?? "default", privacy: .public)")

        await Task.detached(priority: .userInitiated) {
            session.startRunning()
        }.value

        guard generation == preparationGeneration else {
            // A newer prepare()/cleanup() call superseded this one while we were
            // suspended on startRunning() — stop the now-orphaned session instead of
            // letting it silently overwrite (and outlive) the current one.
            facecamLog.notice("prepare(gen=\(generation)) superseded by gen=\(self.preparationGeneration); stopping orphaned session")
            session.stopRunning()
            return
        }

        self.session = session
        self.movieOutput = output
        self.preparedCameraDeviceID = cameraDeviceID
        self.finishResult = nil
        facecamLog.notice("prepare(gen=\(generation)) completed, session running=\(session.isRunning, privacy: .public)")
    }

    func start(outputURL: URL, cameraDeviceID: String?) async throws -> Date {
        facecamLog.notice("start() requested for device=\(cameraDeviceID ?? "default", privacy: .public), isPrepared=\(self.isPrepared, privacy: .public)")
        if preparedCameraDeviceID != cameraDeviceID || session == nil || movieOutput == nil {
            try await prepare(cameraDeviceID: cameraDeviceID)
        } else if let session, !session.isRunning {
            await Task.detached(priority: .userInitiated) {
                session.startRunning()
            }.value
        }

        guard let output = movieOutput else {
            facecamLog.error("start() aborting: movieOutput is nil after prepare()")
            throw FacecamRecorderError.cannotAddMovieOutput
        }

        if output.isRecording, let startedAt {
            facecamLog.notice("start() already recording since \(startedAt.description, privacy: .public)")
            return startedAt
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        self.outputURL = outputURL
        self.finishResult = nil

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            output.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    private func buildSession(cameraDeviceID: String?) throws -> (AVCaptureSession, AVCaptureMovieFileOutput) {
        let device = try cameraDevice(cameraDeviceID)
        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard session.canAddInput(input) else {
            throw FacecamRecorderError.cannotAddCameraInput
        }
        session.addInput(input)

        let output = AVCaptureMovieFileOutput()
        guard session.canAddOutput(output) else {
            throw FacecamRecorderError.cannotAddMovieOutput
        }
        session.addOutput(output)

        return (session, output)
    }

    func stop() async throws -> URL? {
        guard let output = movieOutput, output.isRecording else {
            facecamLog.notice("stop() called while not recording (movieOutput=\(self.movieOutput != nil, privacy: .public)); returning outputURL=\(self.outputURL?.lastPathComponent ?? "nil", privacy: .public)")
            let url = outputURL
            cleanup()
            return url
        }

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            output.stopRecording()
        }
    }

    func cancel() {
        if movieOutput?.isRecording == true {
            movieOutput?.stopRecording()
        }
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        finishContinuation?.resume(throwing: CancellationError())
        finishContinuation = nil
        cleanup()
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            self.finishStartRecording()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.finishRecording(outputFileURL: outputFileURL, error: error)
        }
    }

    private func finishStartRecording() {
        let start = Date()
        startedAt = start
        startContinuation?.resume(returning: start)
        startContinuation = nil
    }

    private func finishRecording(outputFileURL: URL, error: Error?) {
        let isSuccess: Bool
        if let error = error as NSError? {
            let successfullyFinished = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
                ?? (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? NSNumber)?.boolValue
                ?? false
            let fileExists = FileManager.default.fileExists(atPath: outputFileURL.path)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int64) ?? 0
            isSuccess = successfullyFinished || (fileExists && fileSize > 0)
        } else {
            isSuccess = true
        }

        let result: Result<URL?, Error>
        if isSuccess {
            result = .success(outputFileURL)
        } else if let error {
            result = .failure(FacecamRecorderError.recordingFailed(error.localizedDescription))
        } else {
            result = .success(outputFileURL)
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int64) ?? -1
        facecamLog.notice("finishRecording url=\(outputFileURL.lastPathComponent, privacy: .public) isSuccess=\(isSuccess, privacy: .public) fileSize=\(fileSize, privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)")

        finishResult = result
        switch result {
        case .success(let url):
            finishContinuation?.resume(returning: url)
        case .failure(let error):
            finishContinuation?.resume(throwing: error)
        }
        finishContinuation = nil
        cleanup(keepOutputURL: true)
    }

    private func cameraDevice(_ deviceID: String?) throws -> AVCaptureDevice {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
        if let deviceID,
           let device = discovery.devices.first(where: { $0.uniqueID == deviceID }) {
            return device
        }
        if let device = AVCaptureDevice.default(for: .video) ?? discovery.devices.first {
            return device
        }
        throw FacecamRecorderError.cameraUnavailable
    }

    private func cleanup(keepOutputURL: Bool = false) {
        preparationGeneration += 1
        if let session, session.isRunning {
            session.stopRunning()
        }
        session = nil
        movieOutput = nil
        preparedCameraDeviceID = nil
        startedAt = nil
        if !keepOutputURL {
            outputURL = nil
        }
        startContinuation = nil
    }
}
