import AVFoundation
import Foundation

struct TimelineRulerTick: Identifiable, Equatable {
    var time: Double
    var label: String

    var id: Double { time }
}

enum TimelineRulerTickBuilder {
    static func ticks(duration: Double, maxTickCount: Int = 8) -> [TimelineRulerTick] {
        let safeDuration = duration.isFinite && duration > 0 ? duration : 6
        let safeTickCount = max(maxTickCount, 2)
        let step = tickStep(for: safeDuration, maxTickCount: safeTickCount)
        var ticks: [TimelineRulerTick] = []
        var time = 0.0

        while time <= safeDuration + 0.0001 {
            ticks.append(TimelineRulerTick(time: time, label: label(for: time, duration: safeDuration)))
            time += step
        }

        if let last = ticks.last, last.time < safeDuration - 0.0001 {
            ticks.append(TimelineRulerTick(time: safeDuration, label: label(for: safeDuration, duration: safeDuration)))
        }

        return ticks
    }

    static func ticks(visibleStart: Double, visibleDuration: Double, totalDuration: Double, maxTickCount: Int = 8) -> [TimelineRulerTick] {
        let safeVisibleStart = visibleStart.isFinite && visibleStart > 0 ? visibleStart : 0
        let safeVisibleDuration = visibleDuration.isFinite && visibleDuration > 0 ? visibleDuration : 6
        let safeTotalDuration = totalDuration.isFinite && totalDuration > 0 ? totalDuration : safeVisibleDuration
        let safeTickCount = max(maxTickCount, 2)
        let step = tickStep(for: safeVisibleDuration, maxTickCount: safeTickCount)
        let visibleEnd = min(safeTotalDuration, safeVisibleStart + safeVisibleDuration)
        var ticks: [TimelineRulerTick] = []
        var time = (safeVisibleStart / step).rounded(.up) * step

        if abs(time) < 0.0001 {
            time = 0
        }

        while time <= visibleEnd + 0.0001 {
            if time >= safeVisibleStart - 0.0001 {
                ticks.append(TimelineRulerTick(time: time, label: label(for: time, duration: safeTotalDuration)))
            }
            time += step
        }

        if safeVisibleStart <= 0.0001, ticks.first?.time != 0 {
            ticks.insert(TimelineRulerTick(time: 0, label: label(for: 0, duration: safeTotalDuration)), at: 0)
        }

        if visibleEnd >= safeTotalDuration - 0.0001,
           ticks.last.map({ abs($0.time - safeTotalDuration) > 0.0001 }) ?? true {
            ticks.append(TimelineRulerTick(time: safeTotalDuration, label: label(for: safeTotalDuration, duration: safeTotalDuration)))
        }

        return ticks
    }

    static func halfSecondTicks(duration: Double) -> [TimelineRulerTick] {
        let safeDuration = duration.isFinite && duration > 0 ? duration : 6
        var ticks: [TimelineRulerTick] = []
        var time = 0.5

        while time < safeDuration - 0.0001 {
            ticks.append(TimelineRulerTick(time: time, label: ""))
            time += 1
        }

        return ticks
    }

    static func halfSecondTicks(visibleStart: Double, visibleDuration: Double, totalDuration: Double) -> [TimelineRulerTick] {
        let safeVisibleStart = visibleStart.isFinite && visibleStart > 0 ? visibleStart : 0
        let safeVisibleDuration = visibleDuration.isFinite && visibleDuration > 0 ? visibleDuration : 6
        let safeTotalDuration = totalDuration.isFinite && totalDuration > 0 ? totalDuration : safeVisibleDuration
        let visibleEnd = min(safeTotalDuration, safeVisibleStart + safeVisibleDuration)
        var ticks: [TimelineRulerTick] = []
        var time = (safeVisibleStart - 0.5).rounded(.up) + 0.5

        while time < visibleEnd - 0.0001 {
            if time >= safeVisibleStart + 0.0001 {
                ticks.append(TimelineRulerTick(time: time, label: ""))
            }
            time += 1
        }

        return ticks
    }

    private static func tickStep(for duration: Double, maxTickCount: Int) -> Double {
        let preferredSteps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

        for step in preferredSteps {
            if Int(floor(duration / step)) + 1 <= maxTickCount {
                return step
            }
        }

        let rawStep = duration / Double(max(maxTickCount - 1, 1))
        let magnitude = pow(10, floor(log10(rawStep)))
        for multiplier in [1.0, 2.0, 5.0, 10.0] {
            let step = magnitude * multiplier
            if Int(floor(duration / step)) + 1 <= maxTickCount {
                return step
            }
        }

        return max(rawStep, 1)
    }

    private static func label(for time: Double, duration: Double) -> String {
        if duration <= 10 {
            return time == 0 ? "" : "\(Int(time.rounded()))s"
        }

        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

enum TimelineWaveformDownsampler {
    static let quietLevel = 0.08

    static func quietSamples(targetCount: Int) -> [Double] {
        guard targetCount > 0 else { return [] }
        return Array(repeating: quietLevel, count: targetCount)
    }

    static func downsample(
        interleavedSamples: [Float],
        channelCount: Int,
        targetCount: Int
    ) -> [Double] {
        interleavedSamples.withUnsafeBufferPointer { buffer in
            downsample(interleavedSamples: buffer, channelCount: channelCount, targetCount: targetCount)
        }
    }

    static func downsample(
        interleavedSamples: UnsafeBufferPointer<Float>,
        channelCount: Int,
        targetCount: Int
    ) -> [Double] {
        guard targetCount > 0 else { return [] }
        guard channelCount > 0, !interleavedSamples.isEmpty else {
            return quietSamples(targetCount: targetCount)
        }

        let frameCount = interleavedSamples.count / channelCount
        guard frameCount > 0 else {
            return quietSamples(targetCount: targetCount)
        }

        var bucketLevels = Array(repeating: Float(0), count: targetCount)

        for frame in 0..<frameCount {
            let bucket = min(Int(Double(frame) / Double(frameCount) * Double(targetCount)), targetCount - 1)
            bucketLevels[bucket] = max(
                bucketLevels[bucket],
                averagedAbsoluteLevel(in: interleavedSamples, frame: frame, channelCount: channelCount)
            )
        }

        return bucketLevels.map { min(max(Double($0), 0), 1) }
    }

    static func averagedAbsoluteLevel(
        in samples: UnsafeBufferPointer<Float>,
        frame: Int,
        channelCount: Int
    ) -> Float {
        let start = frame * channelCount
        guard start + channelCount <= samples.count else { return 0 }

        var level = Float(0)
        for channel in 0..<channelCount {
            level += abs(samples[start + channel])
        }
        return min(max(level / Float(channelCount), 0), 1)
    }
}

struct TimelineAudioWaveform: Equatable {
    var samples: [Double]

    var isAvailable: Bool {
        !samples.isEmpty
    }

    static let none = TimelineAudioWaveform(samples: [])

    static func available(samples: [Double]) -> TimelineAudioWaveform {
        TimelineAudioWaveform(samples: samples.map { min(max($0, 0), 1) })
    }
}

enum TimelineAudioWaveformLoader {
    static let defaultSampleCount = 720

    static func quietSamples(targetCount: Int = defaultSampleCount) -> [Double] {
        TimelineWaveformDownsampler.quietSamples(targetCount: targetCount)
    }

    static func loadWaveform(from url: URL, targetCount: Int = defaultSampleCount) async -> TimelineAudioWaveform {
        guard targetCount > 0 else { return .none }

        return await Task.detached(priority: .utility) {
            do {
                return try await readWaveform(from: url, targetCount: targetCount)
            } catch {
                return .none
            }
        }.value
    }

    static func loadSamples(from url: URL, targetCount: Int = defaultSampleCount) async -> [Double] {
        await loadWaveform(from: url, targetCount: targetCount).samples
    }

    private static func readWaveform(from url: URL, targetCount: Int) async throws -> TimelineAudioWaveform {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            return .none
        }

        let format = try await audioFormat(for: audioTrack)
        let channelCount = max(Int(format.channelCount), 1)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48_000
        let duration = try await asset.load(.duration).seconds
        let totalFrames = duration.isFinite && duration > 0
            ? max(Int64((duration * sampleRate).rounded(.up)), 1)
            : Int64(0)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw TimelineAudioWaveformReaderError.cannotAddReaderOutput
        }

        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? TimelineAudioWaveformReaderError.readerFailed
        }

        var accumulator = TimelineWaveformAccumulator(targetCount: targetCount)
        var frameOffset = Int64(0)

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                continue
            }

            let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
            try addSampleBuffer(
                sampleBuffer,
                channelCount: channelCount,
                frameOffset: frameOffset,
                totalFrames: totalFrames,
                to: &accumulator
            )
            frameOffset += Int64(frameCount)
        }

        if reader.status == .failed {
            throw reader.error ?? TimelineAudioWaveformReaderError.readerFailed
        }

        return .available(samples: accumulator.samples())
    }

    private static func audioFormat(for track: AVAssetTrack) async throws -> AudioTrackFormat {
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return AudioTrackFormat(channelCount: 1, sampleRate: 48_000)
        }

        return AudioTrackFormat(
            channelCount: streamDescription.pointee.mChannelsPerFrame,
            sampleRate: streamDescription.pointee.mSampleRate
        )
    }

    private static func addSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        channelCount: Int,
        frameOffset: Int64,
        totalFrames: Int64,
        to accumulator: inout TimelineWaveformAccumulator
    ) throws {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw TimelineAudioWaveformReaderError.unreadableSampleData
        }

        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        guard dataLength > 0 else { return }

        var data = Data(count: dataLength)
        let status = data.withUnsafeMutableBytes { rawBuffer in
            CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: dataLength,
                destination: rawBuffer.baseAddress!
            )
        }

        guard status == noErr else {
            throw TimelineAudioWaveformReaderError.unreadableSampleData
        }

        data.withUnsafeBytes { rawBuffer in
            let floatSamples = rawBuffer.bindMemory(to: Float.self)
            accumulator.addInterleavedSamples(
                floatSamples,
                channelCount: channelCount,
                frameOffset: frameOffset,
                totalFrames: totalFrames
            )
        }
    }
}

private struct AudioTrackFormat {
    var channelCount: UInt32
    var sampleRate: Double
}

private enum TimelineAudioWaveformReaderError: Error {
    case cannotAddReaderOutput
    case readerFailed
    case unreadableSampleData
}

private struct TimelineWaveformAccumulator {
    private var bucketLevels: [Float]

    init(targetCount: Int) {
        bucketLevels = Array(repeating: 0, count: max(targetCount, 0))
    }

    mutating func addInterleavedSamples(
        _ samples: UnsafeBufferPointer<Float>,
        channelCount: Int,
        frameOffset: Int64,
        totalFrames: Int64
    ) {
        guard !bucketLevels.isEmpty, channelCount > 0, !samples.isEmpty else { return }

        let frameCount = samples.count / channelCount
        guard frameCount > 0 else { return }

        let safeTotalFrames = max(totalFrames, frameOffset + Int64(frameCount), 1)

        for frame in 0..<frameCount {
            let absoluteFrame = min(frameOffset + Int64(frame), safeTotalFrames - 1)
            let bucket = min(
                Int(Double(absoluteFrame) / Double(safeTotalFrames) * Double(bucketLevels.count)),
                bucketLevels.count - 1
            )
            bucketLevels[bucket] = max(
                bucketLevels[bucket],
                TimelineWaveformDownsampler.averagedAbsoluteLevel(
                    in: samples,
                    frame: frame,
                    channelCount: channelCount
                )
            )
        }
    }

    func samples() -> [Double] {
        guard !bucketLevels.isEmpty else { return [] }
        guard bucketLevels.contains(where: { $0 > 0 }) else {
            return TimelineWaveformDownsampler.quietSamples(targetCount: bucketLevels.count)
        }

        return bucketLevels.map { min(max(Double($0), 0), 1) }
    }
}
