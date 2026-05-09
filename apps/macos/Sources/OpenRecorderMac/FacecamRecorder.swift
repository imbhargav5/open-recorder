@preconcurrency import AVFoundation
import Foundation

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
    private var outputURL: URL?
    private var startedAt: Date?
    private var startContinuation: CheckedContinuation<Date, Error>?
    private var finishContinuation: CheckedContinuation<URL?, Error>?
    private var finishResult: Result<URL?, Error>?

    var isRecording: Bool {
        movieOutput?.isRecording == true
    }

    func start(outputURL: URL, cameraDeviceID: String?) async throws -> Date {
        cleanup()

        let device = try cameraDevice(cameraDeviceID)
        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard session.canAddInput(input) else {
            throw FacecamRecorderError.cannotAddCameraInput
        }
        session.addInput(input)

        let output = AVCaptureMovieFileOutput()
        guard session.canAddOutput(output) else {
            throw FacecamRecorderError.cannotAddMovieOutput
        }
        session.addOutput(output)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        self.session = session
        self.movieOutput = output
        self.outputURL = outputURL
        self.finishResult = nil

        session.startRunning()

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            output.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    func stop() async throws -> URL? {
        guard let output = movieOutput, output.isRecording else {
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
        let result: Result<URL?, Error>
        if let error {
            result = .failure(FacecamRecorderError.recordingFailed(error.localizedDescription))
        } else {
            result = .success(outputFileURL)
        }

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
            deviceTypes: [.builtInWideAngleCamera, .external],
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
        if let session, session.isRunning {
            session.stopRunning()
        }
        session = nil
        movieOutput = nil
        startedAt = nil
        if !keepOutputURL {
            outputURL = nil
        }
        startContinuation = nil
    }
}
