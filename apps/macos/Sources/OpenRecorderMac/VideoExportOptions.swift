import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum VideoExportResolution: String, CaseIterable, Identifiable, Codable, Hashable {
    case source
    case p480
    case p720
    case p1080
    case twoK
    case fourK
    case custom

    var id: String { rawValue }

    static let exportOptions: [VideoExportResolution] = [.p480, .p720, .p1080, .fourK]

    static let defaultExportOption: VideoExportResolution = .p1080

    var title: String {
        switch self {
        case .source: "Source"
        case .p480: "480p"
        case .p720: "720p"
        case .p1080: "1080p"
        case .twoK: "2K"
        case .fourK: "4K"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .source: "Keep the recording dimensions."
        case .p480: "Scale the short edge to 480 px."
        case .p720: "Scale the short edge to 720 px."
        case .p1080: "Scale the short edge to 1080 px."
        case .twoK: "Scale the long edge to 2560 px."
        case .fourK: "Scale the short edge to 2160 px."
        case .custom: "Use the crop dialog size."
        }
    }

    var fileSuffix: String {
        switch self {
        case .source: "source"
        case .p480: "480p"
        case .p720: "720p"
        case .p1080: "1080p"
        case .twoK: "2k"
        case .fourK: "4k"
        case .custom: "custom"
        }
    }

    var targetLongEdge: CGFloat? {
        switch self {
        case .source, .p480, .p720, .p1080: nil
        case .twoK: 2560
        case .custom: nil
        case .fourK: nil
        }
    }

    var targetShortEdge: CGFloat? {
        switch self {
        case .source, .twoK, .custom:
            nil
        case .p480:
            480
        case .p720:
            720
        case .p1080:
            1080
        case .fourK:
            2160
        }
    }
}

enum VideoExportFormat: String, CaseIterable, Identifiable, Codable, Hashable {
    case mov
    case mp4
    case gif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mov: "MOV"
        case .mp4: "MP4"
        case .gif: "GIF"
        }
    }

    var fileExtension: String {
        switch self {
        case .mov: "mov"
        case .mp4: "mp4"
        case .gif: "gif"
        }
    }

    var contentType: UTType {
        switch self {
        case .mov: .quickTimeMovie
        case .mp4: .mpeg4Movie
        case .gif: .gif
        }
    }

    var avFileType: AVFileType? {
        switch self {
        case .mov: .mov
        case .mp4: .mp4
        case .gif: nil
        }
    }

    var detail: String {
        switch self {
        case .mov: "QuickTime movie (.mov)"
        case .mp4: "MPEG-4 movie (.mp4)"
        case .gif: "Animated GIF (.gif)"
        }
    }

    var isAnimatedImage: Bool {
        self == .gif
    }
}

enum VideoExportQuality: String, CaseIterable, Identifiable, Codable, Hashable {
    case low
    case medium
    case highSource

    var id: String { rawValue }

    static let defaultExportOption: VideoExportQuality = .highSource

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .highSource: "High"
        }
    }

    var detail: String {
        switch self {
        case .low: "Smallest MP4 file."
        case .medium: "Balanced MP4 size and clarity."
        case .highSource: "Best MP4 quality from the source."
        }
    }

    var fileSuffix: String {
        switch self {
        case .low: "low"
        case .medium: "medium"
        case .highSource: "high"
        }
    }

    var exportPresetName: String {
        switch self {
        case .low: AVAssetExportPresetLowQuality
        case .medium: AVAssetExportPresetMediumQuality
        case .highSource: AVAssetExportPresetHighestQuality
        }
    }
}

enum VideoExportGIFSize: String, CaseIterable, Identifiable, Codable, Hashable {
    case medium
    case large
    case original

    var id: String { rawValue }

    static let defaultExportOption: VideoExportGIFSize = .medium

    var title: String {
        switch self {
        case .medium: "Medium"
        case .large: "Large"
        case .original: "Original"
        }
    }

    var detail: String {
        switch self {
        case .medium: "Scale the short edge to 480 px."
        case .large: "Scale the short edge to 720 px."
        case .original: "Keep the source dimensions."
        }
    }

    var fileSuffix: String {
        switch self {
        case .medium: "medium"
        case .large: "large"
        case .original: "original"
        }
    }

    var resolution: VideoExportResolution {
        switch self {
        case .medium: .p480
        case .large: .p720
        case .original: .source
        }
    }
}

enum VideoExportFrameRate: String, CaseIterable, Identifiable, Codable, Hashable {
    case source
    case fps15
    case fps20
    case fps24
    case fps25
    case fps30
    case fps60

    var id: String { rawValue }

    static let exportOptions: [VideoExportFrameRate] = [.fps15, .fps24, .fps30, .fps60]
    static let gifExportOptions: [VideoExportFrameRate] = [.fps15, .fps20, .fps25, .fps30]

    static let defaultExportOption: VideoExportFrameRate = .fps30
    static let defaultGIFExportOption: VideoExportFrameRate = .fps15

    static func exportOptions(for format: VideoExportFormat) -> [VideoExportFrameRate] {
        format == .gif ? gifExportOptions : exportOptions
    }

    static func defaultExportOption(for format: VideoExportFormat) -> VideoExportFrameRate {
        format == .gif ? defaultGIFExportOption : defaultExportOption
    }

    var title: String {
        switch self {
        case .source: "Source"
        case .fps15: "15 FPS"
        case .fps20: "20 FPS"
        case .fps24: "24 FPS"
        case .fps25: "25 FPS"
        case .fps30: "30 FPS"
        case .fps60: "60 FPS"
        }
    }

    var detail: String {
        switch self {
        case .source: "Keep the recording frame rate."
        case .fps15: "Smallest file size."
        case .fps20: "Compact GIF motion."
        case .fps24: "Cinematic motion."
        case .fps25: "Smooth GIF playback."
        case .fps30: "Smaller file, smooth playback."
        case .fps60: "Best for fast cursor movement."
        }
    }

    var fileSuffix: String {
        switch self {
        case .source: "source-fps"
        case .fps15: "15fps"
        case .fps20: "20fps"
        case .fps24: "24fps"
        case .fps25: "25fps"
        case .fps30: "30fps"
        case .fps60: "60fps"
        }
    }

    var fixedFramesPerSecond: Double? {
        switch self {
        case .source: nil
        case .fps15: 15
        case .fps20: 20
        case .fps24: 24
        case .fps25: 25
        case .fps30: 30
        case .fps60: 60
        }
    }

    @MainActor
    func frameDuration(for videoTrack: AVAssetTrack) async throws -> CMTime {
        if let fixedFramesPerSecond {
            return frameDuration(framesPerSecond: fixedFramesPerSecond)
        }

        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        guard nominalFrameRate.isFinite, nominalFrameRate > 0 else {
            return frameDuration(framesPerSecond: 60)
        }
        return frameDuration(framesPerSecond: Double(nominalFrameRate))
    }

    private func frameDuration(framesPerSecond: Double) -> CMTime {
        let preciseTimescale = Int32(max(1, min(240_000, (framesPerSecond * 1_000).rounded())))
        return CMTime(value: 1_000, timescale: preciseTimescale)
    }
}

struct VideoExportOptions: Equatable {
    var resolution: VideoExportResolution
    var format: VideoExportFormat
    var frameRate: VideoExportFrameRate
    var quality: VideoExportQuality = .defaultExportOption
    var gifSize: VideoExportGIFSize = .defaultExportOption
    var gifLoops = true
    var aspectPreset: VideoPreviewAspectPreset = .auto
    var styling: VideoBackgroundStyling
    var cropSelection: VideoCropSelection?
    var customOutputSize: CGSize?
    var cursorOverlay: CursorOverlaySettings = .hidden
    var cursorTelemetryURL: URL? = nil
    var facecamVideoURL: URL? = nil
    var facecamOffsetMs: Int? = nil
    var facecamFallbackSettings: FacecamSettings? = nil

    static let `default` = VideoExportOptions(
        resolution: VideoExportResolution.defaultExportOption,
        format: .mov,
        frameRate: VideoExportFrameRate.defaultExportOption,
        quality: .defaultExportOption,
        gifSize: .defaultExportOption,
        gifLoops: true,
        aspectPreset: .auto,
        styling: .none,
        cropSelection: nil,
        customOutputSize: nil,
        cursorOverlay: .hidden,
        cursorTelemetryURL: nil,
        facecamVideoURL: nil,
        facecamOffsetMs: nil,
        facecamFallbackSettings: nil
    )

    func with(
        background: BackgroundStyle,
        padding: Double,
        borderRadius: Double,
        shadow: Double,
        backgroundBlur: Double,
        inset: Double,
        insetColor: SerializableColor,
        insetOpacity: Double,
        insetBalance: VideoInsetBalance
    ) -> VideoExportOptions {
        var copy = self
        copy.styling = VideoBackgroundStyling(
            background: background,
            paddingRatio: max(0, padding) / 100 * 0.2,
            borderRadiusRatio: max(0, borderRadius) / 100 * 0.4,
            shadowIntensity: max(0, min(shadow, 1)),
            backgroundBlurRatio: max(0, backgroundBlur) / 100 * 0.5,
            inset: VideoInsetStyling(
                amountRatio: VideoInsetGeometry.amountRatio(fromValue: inset.rounded()),
                color: insetColor,
                opacity: max(0, min(insetOpacity, 1)),
                balance: insetBalance.clamped
            )
        )
        return copy
    }

    func withCropSelection(_ selection: VideoCropSelection) -> VideoExportOptions {
        var copy = self
        copy.cropSelection = selection.isPassthrough ? nil : selection
        switch selection.sizing {
        case .preset(let resolution):
            if !selection.isPassthrough {
                copy.resolution = resolution
            }
            copy.customOutputSize = nil
        case .custom(let width, let height):
            copy.resolution = .custom
            copy.customOutputSize = CGSize(width: width, height: height)
        }
        return copy
    }

    func withAspectPreset(_ preset: VideoPreviewAspectPreset) -> VideoExportOptions {
        var copy = self
        copy.aspectPreset = preset
        return copy
    }

    func withCursorOverlay(_ settings: CursorOverlaySettings, telemetryURL: URL?) -> VideoExportOptions {
        var copy = self
        copy.cursorOverlay = settings.clamped
        copy.cursorTelemetryURL = telemetryURL
        return copy
    }

    func withFacecam(url: URL?, offsetMs: Int?, fallbackSettings: FacecamSettings?) -> VideoExportOptions {
        var copy = self
        copy.facecamVideoURL = url
        copy.facecamOffsetMs = offsetMs
        copy.facecamFallbackSettings = fallbackSettings?.clamped
        return copy
    }

    var summaryTitle: String {
        switch format {
        case .gif:
            "\(gifSize.title) \(format.title) at \(frameRate.title)"
        case .mp4:
            "\(resolution.title) \(quality.title) \(format.title) at \(frameRate.title)"
        case .mov:
            "\(resolution.title) \(format.title) at \(frameRate.title)"
        }
    }

    var fileNameSuffix: String {
        let sizeSuffix: String
        switch format {
        case .gif:
            sizeSuffix = gifSize.fileSuffix
        case .mov, .mp4:
            if resolution == .custom, let customOutputSize {
                sizeSuffix = "\(Int(customOutputSize.width.rounded()))x\(Int(customOutputSize.height.rounded()))"
            } else {
                sizeSuffix = resolution.fileSuffix
            }
        }

        let qualitySuffix = format == .mp4 ? "-\(quality.fileSuffix)" : ""
        let loopSuffix = format == .gif && gifLoops ? "-loop" : ""
        return "\(sizeSuffix)\(qualitySuffix)-\(frameRate.fileSuffix)\(loopSuffix)"
    }
}

enum VideoExportPhase: Equatable {
    case idle
    case exporting
    case saving
    case savePending
    case success
    case failed

    var isBusy: Bool {
        switch self {
        case .exporting, .saving:
            true
        case .idle, .savePending, .success, .failed:
            false
        }
    }
}

@MainActor
final class VideoExportCancellationToken {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

enum VideoExportRendererError: LocalizedError {
    case missingVideoTrack
    case exportSessionUnavailable
    case exportCancelled
    case emptyTimeline
    case unsupportedFormat
    case gifDestinationUnavailable
    case gifFrameGenerationFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack: "The recording does not contain a video track."
        case .exportSessionUnavailable: "This Mac cannot create the requested export session."
        case .exportCancelled: "Export canceled."
        case .emptyTimeline: "Timeline edits remove the entire recording."
        case .unsupportedFormat: "This export format is not supported."
        case .gifDestinationUnavailable: "This Mac cannot create the GIF export file."
        case .gifFrameGenerationFailed: "GIF frame rendering failed."
        case .exportFailed: "Video export failed."
        }
    }
}

@MainActor
enum VideoExportRenderer {
    private struct RenderContext {
        var asset: AVAsset
        var videoComposition: AVMutableVideoComposition
        var duration: Double
        var outputSize: CGSize
        var frameDuration: CMTime
    }

    static func export(
        sourceURL: URL,
        targetURL: URL,
        options: VideoExportOptions,
        cancellationToken: VideoExportCancellationToken? = nil,
        edits: TimelineEditSnapshot = .empty,
        progressHandler: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws {
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        let context = try await makeRenderContext(sourceURL: sourceURL, options: options, edits: edits)
        if options.format.isAnimatedImage {
            try await exportGIF(context: context, targetURL: targetURL, options: options, cancellationToken: cancellationToken, progressHandler: progressHandler)
        } else {
            try await exportMovie(context: context, targetURL: targetURL, options: options, cancellationToken: cancellationToken, progressHandler: progressHandler)
        }
    }

    private static func makeRenderContext(
        sourceURL: URL,
        options: VideoExportOptions,
        edits: TimelineEditSnapshot
    ) async throws -> RenderContext {
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw VideoExportRendererError.missingVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let assetDuration = try await asset.load(.duration)
        let videoTrackTimeRange = try await videoTrack.load(.timeRange)
        let sourceDuration = exportSourceDuration(assetDuration: assetDuration, videoTrackTimeRange: videoTrackTimeRange)
        let frameDuration = try await options.frameRate.frameDuration(for: videoTrack)
        let normalizedSourceSize = normalizedSize(for: naturalSize, preferredTransform: preferredTransform)
        let cropRect = normalizedCropRect(for: options.cropSelection, sourceSize: normalizedSourceSize)
        let outputSize = resolvedOutputSize(for: cropRect.size, options: options)
        let cursorTrack = options.cursorTelemetryURL
            .flatMap { try? CursorTelemetryPayload.load(from: $0) }
            .map(CursorTelemetryTrack.init(payload:))

        let exportAsset = try await makeEditedAsset(
            from: asset,
            sourceDuration: sourceDuration,
            edits: edits,
            facecamURL: options.facecamVideoURL,
            facecamOffsetMs: options.facecamOffsetMs
        )

        let duration = max(0.001, exportAsset.duration)
        let videoComposition = makeVideoComposition(
            for: exportAsset.videoTrack ?? videoTrack,
            sourceSize: naturalSize,
            preferredTransform: preferredTransform,
            cropRect: cropRect,
            outputSize: outputSize,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            frameDuration: frameDuration,
            styling: options.styling,
            edits: edits,
            editPlan: exportAsset.plan,
            cursorTrack: cursorTrack,
            cursorSettings: options.cursorOverlay,
            facecamTrack: exportAsset.facecamVideoTrack,
            facecamPreferredTransform: exportAsset.facecamPreferredTransform,
            facecamNormalizedSize: exportAsset.facecamNormalizedSize,
            facecamFallbackSettings: options.facecamFallbackSettings
        )

        return RenderContext(
            asset: exportAsset.asset,
            videoComposition: videoComposition,
            duration: duration,
            outputSize: outputSize,
            frameDuration: frameDuration
        )
    }

    private static func exportMovie(
        context: RenderContext,
        targetURL: URL,
        options: VideoExportOptions,
        cancellationToken: VideoExportCancellationToken?,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard let fileType = options.format.avFileType else {
            throw VideoExportRendererError.unsupportedFormat
        }
        guard let exportSession = AVAssetExportSession(asset: context.asset, presetName: exportPresetName(for: options)) else {
            throw VideoExportRendererError.exportSessionUnavailable
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: context.duration, preferredTimescale: 600)
        )
        exportSession.videoComposition = context.videoComposition

        if Task.isCancelled {
            throw VideoExportRendererError.exportCancelled
        }

        progressHandler(0.02)
        let progressTask = Task { @MainActor in
            for await state in exportSession.states(updateInterval: 0.12) {
                if Task.isCancelled {
                    return
                }
                if cancellationToken?.isCancelled == true {
                    return
                }
                if case .exporting(let progress) = state {
                    let fraction = progress.fractionCompleted
                    if fraction.isFinite {
                        progressHandler(min(max(fraction, 0.02), 0.99))
                    }
                }
            }
        }
        defer {
            progressTask.cancel()
        }

        do {
            try await exportSession.export(to: targetURL, as: fileType)
            if cancellationToken?.isCancelled == true || Task.isCancelled {
                throw VideoExportRendererError.exportCancelled
            }
            progressHandler(1)
        } catch is CancellationError {
            throw VideoExportRendererError.exportCancelled
        } catch {
            if cancellationToken?.isCancelled == true || Task.isCancelled {
                throw VideoExportRendererError.exportCancelled
            }
            throw error
        }
    }

    private static func exportGIF(
        context: RenderContext,
        targetURL: URL,
        options: VideoExportOptions,
        cancellationToken: VideoExportCancellationToken?,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        let framesPerSecond = options.frameRate.fixedFramesPerSecond ?? Double(VideoExportFrameRate.defaultGIFExportOption.fixedFramesPerSecond ?? 15)
        let frameDelay = 1 / max(framesPerSecond, 1)
        let frameCount = max(1, Int(ceil(context.duration * framesPerSecond)))
        guard let destination = CGImageDestinationCreateWithURL(
            targetURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw VideoExportRendererError.gifDestinationUnavailable
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: options.gifLoops ? 0 : 1
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]

        nonisolated(unsafe) let generator = AVAssetImageGenerator(asset: context.asset)
        generator.videoComposition = context.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        for frameIndex in 0..<frameCount {
            if Task.isCancelled || cancellationToken?.isCancelled == true {
                throw VideoExportRendererError.exportCancelled
            }

            let seconds = min(Double(frameIndex) * frameDelay, max(0, context.duration - 0.001))
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let image = try await generator.image(at: time).image
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            } catch is CancellationError {
                throw VideoExportRendererError.exportCancelled
            } catch {
                throw VideoExportRendererError.gifFrameGenerationFailed
            }

            progressHandler(min(max(Double(frameIndex + 1) / Double(frameCount), 0.02), 0.99))
        }

        guard CGImageDestinationFinalize(destination) else {
            throw VideoExportRendererError.gifDestinationUnavailable
        }
        progressHandler(1)
    }

    private static func exportPresetName(for options: VideoExportOptions) -> String {
        switch options.format {
        case .mp4:
            options.quality.exportPresetName
        case .mov, .gif:
            AVAssetExportPresetHighestQuality
        }
    }

    private static func effectiveResolution(for options: VideoExportOptions) -> VideoExportResolution {
        switch options.format {
        case .gif:
            options.gifSize.resolution
        case .mov, .mp4:
            options.resolution
        }
    }

    private struct EditedAsset {
        var asset: AVAsset
        var videoTrack: AVAssetTrack?
        var facecamVideoTrack: AVAssetTrack?
        var facecamPreferredTransform: CGAffineTransform = .identity
        var facecamNormalizedSize: CGSize = .zero
        var duration: Double
        var plan: TimelineExportEditPlan
    }

    struct MediaTrackInsertion: Equatable {
        var sourceRange: CMTimeRange
        var outputStart: CMTime
        var scaledDuration: CMTime
    }

    nonisolated static func mediaInsertion(
        for segment: TimelineExportEditPlan.Segment,
        availableSourceRange: CMTimeRange,
        sourceOffsetSeconds: Double = 0,
        preferredTimescale: CMTimeScale = 600
    ) -> MediaTrackInsertion? {
        let segmentSourceStart = segment.sourceStart - sourceOffsetSeconds
        let segmentSourceEnd = segment.sourceEnd - sourceOffsetSeconds
        let availableStart = availableSourceRange.start.seconds
        let availableEnd = availableSourceRange.end.seconds
        guard segmentSourceStart.isFinite,
              segmentSourceEnd.isFinite,
              availableStart.isFinite,
              availableEnd.isFinite else {
            return nil
        }

        let clippedStart = max(availableStart, segmentSourceStart)
        let clippedEnd = min(availableEnd, segmentSourceEnd)
        guard clippedEnd - clippedStart > 0.001 else { return nil }

        let speed = max(0.05, segment.speed)
        let outputStartSeconds = segment.outputStart + (clippedStart - segmentSourceStart) / speed
        let outputDurationSeconds = (clippedEnd - clippedStart) / speed
        return MediaTrackInsertion(
            sourceRange: CMTimeRange(
                start: CMTime(seconds: clippedStart, preferredTimescale: preferredTimescale),
                end: CMTime(seconds: clippedEnd, preferredTimescale: preferredTimescale)
            ),
            outputStart: CMTime(seconds: outputStartSeconds, preferredTimescale: preferredTimescale),
            scaledDuration: CMTime(seconds: outputDurationSeconds, preferredTimescale: preferredTimescale)
        )
    }

    private static func makeEditedAsset(
        from asset: AVAsset,
        sourceDuration: Double,
        edits: TimelineEditSnapshot,
        facecamURL: URL?,
        facecamOffsetMs: Int?
    ) async throws -> EditedAsset {
        let plan = TimelineExportEditPlan.build(duration: sourceDuration, edits: edits)
        let facecamAsset = facecamURL.map { AVURLAsset(url: $0) }
        let facecamTracks = try await facecamAsset?.loadTracks(withMediaType: .video) ?? []
        let facecamSourceTrack = facecamTracks.first
        guard edits.trimRegions.isEmpty == false || edits.hasClipSpeedEdits || facecamSourceTrack != nil else {
            return EditedAsset(asset: asset, videoTrack: nil, duration: sourceDuration, plan: plan)
        }
        guard plan.segments.isEmpty == false else {
            throw VideoExportRendererError.emptyTimeline
        }

        let composition = AVMutableComposition()
        let mediaTypes: [AVMediaType] = [.video, .audio]
        var compositionVideoTrack: AVMutableCompositionTrack?
        for mediaType in mediaTypes {
            let tracks = try await asset.loadTracks(withMediaType: mediaType)
            for sourceTrack in tracks {
                guard let compositionTrack = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    continue
                }
                if mediaType == .video, compositionVideoTrack == nil {
                    compositionVideoTrack = compositionTrack
                }
                let sourceTrackTimeRange = try await sourceTrack.load(.timeRange)
                for segment in plan.segments {
                    guard let insertion = mediaInsertion(
                        for: segment,
                        availableSourceRange: sourceTrackTimeRange
                    ) else {
                        continue
                    }

                    try compositionTrack.insertTimeRange(insertion.sourceRange, of: sourceTrack, at: insertion.outputStart)
                    let outputRange = CMTimeRange(start: insertion.outputStart, duration: insertion.sourceRange.duration)
                    compositionTrack.scaleTimeRange(
                        outputRange,
                        toDuration: insertion.scaledDuration
                    )
                    compositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
                }
            }
        }

        var compositionFacecamTrack: AVMutableCompositionTrack?
        var facecamPreferredTransform = CGAffineTransform.identity
        var facecamNormalizedSize = CGSize.zero
        if let facecamSourceTrack {
            let facecamTrackTimeRange = try await facecamSourceTrack.load(.timeRange)
            facecamPreferredTransform = (try? await facecamSourceTrack.load(.preferredTransform)) ?? .identity
            let facecamNaturalSize = (try? await facecamSourceTrack.load(.naturalSize)) ?? .zero
            facecamNormalizedSize = normalizedSize(for: facecamNaturalSize, preferredTransform: facecamPreferredTransform)
            let offsetSeconds = Double(facecamOffsetMs ?? 0) / 1000
            let facecamTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            compositionFacecamTrack = facecamTrack
            facecamTrack?.preferredTransform = facecamPreferredTransform

            for segment in plan.segments {
                guard let insertion = mediaInsertion(
                    for: segment,
                    availableSourceRange: facecamTrackTimeRange,
                    sourceOffsetSeconds: offsetSeconds
                ) else {
                    continue
                }

                try facecamTrack?.insertTimeRange(insertion.sourceRange, of: facecamSourceTrack, at: insertion.outputStart)
                let outputRange = CMTimeRange(start: insertion.outputStart, duration: insertion.sourceRange.duration)
                facecamTrack?.scaleTimeRange(
                    outputRange,
                    toDuration: insertion.scaledDuration
                )
            }
        }

        return EditedAsset(
            asset: composition,
            videoTrack: compositionVideoTrack,
            facecamVideoTrack: compositionFacecamTrack,
            facecamPreferredTransform: facecamPreferredTransform,
            facecamNormalizedSize: facecamNormalizedSize,
            duration: plan.outputDuration,
            plan: plan
        )
    }

    static func resolvedOutputSize(for sourceSize: CGSize, options: VideoExportOptions) -> CGSize {
        let resolution = effectiveResolution(for: options)
        if resolution == .custom, let customOutputSize = options.customOutputSize {
            return evenSize(width: customOutputSize.width, height: customOutputSize.height)
        }

        let sourceWidth = max(abs(sourceSize.width), 2)
        let sourceHeight = max(abs(sourceSize.height), 2)
        let aspectRatio = resolvedAspectRatio(
            options.aspectPreset.aspectRatio(forExportSourceSize: CGSize(width: sourceWidth, height: sourceHeight))
        )
        if let targetShortEdge = resolution.targetShortEdge {
            return outputSize(forAspectRatio: aspectRatio, targetShortEdge: targetShortEdge)
        }
        if let targetLongEdge = resolution.targetLongEdge {
            return outputSize(forAspectRatio: aspectRatio, targetLongEdge: targetLongEdge)
        }

        return sourceSizedCanvas(
            width: sourceWidth,
            height: sourceHeight,
            aspectRatio: aspectRatio
        )
    }

    nonisolated static func exportSourceDuration(assetDuration: CMTime, videoTrackTimeRange: CMTimeRange) -> Double {
        let assetSeconds = assetDuration.seconds
        let videoEndSeconds = videoTrackTimeRange.end.seconds
        let candidates = [assetSeconds, videoEndSeconds].filter { $0.isFinite && $0 > 0 }
        guard let shortest = candidates.min() else { return 0 }
        return shortest
    }

    private static func outputSize(forAspectRatio aspectRatio: CGFloat, targetShortEdge: CGFloat) -> CGSize {
        if aspectRatio >= 1 {
            return evenSize(width: targetShortEdge * aspectRatio, height: targetShortEdge)
        }
        return evenSize(width: targetShortEdge, height: targetShortEdge / aspectRatio)
    }

    private static func outputSize(forAspectRatio aspectRatio: CGFloat, targetLongEdge: CGFloat) -> CGSize {
        if aspectRatio >= 1 {
            return evenSize(width: targetLongEdge, height: targetLongEdge / aspectRatio)
        }
        return evenSize(width: targetLongEdge * aspectRatio, height: targetLongEdge)
    }

    private static func sourceSizedCanvas(width sourceWidth: CGFloat, height sourceHeight: CGFloat, aspectRatio: CGFloat) -> CGSize {
        let sourceAspectRatio = sourceWidth / max(sourceHeight, 1)
        if sourceAspectRatio > aspectRatio {
            return evenSize(width: sourceWidth, height: sourceWidth / aspectRatio)
        }
        return evenSize(width: sourceHeight * aspectRatio, height: sourceHeight)
    }

    private static func resolvedAspectRatio(_ aspectRatio: CGFloat) -> CGFloat {
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return PreviewStageLayout.videoAspectRatio
        }
        return aspectRatio
    }

    private static func evenSize(width: CGFloat, height: CGFloat) -> CGSize {
        VideoCropGeometry.evenSize(CGSize(width: width, height: height))
    }

    static func normalizedSize(for naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let naturalRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: max(abs(naturalRect.width), 2), height: max(abs(naturalRect.height), 2))
    }

    static func normalizedCropRect(for selection: VideoCropSelection?, sourceSize: CGSize) -> CGRect {
        guard let selection else {
            return CGRect(origin: .zero, size: VideoCropSelection.safeSourceSize(sourceSize))
        }
        return VideoCropSelection.clampedPixelRect(selection.pixelRect(in: sourceSize), in: sourceSize)
    }

    private static func makeVideoComposition(
        for videoTrack: AVAssetTrack,
        sourceSize: CGSize,
        preferredTransform: CGAffineTransform,
        cropRect: CGRect,
        outputSize: CGSize,
        duration: CMTime,
        frameDuration: CMTime,
        styling: VideoBackgroundStyling,
        edits: TimelineEditSnapshot = .empty,
        editPlan: TimelineExportEditPlan = TimelineExportEditPlan(segments: [], outputDuration: 0),
        cursorTrack: CursorTelemetryTrack? = nil,
        cursorSettings: CursorOverlaySettings = .hidden,
        facecamTrack: AVAssetTrack? = nil,
        facecamPreferredTransform: CGAffineTransform = .identity,
        facecamNormalizedSize: CGSize = .zero,
        facecamFallbackSettings: FacecamSettings? = nil
    ) -> AVMutableVideoComposition {
        let naturalRect = CGRect(origin: .zero, size: sourceSize).applying(preferredTransform)
        let normalizedTransform = preferredTransform.translatedBy(x: -naturalRect.origin.x, y: -naturalRect.origin.y)
        let normalizedSize = CGSize(width: abs(naturalRect.width), height: abs(naturalRect.height))
        let clampedCropRect = VideoCropSelection.clampedPixelRect(cropRect, in: normalizedSize)
        let cropSize = clampedCropRect.size
        let scale = min(outputSize.width / max(cropSize.width, 1), outputSize.height / max(cropSize.height, 1))
        let scaledSize = CGSize(width: cropSize.width * scale, height: cropSize.height * scale)
        let translation = CGAffineTransform(
            translationX: (outputSize.width - scaledSize.width) / 2,
            y: (outputSize.height - scaledSize.height) / 2
        )
        let cropTranslation = CGAffineTransform(translationX: -clampedCropRect.minX, y: -clampedCropRect.minY)
        let transform = normalizedTransform
            .concatenating(cropTranslation)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(translation)

        if styling.isPassthrough, facecamTrack == nil {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]

            let composition = AVMutableVideoComposition()
            composition.renderSize = outputSize
            composition.frameDuration = frameDuration
            composition.instructions = [instruction]
            if needsFinalCanvasOverlayTool(edits: edits, cursorTrack: cursorTrack, cursorSettings: cursorSettings) {
                let contentRect = exportSourceContentRect(
                    renderSize: outputSize,
                    cropSize: clampedCropRect.size,
                    styling: .none
                )
                composition.animationTool = makeOverlayTool(
                    outputSize: outputSize,
                    contentRect: contentRect,
                    cropRect: clampedCropRect,
                    sourceSize: normalizedSize,
                    edits: edits,
                    editPlan: editPlan,
                    cursorTrack: cursorTrack,
                    cursorSettings: cursorSettings
                )
            }
            return composition
        }

        let instruction = VideoBackgroundCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            trackID: videoTrack.trackID,
            facecamTrackID: facecamTrack?.trackID,
            styling: styling,
            preferredTransform: normalizedTransform,
            normalizedSize: normalizedSize,
            facecamPreferredTransform: facecamPreferredTransform,
            facecamNormalizedSize: facecamNormalizedSize,
            cropRect: clampedCropRect,
            renderSize: outputSize,
            edits: edits,
            editPlan: editPlan,
            cursorTrack: cursorTrack,
            cursorSettings: cursorSettings,
            facecamFallbackSettings: facecamFallbackSettings
        )

        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = VideoBackgroundCompositor.self
        composition.renderSize = outputSize
        composition.frameDuration = frameDuration
        composition.instructions = [instruction]
        if needsFinalCanvasOverlayTool(edits: edits, cursorTrack: nil, cursorSettings: .hidden) {
            let contentRect = exportSourceContentRect(
                renderSize: outputSize,
                cropSize: clampedCropRect.size,
                styling: styling
            )
            composition.animationTool = makeOverlayTool(
                outputSize: outputSize,
                contentRect: contentRect,
                cropRect: clampedCropRect,
                sourceSize: normalizedSize,
                edits: edits,
                editPlan: editPlan,
                cursorTrack: cursorTrack,
                cursorSettings: .hidden
            )
        }
        return composition
    }

    nonisolated static func needsFinalCanvasOverlayTool(edits: TimelineEditSnapshot, cursorTrack: CursorTelemetryTrack?, cursorSettings: CursorOverlaySettings) -> Bool {
        edits.zoomRegions.isEmpty == false ||
            edits.annotationRegions.isEmpty == false ||
            edits.cameraClips.isEmpty == false ||
            (cursorSettings.clamped.isVisible && cursorTrack?.samples.isEmpty == false)
    }

    private static func makeOverlayTool(
        outputSize: CGSize,
        contentRect: CGRect,
        cropRect: CGRect,
        sourceSize: CGSize,
        edits: TimelineEditSnapshot,
        editPlan: TimelineExportEditPlan,
        cursorTrack: CursorTelemetryTrack?,
        cursorSettings: CursorOverlaySettings
    ) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: outputSize)
        let contentLayer = CALayer()
        contentLayer.bounds = parentLayer.bounds
        contentLayer.anchorPoint = .zero
        contentLayer.position = .zero
        parentLayer.addSublayer(contentLayer)

        let videoLayer = CALayer()
        videoLayer.frame = contentLayer.bounds
        contentLayer.addSublayer(videoLayer)

        for annotation in edits.annotationRegions {
            for outputSpan in editPlan.outputSpans(forSourceSpan: annotation.span) {
                let textLayer = CATextLayer()
                textLayer.string = annotation.text
                textLayer.fontSize = annotation.fontSize
                textLayer.alignmentMode = .center
                textLayer.foregroundColor = NSColor.white.cgColor
                textLayer.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
                textLayer.cornerRadius = 10
                textLayer.masksToBounds = true
                let width = min(outputSize.width * 0.72, max(180, CGFloat(annotation.text.count * 18)))
                let height = annotation.fontSize + 24
                textLayer.frame = CGRect(x: outputSize.width * annotation.x - width / 2, y: outputSize.height * (1 - annotation.y) - height / 2, width: width, height: height)
                textLayer.opacity = 0

                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = [0, 1, 1, 0]
                animation.keyTimes = [0, 0.08, 0.92, 1]
                animation.beginTime = AVCoreAnimationBeginTimeAtZero + outputSpan.start
                animation.duration = max(0.05, outputSpan.duration)
                animation.isRemovedOnCompletion = false
                animation.fillMode = .both
                textLayer.add(animation, forKey: "visible")
                contentLayer.addSublayer(textLayer)
            }
        }

        if let cursorTrack, cursorSettings.clamped.isVisible {
            let cursorLayer = makeCursorLayer(
                outputSize: outputSize,
                contentRect: contentRect,
                cropRect: cropRect,
                sourceSize: sourceSize,
                edits: edits,
                editPlan: editPlan,
                track: cursorTrack,
                settings: cursorSettings
            )
            contentLayer.addSublayer(cursorLayer)
        }

        applyFinalCanvasZoomAnimations(
            to: contentLayer,
            outputSize: outputSize,
            edits: edits,
            editPlan: editPlan,
            cursorTrack: cursorTrack
        )
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }

    private static func applyFinalCanvasZoomAnimations(
        to layer: CALayer,
        outputSize: CGSize,
        edits: TimelineEditSnapshot,
        editPlan: TimelineExportEditPlan,
        cursorTrack: CursorTelemetryTrack?
    ) {
        guard edits.zoomRegions.isEmpty == false,
              editPlan.outputDuration > 0 else {
            return
        }

        let duration = max(0.001, editPlan.outputDuration)
        let sampleCount = max(2, min(9_000, Int(ceil(duration * 30)) + 1))
        let rect = CGRect(origin: .zero, size: outputSize)
        var values: [CATransform3D] = []
        var keyTimes: [NSNumber] = []

        for index in 0..<sampleCount {
            let progress = sampleCount == 1 ? 0 : Double(index) / Double(sampleCount - 1)
            let outputTime = duration * progress
            let effect = TimelineZoomCanvasTransform.activeEffect(
                edits: edits,
                editPlan: editPlan,
                outputTime: outputTime,
                cursorTrack: cursorTrack
            )
            let transform = TimelineZoomCanvasTransform.transform(for: effect, in: rect, flipsY: true)
            values.append(CATransform3DMakeAffineTransform(transform))
            keyTimes.append(NSNumber(value: progress))
        }

        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values
        animation.keyTimes = keyTimes
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.duration = duration
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        layer.add(animation, forKey: "final-canvas-zoom")
    }

    private static func makeCursorLayer(
        outputSize: CGSize,
        contentRect: CGRect,
        cropRect: CGRect,
        sourceSize: CGSize,
        edits: TimelineEditSnapshot,
        editPlan: TimelineExportEditPlan,
        track: CursorTelemetryTrack,
        settings: CursorOverlaySettings
    ) -> CALayer {
        let resolvedSettings = settings.clamped
        let cursorSize = CursorOverlayGeometry.glyphSize(
            contentRect: contentRect,
            cropRect: cropRect,
            settings: resolvedSettings
        )
        let cursorLayer = CALayer()
        guard let glyph = CursorStyleRenderer.renderedGlyph(styleID: resolvedSettings.styleID, size: cursorSize) else {
            return cursorLayer
        }
        cursorLayer.bounds = CGRect(origin: .zero, size: glyph.canvasSize)
        cursorLayer.anchorPoint = glyph.coreAnimationAnchorPoint
        cursorLayer.contents = glyph.image
        cursorLayer.contentsGravity = .resize
        cursorLayer.magnificationFilter = .linear
        cursorLayer.minificationFilter = .linear

        let duration = max(0.001, editPlan.outputDuration)
        let sampleCount = max(2, min(9_000, Int(ceil(duration * 30)) + 1))
        var values: [CGPoint] = []
        var keyTimes: [NSNumber] = []

        for index in 0..<sampleCount {
            let progress = sampleCount == 1 ? 0 : Double(index) / Double(sampleCount - 1)
            let outputTime = duration * progress
            let sourceTime = editPlan.sourceTime(forOutputTime: outputTime) ?? outputTime
            guard let point = track.point(at: sourceTime, settings: resolvedSettings) else {
                continue
            }
            let mapped = cursorOutputPoint(
                telemetryPoint: point,
                outputTime: outputTime,
                outputSize: outputSize,
                contentRect: contentRect,
                cropRect: cropRect,
                sourceSize: sourceSize,
                edits: edits,
                editPlan: editPlan,
                track: track
            )
            values.append(mapped)
            keyTimes.append(NSNumber(value: progress))
        }

        cursorLayer.position = values.first ?? CGPoint(x: contentRect.minX, y: contentRect.maxY)
        if values.count > 1 {
            let animation = CAKeyframeAnimation(keyPath: "position")
            animation.values = values
            animation.keyTimes = keyTimes
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.duration = duration
            animation.calculationMode = .linear
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            cursorLayer.add(animation, forKey: "cursor-position")
        }

        return cursorLayer
    }

    private static func cursorOutputPoint(
        telemetryPoint: CGPoint,
        outputTime: Double,
        outputSize: CGSize,
        contentRect: CGRect,
        cropRect: CGRect,
        sourceSize: CGSize,
        edits: TimelineEditSnapshot,
        editPlan: TimelineExportEditPlan,
        track: CursorTelemetryTrack
    ) -> CGPoint {
        let telemetryWidth = CGFloat(max(track.width, 1))
        let telemetryHeight = CGFloat(max(track.height, 1))
        let sourcePoint = CGPoint(
            x: CGFloat(telemetryPoint.x) / telemetryWidth * sourceSize.width,
            y: CGFloat(telemetryPoint.y) / telemetryHeight * sourceSize.height
        )
        let cropRelativeX = sourcePoint.x - cropRect.minX
        let cropRelativeY = sourcePoint.y - cropRect.minY
        let scale = min(contentRect.width / max(cropRect.width, 1), contentRect.height / max(cropRect.height, 1))
        let scaledSize = CGSize(width: cropRect.width * scale, height: cropRect.height * scale)
        let placedRect = CGRect(
            x: contentRect.midX - scaledSize.width / 2,
            y: contentRect.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )

        var point = CGPoint(
            x: placedRect.minX + cropRelativeX * scale,
            y: placedRect.maxY - cropRelativeY * scale
        )

        point.x = min(max(point.x, 0), outputSize.width)
        point.y = min(max(point.y, 0), outputSize.height)
        return point
    }

    private static func exportSourceContentRect(renderSize: CGSize, cropSize: CGSize, styling: VideoBackgroundStyling) -> CGRect {
        let renderRect = CGRect(origin: .zero, size: renderSize)
        let minDim = min(renderSize.width, renderSize.height)
        let pad = styling.paddingRatio * minDim
        let innerSize = CGSize(
            width: max(2, renderSize.width - 2 * pad),
            height: max(2, renderSize.height - 2 * pad)
        )
        let innerRect = CGRect(
            x: renderRect.midX - innerSize.width / 2,
            y: renderRect.midY - innerSize.height / 2,
            width: innerSize.width,
            height: innerSize.height
        )
        let frameScale = min(innerSize.width / max(cropSize.width, 1), innerSize.height / max(cropSize.height, 1))
        let frameSize = CGSize(width: cropSize.width * frameScale, height: cropSize.height * frameScale)
        let frameRect = CGRect(
            x: innerRect.midX - frameSize.width / 2,
            y: innerRect.midY - frameSize.height / 2,
            width: frameSize.width,
            height: frameSize.height
        )
        guard styling.inset.isEnabled else { return frameRect }
        let coreImageBalance = VideoInsetBalance(
            left: styling.inset.balance.left,
            top: 1 - styling.inset.balance.top
        )
        return VideoInsetGeometry.contentRect(
            in: frameRect,
            amountRatio: styling.inset.amountRatio,
            balance: coreImageBalance
        )
    }

}
