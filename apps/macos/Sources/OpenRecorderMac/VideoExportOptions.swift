import AVFoundation
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum VideoExportResolution: String, CaseIterable, Identifiable {
    case source
    case twoK
    case fourK

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: "Source"
        case .twoK: "2K"
        case .fourK: "4K"
        }
    }

    var detail: String {
        switch self {
        case .source: "Keep the recording dimensions."
        case .twoK: "Scale the long edge to 2560 px."
        case .fourK: "Scale the long edge to 3840 px."
        }
    }

    var fileSuffix: String {
        switch self {
        case .source: "source"
        case .twoK: "2k"
        case .fourK: "4k"
        }
    }

    var targetLongEdge: CGFloat? {
        switch self {
        case .source: nil
        case .twoK: 2560
        case .fourK: 3840
        }
    }
}

enum VideoExportFormat: String, CaseIterable, Identifiable {
    case mov

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mov: "MOV"
        }
    }

    var fileExtension: String {
        switch self {
        case .mov: "mov"
        }
    }

    var contentType: UTType {
        switch self {
        case .mov: .quickTimeMovie
        }
    }

    var avFileType: AVFileType {
        switch self {
        case .mov: .mov
        }
    }
}

enum VideoExportFrameRate: String, CaseIterable, Identifiable {
    case source
    case fps24
    case fps30
    case fps60

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: "Source"
        case .fps24: "24 FPS"
        case .fps30: "30 FPS"
        case .fps60: "60 FPS"
        }
    }

    var detail: String {
        switch self {
        case .source: "Keep the recording frame rate."
        case .fps24: "Cinematic motion."
        case .fps30: "Smaller file, smooth playback."
        case .fps60: "Best for fast cursor movement."
        }
    }

    var fileSuffix: String {
        switch self {
        case .source: "source-fps"
        case .fps24: "24fps"
        case .fps30: "30fps"
        case .fps60: "60fps"
        }
    }

    private var fixedFramesPerSecond: Double? {
        switch self {
        case .source: nil
        case .fps24: 24
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

    static let `default` = VideoExportOptions(resolution: .source, format: .mov, frameRate: .source)
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
    private var exportSession: AVAssetExportSession?
    private(set) var isCancelled = false

    func attach(_ exportSession: AVAssetExportSession) {
        if isCancelled {
            exportSession.cancelExport()
        } else {
            self.exportSession = exportSession
        }
    }

    func cancel() {
        isCancelled = true
        exportSession?.cancelExport()
    }

    func detach() {
        exportSession = nil
    }
}

enum VideoExportRendererError: LocalizedError {
    case missingVideoTrack
    case exportSessionUnavailable
    case exportCancelled
    case emptyTimeline
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack: "The recording does not contain a video track."
        case .exportSessionUnavailable: "This Mac cannot create the requested export session."
        case .exportCancelled: "Export canceled."
        case .emptyTimeline: "Timeline edits remove the entire recording."
        case .exportFailed: "Video export failed."
        }
    }
}

@MainActor
enum VideoExportRenderer {
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

        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw VideoExportRendererError.missingVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let frameDuration = try await options.frameRate.frameDuration(for: videoTrack)
        let outputSize = outputSize(for: naturalSize.applying(preferredTransform), options: options)

        let exportAsset = try await makeEditedAsset(from: asset, duration: duration, edits: edits)

        guard let exportSession = AVAssetExportSession(asset: exportAsset.asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoExportRendererError.exportSessionUnavailable
        }

        exportSession.outputURL = targetURL
        exportSession.outputFileType = options.format.avFileType
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = makeVideoComposition(
            for: exportAsset.videoTrack ?? videoTrack,
            sourceSize: naturalSize,
            preferredTransform: preferredTransform,
            outputSize: outputSize,
            duration: CMTime(seconds: max(0.001, exportAsset.duration), preferredTimescale: 600),
            frameDuration: frameDuration,
            edits: edits,
            editPlan: exportAsset.plan
        )

        if Task.isCancelled {
            throw VideoExportRendererError.exportCancelled
        }

        if let cancellationToken {
            cancellationToken.attach(exportSession)
        }

        progressHandler(0.1)
        await exportSession.export()
        if let cancellationToken {
            cancellationToken.detach()
        }

        switch exportSession.status {
        case .completed:
            progressHandler(1)
            return
        case .cancelled:
            throw VideoExportRendererError.exportCancelled
        case .failed:
            throw exportSession.error ?? VideoExportRendererError.exportFailed
        default:
            throw VideoExportRendererError.exportFailed
        }
    }

    private struct EditedAsset {
        var asset: AVAsset
        var videoTrack: AVAssetTrack?
        var duration: Double
        var plan: TimelineExportEditPlan
    }

    private static func makeEditedAsset(from asset: AVAsset, duration: CMTime, edits: TimelineEditSnapshot) async throws -> EditedAsset {
        let sourceDuration = max(0, duration.seconds)
        let plan = TimelineExportEditPlan.build(duration: sourceDuration, edits: edits)
        guard edits.trimRegions.isEmpty == false || edits.speedRegions.isEmpty == false else {
            return EditedAsset(asset: asset, videoTrack: nil, duration: sourceDuration, plan: plan)
        }
        guard plan.segments.isEmpty == false else {
            throw VideoExportRendererError.emptyTimeline
        }

        let composition = AVMutableComposition()
        let mediaTypes: [AVMediaType] = [.video, .audio]
        for mediaType in mediaTypes {
            let tracks = try await asset.loadTracks(withMediaType: mediaType)
            for sourceTrack in tracks {
                guard let compositionTrack = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    continue
                }
                for segment in plan.segments {
                    let sourceRange = CMTimeRange(
                        start: CMTime(seconds: segment.sourceStart, preferredTimescale: 600),
                        end: CMTime(seconds: segment.sourceEnd, preferredTimescale: 600)
                    )
                    let outputStart = CMTime(seconds: segment.outputStart, preferredTimescale: 600)
                    try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: outputStart)
                    let outputRange = CMTimeRange(start: outputStart, duration: sourceRange.duration)
                    compositionTrack.scaleTimeRange(
                        outputRange,
                        toDuration: CMTime(seconds: segment.outputEnd - segment.outputStart, preferredTimescale: 600)
                    )
                    compositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
                }
            }
        }

        return EditedAsset(
            asset: composition,
            videoTrack: composition.tracks(withMediaType: .video).first,
            duration: plan.outputDuration,
            plan: plan
        )
    }

    private static func outputSize(for transformedSize: CGSize, options: VideoExportOptions) -> CGSize {
        let sourceWidth = max(abs(transformedSize.width), 2)
        let sourceHeight = max(abs(transformedSize.height), 2)
        guard let targetLongEdge = options.resolution.targetLongEdge else {
            return evenSize(width: sourceWidth, height: sourceHeight)
        }

        let longEdge = max(sourceWidth, sourceHeight)
        let scale = targetLongEdge / longEdge
        return evenSize(width: sourceWidth * scale, height: sourceHeight * scale)
    }

    private static func evenSize(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(
            width: max(2, floor(width / 2) * 2),
            height: max(2, floor(height / 2) * 2)
        )
    }

    private static func makeVideoComposition(
        for videoTrack: AVAssetTrack,
        sourceSize: CGSize,
        preferredTransform: CGAffineTransform,
        outputSize: CGSize,
        duration: CMTime,
        frameDuration: CMTime,
        edits: TimelineEditSnapshot = .empty,
        editPlan: TimelineExportEditPlan = TimelineExportEditPlan(segments: [], outputDuration: 0)
    ) -> AVMutableVideoComposition {
        let naturalRect = CGRect(origin: .zero, size: sourceSize).applying(preferredTransform)
        let normalizedTransform = preferredTransform.translatedBy(x: -naturalRect.origin.x, y: -naturalRect.origin.y)
        let normalizedSize = CGSize(width: abs(naturalRect.width), height: abs(naturalRect.height))
        let scale = min(outputSize.width / max(normalizedSize.width, 1), outputSize.height / max(normalizedSize.height, 1))
        let scaledSize = CGSize(width: normalizedSize.width * scale, height: normalizedSize.height * scale)
        let translation = CGAffineTransform(
            translationX: (outputSize.width - scaledSize.width) / 2,
            y: (outputSize.height - scaledSize.height) / 2
        )
        let transform = normalizedTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(translation)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        applyZoomTransforms(to: layerInstruction, baseTransform: transform, outputSize: outputSize, edits: edits, editPlan: editPlan)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = outputSize
        composition.frameDuration = frameDuration
        composition.instructions = [instruction]
        if edits.annotationRegions.isEmpty == false {
            composition.animationTool = makeAnnotationTool(outputSize: outputSize, edits: edits, editPlan: editPlan)
        }
        return composition
    }

    private static func applyZoomTransforms(to layerInstruction: AVMutableVideoCompositionLayerInstruction, baseTransform: CGAffineTransform, outputSize: CGSize, edits: TimelineEditSnapshot, editPlan: TimelineExportEditPlan) {
        layerInstruction.setTransform(baseTransform, at: .zero)
        for zoom in edits.zoomRegions {
            let start = editPlan.outputTime(forSourceTime: zoom.span.start) ?? zoom.span.start
            let end = editPlan.outputTime(forSourceTime: zoom.span.end) ?? zoom.span.end
            guard end > start else { continue }
            let zoomTransform = zoomedTransform(base: baseTransform, outputSize: outputSize, zoom: zoom)
            let timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
            layerInstruction.setTransform(zoomTransform, at: timeRange.start)
            layerInstruction.setTransform(baseTransform, at: timeRange.end)
        }
    }

    private static func zoomedTransform(base: CGAffineTransform, outputSize: CGSize, zoom: TimelineZoomRegion) -> CGAffineTransform {
        let scale = max(1, zoom.depth)
        let focus = CGPoint(x: outputSize.width * zoom.focusX, y: outputSize.height * zoom.focusY)
        let translateToFocus = CGAffineTransform(translationX: focus.x, y: focus.y)
        let zoomScale = CGAffineTransform(scaleX: scale, y: scale)
        let translateBack = CGAffineTransform(translationX: -focus.x, y: -focus.y)
        return base.concatenating(translateBack).concatenating(zoomScale).concatenating(translateToFocus)
    }

    private static func makeAnnotationTool(outputSize: CGSize, edits: TimelineEditSnapshot, editPlan: TimelineExportEditPlan) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: outputSize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        for annotation in edits.annotationRegions {
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

            let start = editPlan.outputTime(forSourceTime: annotation.span.start) ?? annotation.span.start
            let end = editPlan.outputTime(forSourceTime: annotation.span.end) ?? annotation.span.end
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0, 1, 1, 0]
            animation.keyTimes = [0, 0.08, 0.92, 1]
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
            animation.duration = max(0.05, end - start)
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            textLayer.add(animation, forKey: "visible")
            parentLayer.addSublayer(textLayer)
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }
}
