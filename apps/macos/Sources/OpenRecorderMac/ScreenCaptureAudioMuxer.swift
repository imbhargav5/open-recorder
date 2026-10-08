@preconcurrency import AVFoundation
import Foundation

/// Preserve SCK's encoded video while replacing its combined audio with audio
/// encoded from each source's native CMSampleBuffer format and timestamps.
@MainActor
enum ScreenCaptureAudioMuxer {
    static func replaceAudio(in videoURL: URL, sources: [ScreenCaptureAudioTrack.Result],
                             videoStartedAt: Date) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw Failure.missingVideo }
        let videoRange = try await videoTrack.load(.timeRange)
        let duration = videoRange.end
        let audioComposition = AVMutableComposition()
        // Keep source assets alive throughout asynchronous reading and export.
        let audioAssets = sources.map { AVURLAsset(url: $0.url) }
        for (source, asset) in zip(sources, audioAssets) {
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.missingAudio }
            var range = try await track.load(.timeRange)
            var start = range.start + CMTime(seconds: source.startedAt.timeIntervalSince(videoStartedAt), preferredTimescale: 48_000)
            if start < .zero {
                let trim = CMTimeMinimum(.zero - start, range.duration)
                range.start = range.start + trim
                range.duration = range.duration - trim
                start = .zero
            }
            range.duration = CMTimeMinimum(range.duration, CMTimeMaximum(.zero, duration - start))
            guard range.duration > .zero else { continue }
            guard let target = audioComposition.addMutableTrack(withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else { throw Failure.missingAudio }
            try target.insertTimeRange(range, of: track, at: start)
        }
        guard !audioComposition.tracks.isEmpty else { throw Failure.missingAudio }
        // Match video duration, including silence before/after an audio source.
        if audioComposition.duration < duration {
            audioComposition.insertEmptyTimeRange(CMTimeRange(start: audioComposition.duration,
                duration: duration - audioComposition.duration))
        }
        let temporary = videoURL.deletingLastPathComponent().appendingPathComponent(".audio-mux-" + UUID().uuidString)
        let mixedURL = temporary.appendingPathExtension("m4a")
        let finalURL = temporary.appendingPathExtension("mp4")
        defer {
            try? FileManager.default.removeItem(at: mixedURL)
            try? FileManager.default.removeItem(at: finalURL)
        }
        guard let audioExport = AVAssetExportSession(asset: audioComposition, presetName: AVAssetExportPresetAppleM4A) else { throw Failure.cannotExport }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioComposition.tracks.map { track in
            let parameter = AVMutableAudioMixInputParameters(track: track)
            parameter.setVolume(1, at: .zero)
            return parameter
        }
        audioExport.audioMix = mix
        audioExport.timeRange = CMTimeRange(start: .zero, duration: duration)
        try await audioExport.export(to: mixedURL, as: .m4a)

        let mixedAsset = AVURLAsset(url: mixedURL)
        guard let mixedTrack = try await mixedAsset.loadTracks(withMediaType: .audio).first else { throw Failure.missingAudio }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw Failure.cannotExport }
        try video.insertTimeRange(videoRange, of: videoTrack, at: videoRange.start)
        video.preferredTransform = try await videoTrack.load(.preferredTransform)
        let mixedRange = try await mixedTrack.load(.timeRange)
        try audio.insertTimeRange(mixedRange, of: mixedTrack, at: mixedRange.start)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw Failure.cannotExport }
        export.timeRange = CMTimeRange(start: .zero, duration: duration)
        try await export.export(to: finalURL, as: .mp4)
        _ = try FileManager.default.replaceItemAt(videoURL, withItemAt: finalURL)
    }

    private enum Failure: LocalizedError {
        case missingVideo, missingAudio, cannotExport
        var errorDescription: String? {
            "Could not finalize the recording audio. The original capture and separate audio sources have been preserved."
        }
    }
}
