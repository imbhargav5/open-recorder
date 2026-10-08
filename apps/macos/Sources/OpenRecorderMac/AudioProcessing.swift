@preconcurrency import AVFoundation
import MediaToolbox
import Foundation

struct AudioProcessingSettings: Codable, Equatable, Hashable, Sendable {
    enum Routing: String, Codable, CaseIterable, Identifiable, Sendable {
        case stereo, left, right, mono
        var id: String { rawValue }
        var title: String {
            switch self {
            case .stereo: "Original stereo"
            case .left: "Input 1 → Mono"
            case .right: "Input 2 → Mono"
            case .mono: "Mix both → Mono"
            }
        }
    }
    var routing: Routing = .stereo
    var gainDB: Double = 0
    var bassDB: Double = 0
    var presenceDB: Double = 0
    var trebleDB: Double = 0
    var punch: Double = 0
    var reduceRumble = false
    var normalize = false
    var targetLUFS: Double = -14
    var syncOffsetMs: Double?
    var syncOffset: Double { min(2000, max(-2000, syncOffsetMs ?? 0)) }
    static let `default` = Self()
    static let voice = Self(bassDB: 0, presenceDB: 2, trebleDB: 1, punch: 0.35, reduceRumble: true, normalize: true)
    var isActive: Bool { self != .default }
}

/// Direct-form biquad. Each instance owns the history for one channel.
struct AudioBiquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var z1 = 0.0, z2 = 0.0
    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
    static func filter(frequency: Double, sampleRate: Double, gain: Double = 0, highPass: Bool = false) -> Self {
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let c = cos(w), alpha = sin(w) / (2 * 0.707), a = pow(10, gain / 40)
        let denominator = highPass ? 1 + alpha : 1 + alpha / a
        if highPass {
            return Self(b0: (1+c)/2/denominator, b1: -(1+c)/denominator, b2: (1+c)/2/denominator,
                        a1: -2*c/denominator, a2: (1-alpha)/denominator)
        }
        return Self(b0: (1+alpha*a)/denominator, b1: -2*c/denominator, b2: (1-alpha*a)/denominator,
                    a1: -2*c/denominator, a2: (1-alpha/a)/denominator)
    }
}

final class VoiceAudioDSP {
    let settings: AudioProcessingSettings
    let gain: Double
    var filters: [[AudioBiquad]]
    var envelope = 0.0
    let attack: Double
    let release: Double
    init(settings: AudioProcessingSettings, sampleRate: Double, normalizationGain: Double = 0) {
        self.settings = settings
        gain = pow(10, (min(24, max(-24, settings.gainDB)) + normalizationGain) / 20)
        attack = exp(-1 / (0.008 * sampleRate))
        release = exp(-1 / (0.12 * sampleRate))
        var channelFilters: [AudioBiquad] = []
        if settings.reduceRumble { channelFilters.append(.filter(frequency: 80, sampleRate: sampleRate, highPass: true)) }
        for (frequency, db) in [(120.0, settings.bassDB), (3000.0, settings.presenceDB), (9000.0, settings.trebleDB)] {
            channelFilters.append(.filter(frequency: frequency, sampleRate: sampleRate, gain: min(12, max(-12, db))))
        }
        filters = [channelFilters, channelFilters]
    }
    func process(_ left: Float, _ right: Float, limit: Bool = true) -> (Float, Float) {
        var l = Double(left.isFinite ? left : 0), r = Double(right.isFinite ? right : 0)
        switch settings.routing {
        case .stereo: break
        case .left: r = l
        case .right: l = r
        case .mono: l = (l+r)/2; r = l
        }
        for index in filters[0].indices {
            l = filters[0][index].process(l)
            r = filters[1][index].process(r)
        }
        let peak = max(abs(l), abs(r))
        let coefficient = peak > envelope ? attack : release
        envelope = coefficient * envelope + (1-coefficient) * peak
        let amount = min(1, max(0, settings.punch))
        let aboveThreshold = max(0, 20 * log10(max(envelope, 1e-12)) + 20)
        let reduction = aboveThreshold * (1 - 1 / (1 + 3 * amount))
        let compression = pow(10, (-reduction + 4 * amount)/20)
        l *= gain * compression; r *= gain * compression
        // Sample peak safety ceiling. This is not a true-peak meter/limiter.
        if limit {
            let ceiling = pow(10, -1.0/20)
            let attenuation = min(1, ceiling / max(max(abs(l), abs(r)), 1e-12))
            l *= attenuation; r *= attenuation
        }
        return (Float(l), Float(r))
    }
}

private final class AudioTapStorage {
    let settings: AudioProcessingSettings
    let normalizationGain: Double
    var dsp: VoiceAudioDSP?
    var format = AudioStreamBasicDescription()
    init(_ settings: AudioProcessingSettings, gain: Double) { self.settings = settings; normalizationGain = gain }
}

enum ProjectAudioProcessor {
    static func mix(for asset: AVAsset, settings: AudioProcessingSettings, normalizationGain: Double = 0, isolation: isolated (any Actor)? = #isolation) async throws -> AVAudioMix? {
        guard settings.isActive else { return nil }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let mix = AVMutableAudioMix()
        mix.inputParameters = try tracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            let storage = Unmanaged.passRetained(AudioTapStorage(settings, gain: normalizationGain))
            var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: storage.toOpaque(), init: { _, info, out in out.pointee = info },
                finalize: { tap in Unmanaged<AudioTapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
                prepare: { tap, _, format in
                    let state = Unmanaged<AudioTapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    state.format = format.pointee
                    state.dsp = VoiceAudioDSP(settings: state.settings, sampleRate: format.pointee.mSampleRate,
                                              normalizationGain: state.normalizationGain)
                }, unprepare: { _ in }, process: { tap, frames, _, list, count, flags in
                    guard MTAudioProcessingTapGetSourceAudio(tap, frames, list, flags, nil, count) == noErr else {
                        count.pointee = 0; return
                    }
                    let state = Unmanaged<AudioTapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    guard state.format.mFormatID == kAudioFormatLinearPCM,
                          state.format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                          state.format.mBitsPerChannel == 32, let dsp = state.dsp else { return }
                    let buffers = UnsafeMutableAudioBufferListPointer(list)
                    let channels = Int(state.format.mChannelsPerFrame)
                    guard channels == 1 || channels == 2, let first = buffers.first?.mData else { return }
                    let interleaved = state.format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
                    let left = first.assumingMemoryBound(to: Float.self)
                    guard interleaved || channels == 1 || (buffers.count >= 2 && buffers[1].mData != nil) else { return }
                    let right = channels == 2 && !interleaved ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
                    for frame in 0..<Int(count.pointee) {
                        let offset = interleaved ? frame * channels : frame
                        let l = left[offset]
                        let r = channels == 1 ? l : (interleaved ? left[offset+1] : right![frame])
                        let result = dsp.process(l, r)
                        left[offset] = result.0
                        if channels == 2 {
                            if interleaved { left[offset+1] = result.1 } else { right![frame] = result.1 }
                        }
                    }
                })
            var tap: MTAudioProcessingTap?
            let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
            guard status == noErr, let tap else {
                storage.release()
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            parameters.audioTapProcessor = tap
            return parameters
        }
        return mix
    }
}

/// BS.1770 K weighting at 48 kHz, 400 ms blocks with 75% overlap,
/// then the -70 LUFS absolute and -10 LU relative gates (stereo only).
struct IntegratedLoudnessMeter {
    private var shelf = Array(repeating: AudioBiquad(b0: 1.53512485958697, b1: -2.69169618940638,
        b2: 1.19839281085285, a1: -1.69065929318241, a2: 0.73248077421585), count: 2)
    private var highPass = Array(repeating: AudioBiquad(b0: 1, b1: -2, b2: 1,
        a1: -1.99004745483398, a2: 0.99007225036621), count: 2)
    private var ring = [Double](repeating: 0, count: 19_200)
    private var count = 0
    private var sum = 0.0
    private var blocks: [Double] = []
    mutating func add(_ left: Float, _ right: Float) {
        let l = highPass[0].process(shelf[0].process(Double(left)))
        let r = highPass[1].process(shelf[1].process(Double(right)))
        let energy = l*l + r*r
        let index = count % ring.count
        sum += energy - ring[index]; ring[index] = energy; count += 1
        if count >= ring.count && (count - ring.count) % 4800 == 0 { blocks.append(max(0, sum / Double(ring.count))) }
    }
    var loudness: Double? {
        func lufs(_ energy: Double) -> Double { -0.691 + 10 * log10(max(energy, 1e-20)) }
        let absolute = blocks.filter { lufs($0) > -70 }
        guard !absolute.isEmpty else { return nil }
        let relativeGate = lufs(absolute.reduce(0,+) / Double(absolute.count)) - 10
        let gated = absolute.filter { lufs($0) > relativeGate }
        guard !gated.isEmpty else { return nil }
        return lufs(gated.reduce(0,+) / Double(gated.count))
    }
}

struct AudioLoudnessAnalysis: Sendable {
    var lufs: Double?
    var peakDB: Double
    func normalizationGain(target: Double) -> Double {
        guard let lufs else { return 0 }
        return max(-60, min(24, min(target - lufs, -1 - peakDB)))
    }
}

extension ProjectAudioProcessor {
    static func analyze(asset: AVAsset, settings: AudioProcessingSettings, isolation: isolated (any Actor)? = #isolation) async throws -> AudioLoudnessAnalysis {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return AudioLoudnessAnalysis(lufs: nil, peakDB: -120) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else { throw AudioFailure.readFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? AudioFailure.readFailed }
        let dsp = VoiceAudioDSP(settings: settings, sampleRate: 48_000)
        var meter = IntegratedLoudnessMeter()
        var peak = 0.0
        while let sample = output.copyNextSampleBuffer() {
            await Task.yield()
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { throw AudioFailure.readFailed }
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = floats.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            guard status == noErr, floats.count % 2 == 0 else { throw AudioFailure.readFailed }
            for frame in stride(from: 0, to: floats.count, by: 2) {
                let processed = dsp.process(floats[frame], floats[frame+1], limit: false)
                meter.add(processed.0, processed.1)
                peak = max(peak, max(abs(Double(processed.0)), abs(Double(processed.1))))
            }
        }
        guard reader.status == .completed else { throw reader.error ?? AudioFailure.readFailed }
        return AudioLoudnessAnalysis(lufs: meter.loudness, peakDB: 20 * log10(max(peak, 1e-6)))
    }
    enum AudioFailure: LocalizedError {
        case readFailed
        var errorDescription: String? { "Unable to analyze this recording’s audio." }
    }
}


extension ProjectAudioProcessor {
    /// Apply a timestamp shift to audio while retaining the original video clock.
    /// Positive shifts delay audio; negative shifts advance it and trim only audio
    /// that would precede time zero. Source audio's existing start delay is retained.
    static func synchronizedAsset(from asset: AVAsset, offsetMs: Double,
        isolation: isolated (any Actor)? = #isolation) async throws -> AVAsset {
        guard offsetMs.isFinite, abs(offsetMs) > 0.01 else { return asset }
        let composition = AVMutableComposition()
        let offset = CMTime(seconds: min(2000, max(-2000, offsetMs)) / 1000, preferredTimescale: 48_000)
        let videoDuration = try await asset.load(.duration)
        for mediaType in [AVMediaType.video, .audio] {
            for track in try await asset.loadTracks(withMediaType: mediaType) {
                guard let target = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw AudioFailure.readFailed
                }
                var range = try await track.load(.timeRange)
                var start = range.start
                if mediaType == .audio {
                    start = range.start + offset
                    if start < .zero {
                        let trim = CMTimeMinimum(.zero - start, range.duration)
                        range = CMTimeRange(start: range.start + trim, duration: range.duration - trim)
                        start = .zero
                    }
                    range.duration = CMTimeMinimum(range.duration, CMTimeMaximum(.zero, videoDuration - start))
                }
                if range.duration > .zero { try target.insertTimeRange(range, of: track, at: start) }
                if mediaType == .video { target.preferredTransform = try await track.load(.preferredTransform) }
            }
        }
        return composition
    }
}
