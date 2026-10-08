#if DEBUG
@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import Foundation

/// A development-only comparison of ScreenCaptureKit's native microphone buffers
/// with SCRecordingOutput. All mutable state is confined to sampleQueue.
final class MicrophoneCaptureDiagnostic: NSObject, SCStreamOutput, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "dev.openrecorder.microphone-diagnostic")
    let audioURL: URL
    private let reportURL: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstTime: CMTime?
    private var lastEnd: CMTime?
    private var sampleCount = 0
    private var droppedBuffers = 0
    private var failure: String?
    private var format: AudioStreamBasicDescription?
    private var closed = false

    init(directory: URL, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = directory.appendingPathComponent(name + "-" + UUID().uuidString)
        audioURL = base.appendingPathExtension("mov")
        reportURL = base.appendingPathExtension("json")
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .microphone else { return }
        append(sampleBuffer)
    }

    // Called exclusively on sampleQueue, including by synthetic-buffer tests.
    func append(_ buffer: CMSampleBuffer) {
        guard !closed, failure == nil, buffer.isValid,
              CMSampleBufferDataIsReady(buffer), CMSampleBufferGetNumSamples(buffer) > 0,
              let description = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard timestamp.isNumeric, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else { return }
        // This probe only needs a short comparison, even during a long recording.
        if let firstTime, (timestamp - firstTime).seconds >= 30 { return }
        do {
            if writer == nil {
                format = asbd
                let writer = try AVAssetWriter(outputURL: audioURL, fileType: .mov)
                // The input's source format comes from SCK, including integer/float,
                // packing and interleaving. Never reinterpret its bytes as Float32.
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: asbd.mSampleRate,
                    AVNumberOfChannelsKey: Int(asbd.mChannelsPerFrame),
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ], sourceFormatHint: description)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { throw DiagnosticError.cannotAddInput }
                writer.add(input)
                guard writer.startWriting() else { throw writer.error ?? DiagnosticError.cannotStart }
                writer.startSession(atSourceTime: timestamp)
                self.writer = writer
                self.input = input
                firstTime = timestamp
            }
            guard let writer, let input else { return }
            guard input.isReadyForMoreMediaData else {
                droppedBuffers += 1
                if writer.status == .failed { failure = writer.error?.localizedDescription ?? "Writer failed" }
                return
            }
            guard input.append(buffer) else { throw writer.error ?? DiagnosticError.cannotAppend }
            sampleCount += CMSampleBufferGetNumSamples(buffer)
            lastEnd = timestamp + CMTime(seconds: Double(CMSampleBufferGetNumSamples(buffer)) / asbd.mSampleRate,
                                         preferredTimescale: 1_000_000_000)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Call after SCK has stopped. The queue barrier drains pending microphone callbacks.
    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sampleQueue.async {
                guard !self.closed else { continuation.resume(); return }
                self.closed = true
                guard let writer = self.writer, writer.status == .writing else {
                    self.writeReport()
                    continuation.resume()
                    return
                }
                self.input?.markAsFinished()
                writer.finishWriting {
                    self.sampleQueue.async {
                        if self.writer?.status != .completed {
                            self.failure = self.writer?.error?.localizedDescription ?? "Writer did not finish"
                        }
                        self.writeReport()
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func writeReport() {
        var report: [String: Any] = [
            "audioFile": audioURL.path, "samplesWritten": sampleCount,
            "captureLimitSeconds": 30,
            "droppedBuffers": droppedBuffers,
            "error": failure ?? (sampleCount == 0 ? "No microphone samples received" : "")
        ]
        if let format {
            report["sampleRate"] = format.mSampleRate
            report["channels"] = format.mChannelsPerFrame
            report["formatID"] = format.mFormatID
            report["formatFlags"] = format.mFormatFlags
            report["bitsPerChannel"] = format.mBitsPerChannel
            report["bytesPerFrame"] = format.mBytesPerFrame
            report["sampleDuration"] = Double(sampleCount) / format.mSampleRate
        }
        if let firstTime, let lastEnd {
            report["timestampDuration"] = (lastEnd - firstTime).seconds
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
            NSLog("ScreenCaptureKit microphone diagnostic: %@", reportURL.path)
        } catch {
            NSLog("Unable to save microphone diagnostic: %@", error.localizedDescription)
        }
    }

    private enum DiagnosticError: Error {
        case cannotAddInput, cannotStart, cannotAppend
    }
}
#endif
