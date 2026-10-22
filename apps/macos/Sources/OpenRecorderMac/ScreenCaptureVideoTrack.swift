@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import Foundation

/// Owns the video writer instead of relying on SCRecordingOutput, which can
/// finalize early while ScreenCaptureKit continues delivering audio samples.
final class ScreenCaptureVideoTrack: NSObject, SCStreamOutput, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "dev.openrecorder.native-video-track")
    private let url: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstTime: CMTime?
    private var closed = false
    private var failure: Error?

    init(url: URL) { self.url = url; super.init() }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen,
              buffer.isValid, CMSampleBufferDataIsReady(buffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete else { return }
        append(buffer)
    }

    private func append(_ buffer: CMSampleBuffer) {
        guard !closed, failure == nil else { return }
        do {
            let timestamp = buffer.presentationTimeStamp
            guard timestamp.isNumeric, let format = CMSampleBufferGetFormatDescription(buffer) else { return }
            if writer == nil {
                try? FileManager.default.removeItem(at: url)
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: max(2, Int(dimensions.width)),
                    AVVideoHeightKey: max(2, Int(dimensions.height))
                ], sourceFormatHint: format)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { throw NSError(domain: "OpenRecorderVideo", code: 1) }
                writer.add(input)
                guard writer.startWriting() else { throw writer.error ?? NSError(domain: "OpenRecorderVideo", code: 2) }
                writer.startSession(atSourceTime: timestamp)
                self.writer = writer; self.input = input
            }
            guard input?.isReadyForMoreMediaData == true else { return }
            guard input?.append(buffer) == true else { throw writer?.error ?? NSError(domain: "OpenRecorderVideo", code: 3) }
            if firstTime == nil { firstTime = timestamp }
        } catch { failure = error }
    }

    func waitForFirstFrame() async throws {
        for _ in 0..<300 {
            if let failure { throw failure }
            if firstTime != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "OpenRecorderVideo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Screen video did not start."])
    }

    func finish() async throws {
        closed = true
        guard let writer, writer.status == .writing else { if let failure { throw failure }; return }
        input?.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        if writer.status != .completed { throw writer.error ?? NSError(domain: "OpenRecorderVideo", code: 5) }
    }
}
