import AVFoundation
import AppKit
import CoreGraphics
import Foundation
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
    case fps15
    case fps24
    case fps30
    case fps60

    var id: String { rawValue }

    static let exportOptions: [VideoExportFrameRate] = [.fps15, .fps24, .fps30, .fps60]

    static let defaultExportOption: VideoExportFrameRate = .fps30

    var title: String {
        switch self {
        case .source: "Source"
        case .fps15: "15 FPS"
        case .fps24: "24 FPS"
        case .fps30: "30 FPS"
        case .fps60: "60 FPS"
        }
    }

    var detail: String {
        switch self {
        case .source: "Keep the recording frame rate."
        case .fps15: "Smallest file size."
        case .fps24: "Cinematic motion."
        case .fps30: "Smaller file, smooth playback."
        case .fps60: "Best for fast cursor movement."
        }
    }

    var fileSuffix: String {
        switch self {
        case .source: "source-fps"
        case .fps15: "15fps"
        case .fps24: "24fps"
        case .fps30: "30fps"
        case .fps60: "60fps"
        }
    }

    private var fixedFramesPerSecond: Double? {
        switch self {
        case .source: nil
        case .fps15: 15
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
    var styling: VideoBackgroundStyling
    var cropSelection: VideoCropSelection?
    var customOutputSize: CGSize?
    var cursorOverlay: CursorOverlaySettings = .hidden
    var cursorTelemetryURL: URL? = nil

    static let `default` = VideoExportOptions(
        resolution: VideoExportResolution.defaultExportOption,
        format: .mov,
        frameRate: VideoExportFrameRate.defaultExportOption,
        styling: .none,
        cropSelection: nil,
        customOutputSize: nil,
        cursorOverlay: .hidden,
        cursorTelemetryURL: nil
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

    func withCursorOverlay(_ settings: CursorOverlaySettings, telemetryURL: URL?) -> VideoExportOptions {
        var copy = self
        copy.cursorOverlay = settings.clamped
        copy.cursorTelemetryURL = telemetryURL
        return copy
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
        let normalizedSourceSize = normalizedSize(for: naturalSize, preferredTransform: preferredTransform)
        let cropRect = normalizedCropRect(for: options.cropSelection, sourceSize: normalizedSourceSize)
        let outputSize = resolvedOutputSize(for: cropRect.size, options: options)
        let cursorTrack = options.cursorTelemetryURL
            .flatMap { try? CursorTelemetryPayload.load(from: $0) }
            .map(CursorTelemetryTrack.init(payload:))

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
            cropRect: cropRect,
            outputSize: outputSize,
            duration: CMTime(seconds: max(0.001, exportAsset.duration), preferredTimescale: 600),
            frameDuration: frameDuration,
            styling: options.styling,
            edits: edits,
            editPlan: exportAsset.plan,
            cursorTrack: cursorTrack,
            cursorSettings: options.cursorOverlay
        )

        if Task.isCancelled {
            throw VideoExportRendererError.exportCancelled
        }

        if let cancellationToken {
            cancellationToken.attach(exportSession)
        }

        progressHandler(0.02)
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                if cancellationToken?.isCancelled == true {
                    return
                }
                let progress = Double(exportSession.progress)
                if progress.isFinite {
                    progressHandler(min(max(progress, 0.02), 0.99))
                }

                do {
                    try await Task.sleep(nanoseconds: 120_000_000)
                } catch {
                    return
                }
            }
        }
        defer {
            progressTask.cancel()
        }

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
        guard edits.trimRegions.isEmpty == false || edits.hasClipSpeedEdits else {
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
            videoTrack: compositionVideoTrack,
            duration: plan.outputDuration,
            plan: plan
        )
    }

    static func resolvedOutputSize(for sourceSize: CGSize, options: VideoExportOptions) -> CGSize {
        if options.resolution == .custom, let customOutputSize = options.customOutputSize {
            return evenSize(width: customOutputSize.width, height: customOutputSize.height)
        }

        let sourceWidth = max(abs(sourceSize.width), 2)
        let sourceHeight = max(abs(sourceSize.height), 2)
        if let targetShortEdge = options.resolution.targetShortEdge {
            let shortEdge = min(sourceWidth, sourceHeight)
            let scale = targetShortEdge / max(shortEdge, 1)
            return evenSize(width: sourceWidth * scale, height: sourceHeight * scale)
        }
        guard let targetLongEdge = options.resolution.targetLongEdge else {
            return evenSize(width: sourceWidth, height: sourceHeight)
        }

        let longEdge = max(sourceWidth, sourceHeight)
        let scale = targetLongEdge / longEdge
        return evenSize(width: sourceWidth * scale, height: sourceHeight * scale)
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
        cursorSettings: CursorOverlaySettings = .hidden
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

        if styling.isPassthrough {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            applyZoomTransforms(to: layerInstruction, baseTransform: transform, outputSize: outputSize, edits: edits, editPlan: editPlan)
            instruction.layerInstructions = [layerInstruction]

            let composition = AVMutableVideoComposition()
            composition.renderSize = outputSize
            composition.frameDuration = frameDuration
            composition.instructions = [instruction]
            if needsOverlayTool(edits: edits, cursorTrack: cursorTrack, cursorSettings: cursorSettings) {
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
            styling: styling,
            preferredTransform: normalizedTransform,
            normalizedSize: normalizedSize,
            cropRect: clampedCropRect,
            renderSize: outputSize,
            edits: edits,
            editPlan: editPlan,
            cursorTrack: cursorTrack,
            cursorSettings: cursorSettings
        )

        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = VideoBackgroundCompositor.self
        composition.renderSize = outputSize
        composition.frameDuration = frameDuration
        composition.instructions = [instruction]
        if edits.annotationRegions.isEmpty == false {
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
                cursorTrack: nil,
                cursorSettings: .hidden
            )
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
            let duration = end - start
            let rampIn = min(TimelineZoomAnimator.rampInSeconds, duration * 0.4)
            let rampOut = min(TimelineZoomAnimator.rampOutSeconds, duration * 0.4)
            let holdStart = start + rampIn
            let holdEnd = max(holdStart, end - rampOut)

            if rampIn > 0 {
                layerInstruction.setTransformRamp(
                    fromStart: baseTransform,
                    toEnd: zoomTransform,
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: start, preferredTimescale: 600),
                        duration: CMTime(seconds: rampIn, preferredTimescale: 600)
                    )
                )
            } else {
                layerInstruction.setTransform(zoomTransform, at: CMTime(seconds: start, preferredTimescale: 600))
            }

            layerInstruction.setTransform(zoomTransform, at: CMTime(seconds: holdStart, preferredTimescale: 600))
            if rampOut > 0 {
                layerInstruction.setTransformRamp(
                    fromStart: zoomTransform,
                    toEnd: baseTransform,
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: holdEnd, preferredTimescale: 600),
                        duration: CMTime(seconds: max(0, end - holdEnd), preferredTimescale: 600)
                    )
                )
            }
            layerInstruction.setTransform(baseTransform, at: CMTime(seconds: end, preferredTimescale: 600))
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

    private static func needsOverlayTool(edits: TimelineEditSnapshot, cursorTrack: CursorTelemetryTrack?, cursorSettings: CursorOverlaySettings) -> Bool {
        edits.annotationRegions.isEmpty == false || (cursorSettings.clamped.isVisible && cursorTrack?.samples.isEmpty == false)
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
            parentLayer.addSublayer(cursorLayer)
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
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
        let baseSize = max(14, min(52, min(contentRect.width, contentRect.height) * 0.032))
        let cursorSize = baseSize * resolvedSettings.size
        let cursorLayer = CALayer()
        guard let glyph = CursorPresetRenderer.renderedGlyph(
            style: resolvedSettings.style,
            variant: resolvedSettings.variant,
            size: cursorSize
        ) else {
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

        if let zoomEffect = activeZoomEffect(edits: edits, editPlan: editPlan, outputTime: outputTime) {
            let focus = CGPoint(
                x: placedRect.minX + placedRect.width * CGFloat(zoomEffect.focusX),
                y: placedRect.minY + placedRect.height * CGFloat(1 - zoomEffect.focusY)
            )
            let depth = CGFloat(max(1, zoomEffect.depth))
            point = CGPoint(
                x: focus.x + (point.x - focus.x) * depth,
                y: focus.y + (point.y - focus.y) * depth
            )
        }

        point.x = min(max(point.x, 0), outputSize.width)
        point.y = min(max(point.y, 0), outputSize.height)
        return point
    }

    private static func activeZoomEffect(edits: TimelineEditSnapshot, editPlan: TimelineExportEditPlan, outputTime: Double) -> TimelineZoomEffect? {
        guard outputTime.isFinite else { return nil }
        let activeZoom = edits.zoomRegions
            .sorted { $0.span.start < $1.span.start }
            .last { zoom in
                let start = editPlan.outputTime(forSourceTime: zoom.span.start) ?? zoom.span.start
                let end = editPlan.outputTime(forSourceTime: zoom.span.end) ?? zoom.span.end
                return outputTime >= start && outputTime < end
            }
        guard let zoom = activeZoom else { return nil }

        let start = editPlan.outputTime(forSourceTime: zoom.span.start) ?? zoom.span.start
        let end = editPlan.outputTime(forSourceTime: zoom.span.end) ?? zoom.span.end
        let outputSpan = TimelineSpan(start: start, end: end)
        let progress = TimelineZoomAnimator.animationProgress(for: outputSpan, at: outputTime)
        return TimelineZoomEffect(
            depth: 1 + (max(1, zoom.depth) - 1) * progress,
            focusX: zoom.focusX,
            focusY: zoom.focusY
        )
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
