@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import Foundation

/// Records one ScreenCaptureKit audio source using its actual format description.
/// Kept separately from SCRecordingOutput so microphone and system audio never
/// share format assumptions. All mutable state is confined to sampleQueue.
final class ScreenCaptureAudioTrack: NSObject, SCStreamOutput, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "dev.openrecorder.native-audio-track")
    let audioURL: URL
    let reportURL: URL
    let outputType: SCStreamOutputType
    private var firstDate: Date?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var firstTime: CMTime?
    private var lastEnd: CMTime?
    private var sampleCount = 0
    private var droppedBuffers = 0
    private var failure: String?
    private var format: AudioStreamBasicDescription?
    private var closed = false
    private var pending: [CMSampleBuffer] = []
    private var pendingFrames = 0
    private var retryScheduled = false
    private var finalizing = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    init(directory: URL, name: String, outputType: SCStreamOutputType) throws {
        self.outputType = outputType
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = directory.appendingPathComponent(name + "-" + UUID().uuidString)
        audioURL = base.appendingPathExtension("mov")
        reportURL = base.appendingPathExtension("json")
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == self.outputType else { return }
        append(sampleBuffer, clock: stream.synchronizationClock ?? CMClockGetHostTimeClock())
    }

    // Called exclusively on sampleQueue, including by synthetic-buffer tests.
    func append(_ buffer: CMSampleBuffer, clock: CMClock = CMClockGetHostTimeClock()) {
        guard !closed, failure == nil, buffer.isValid,
              CMSampleBufferDataIsReady(buffer), CMSampleBufferGetNumSamples(buffer) > 0,
              let description = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard timestamp.isNumeric, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else { return }
        do {
            if writer == nil {
                format = asbd
                let writer = try AVAssetWriter(outputURL: audioURL, fileType: .mov)
                // Scarlett sends signed 24-bit samples in 32-bit aligned slots.
                // Pass those samples through untouched: AVAssetWriter's PCM
                // float converter truncates their frames and corrupts values.
                let aligned24In32 = asbd.mBitsPerChannel == 24 &&
                    asbd.mBytesPerFrame == asbd.mChannelsPerFrame * 4 &&
                    asbd.mFormatFlags & kAudioFormatFlagIsPacked == 0
                let outputSettings: [String: Any]? = aligned24In32 ? nil : [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: asbd.mSampleRate,
                    AVNumberOfChannelsKey: Int(asbd.mChannelsPerFrame),
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings,
                                               sourceFormatHint: description)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { throw CaptureAudioError.cannotAddInput }
                writer.add(input)
                guard writer.startWriting() else { throw writer.error ?? CaptureAudioError.cannotStart }
                writer.startSession(atSourceTime: timestamp)
                self.writer = writer
                self.input = input
                firstTime = timestamp
                firstDate = CaptureMediaClock.date(for: timestamp, clock: clock)
            }
            pending.append(buffer)
            pendingFrames += CMSampleBufferGetNumSamples(buffer)
            if pendingFrames > Int(asbd.mSampleRate * 2) {
                droppedBuffers += pending.count
                failure = "Audio storage could not keep up. The original capture and separate audio sources have been preserved."
                pending.removeAll()
                pendingFrames = 0
            }
            drainPending()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func drainPending() {
        guard let writer, let input else { finalizeIfReady(); return }
        if writer.status == .failed {
            failure = writer.error?.localizedDescription ?? "Audio writer failed"
            pending.removeAll()
            pendingFrames = 0
        }
        while !pending.isEmpty && input.isReadyForMoreMediaData && failure == nil {
            let buffer = pending.removeFirst()
            let frames = CMSampleBufferGetNumSamples(buffer)
            pendingFrames -= frames
            guard input.append(buffer) else {
                failure = writer.error?.localizedDescription ?? "Could not write audio"
                pending.removeAll()
                pendingFrames = 0
                break
            }
            sampleCount += frames
            lastEnd = buffer.presentationTimeStamp + CMTime(seconds: Double(frames) / (format?.mSampleRate ?? 48_000),
                preferredTimescale: 1_000_000_000)
        }
        if !pending.isEmpty && !retryScheduled {
            retryScheduled = true
            sampleQueue.asyncAfter(deadline: .now() + .milliseconds(5)) {
                self.retryScheduled = false
                self.drainPending()
            }
        }
        finalizeIfReady()
    }

    /// Called after SCK has stopped; drains pending audio before closing the file.
    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sampleQueue.async {
                if self.finalizing && self.finishWaiters.isEmpty { continuation.resume(); return }
                self.finishWaiters.append(continuation)
                self.closed = true
                self.drainPending()
            }
        }
    }

    private func finalizeIfReady() {
        guard closed, pending.isEmpty, !finalizing else { return }
        finalizing = true
        guard let writer, writer.status == .writing else { completeFinish(); return }
        input?.markAsFinished()
        writer.finishWriting {
            self.sampleQueue.async {
                if self.writer?.status != .completed {
                    self.failure = self.writer?.error?.localizedDescription ?? "Writer did not finish"
                }
                self.completeFinish()
            }
        }
    }

    private func completeFinish() {
        writeReport()
        let waiters = finishWaiters
        finishWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    struct Result: Sendable {
        let url: URL
        let startedAt: Date
    }

    func waitForFirstSamples() async throws {
        for _ in 0..<200 {
            let ready: Bool = try await withCheckedThrowingContinuation { continuation in
                sampleQueue.async {
                    if let failure = self.failure {
                        continuation.resume(throwing: NSError(domain: "OpenRecorderAudio", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: failure]))
                    } else { continuation.resume(returning: self.sampleCount > 0) }
                }
            }
            if ready { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "OpenRecorderAudio", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "ScreenCaptureKit is not delivering audio from the selected input. Recording was stopped; check the selected microphone and try a short test."])
    }

    func result() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            sampleQueue.async {
                if let failure = self.failure {
                    continuation.resume(throwing: NSError(domain: "OpenRecorderAudio", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: failure]))
                } else if self.sampleCount == 0 || self.firstDate == nil {
                    continuation.resume(throwing: NSError(domain: "OpenRecorderAudio", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "ScreenCaptureKit did not deliver audio samples. The video and any audio sources have been preserved."]))
                } else {
                    continuation.resume(returning: Result(url: self.audioURL, startedAt: self.firstDate!))
                }
            }
        }
    }

    private func writeReport() {
        var report: [String: Any] = [
            "audioFile": audioURL.path, "samplesWritten": sampleCount,
            "source": outputType == .microphone ? "microphone" : "system",
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
            NSLog("ScreenCaptureKit native audio source: %@", reportURL.path)
        } catch {
            NSLog("Unable to save microphone diagnostic: %@", error.localizedDescription)
        }
    }

    private enum CaptureAudioError: Error {
        case cannotAddInput, cannotStart, cannotAppend
    }
}
