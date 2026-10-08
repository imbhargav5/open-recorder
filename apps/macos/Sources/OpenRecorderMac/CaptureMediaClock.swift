import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// Convert media timestamps to the same host-clock origin before comparing
/// recordings. Delegate delivery and actor scheduling are not media timestamps.
enum CaptureMediaClock {
    static func date(for timestamp: CMTime, clock: CMClock, now: Date = Date(),
                     hostNow: CMTime = CMClockGetTime(CMClockGetHostTimeClock())) -> Date? {
        let hostTimestamp = CMSyncConvertTime(timestamp, from: clock, to: CMClockGetHostTimeClock())
        guard hostTimestamp.isNumeric, hostNow.isNumeric else { return nil }
        return now.addingTimeInterval((hostTimestamp - hostNow).seconds)
    }
}

final class ScreenCaptureStartClock: NSObject, SCStreamOutput, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "dev.openrecorder.screen-start-clock")
    private let lock = NSLock()
    private var firstFrameDate: Date?
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let date = CaptureMediaClock.date(for: sampleBuffer.presentationTimeStamp,
                                               clock: stream.synchronizationClock ?? CMClockGetHostTimeClock()) else { return }
        lock.lock()
        if firstFrameDate == nil { firstFrameDate = date }
        lock.unlock()
    }
    private func recordedStartDate() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return firstFrameDate
    }
    func startDate(fallback: Date) async throws -> Date {
        // The recording delegate and sample output use different queues; the
        // delegate can arrive first. Give the first frame time to arrive.
        for _ in 0..<100 {
            if let date = recordedStartDate() { return date }
            try await Task.sleep(for: .milliseconds(10))
        }
        return fallback
    }
}
