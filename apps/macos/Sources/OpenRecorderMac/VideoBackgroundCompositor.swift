import AVFoundation
import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal

struct VideoInsetBalance: Equatable, Hashable, Codable {
    var left: Double
    var top: Double

    static let centered = VideoInsetBalance(left: 0.5, top: 0.5)

    var clamped: VideoInsetBalance {
        VideoInsetBalance(
            left: max(0, min(left, 1)),
            top: max(0, min(top, 1))
        )
    }
}

struct VideoInsetStyling: Equatable {
    var amountRatio: Double
    var color: SerializableColor
    var opacity: Double
    var balance: VideoInsetBalance

    static let none = VideoInsetStyling(
        amountRatio: 0,
        color: SerializableColor(hex: "#276FAA"),
        opacity: 1,
        balance: .centered
    )

    var isEnabled: Bool {
        amountRatio > 0
    }
}

struct VideoInsetLayout: Equatable {
    var frameRect: CGRect
    var contentRect: CGRect
}

enum VideoInsetGeometry {
    static func amountRatio(fromValue value: Double) -> Double {
        max(0, min(value, 100)) / 100 * 0.5
    }

    static func layout(in frameRect: CGRect, amountRatio: Double, balance: VideoInsetBalance) -> VideoInsetLayout {
        let contentRect = contentRect(in: frameRect, amountRatio: amountRatio, balance: balance)
        guard contentRect != .zero else {
            return VideoInsetLayout(frameRect: .zero, contentRect: .zero)
        }

        return VideoInsetLayout(frameRect: frameRect, contentRect: contentRect)
    }

    static func contentRect(in frameRect: CGRect, amountRatio: Double, balance: VideoInsetBalance) -> CGRect {
        guard frameRect.width.isFinite,
              frameRect.height.isFinite,
              frameRect.width > 0,
              frameRect.height > 0 else {
            return .zero
        }

        let scale = max(0.05, 1 - max(0, min(amountRatio, 0.95)))
        let contentSize = CGSize(width: frameRect.width * scale, height: frameRect.height * scale)
        let freeX = max(0, frameRect.width - contentSize.width)
        let freeY = max(0, frameRect.height - contentSize.height)
        let resolvedBalance = balance.clamped

        return CGRect(
            x: frameRect.minX + freeX * resolvedBalance.left,
            y: frameRect.minY + freeY * resolvedBalance.top,
            width: contentSize.width,
            height: contentSize.height
        )
    }
}

struct VideoBackgroundStyling: Equatable {
    var background: BackgroundStyle
    var paddingRatio: Double
    var borderRadiusRatio: Double
    var shadowIntensity: Double
    var backgroundBlurRatio: Double
    var inset: VideoInsetStyling

    static let none = VideoBackgroundStyling(
        background: .transparent,
        paddingRatio: 0,
        borderRadiusRatio: 0,
        shadowIntensity: 0,
        backgroundBlurRatio: 0,
        inset: .none
    )

    var isPassthrough: Bool {
        background.isTransparent &&
            paddingRatio == 0 &&
            borderRadiusRatio == 0 &&
            shadowIntensity == 0 &&
            backgroundBlurRatio == 0 &&
            !inset.isEnabled
    }
}

final class VideoBackgroundCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let styling: VideoBackgroundStyling
    let preferredTransform: CGAffineTransform
    let normalizedSize: CGSize
    let cropRect: CGRect
    let renderSize: CGSize
    let edits: TimelineEditSnapshot
    let editPlan: TimelineExportEditPlan
    let cursorTrack: CursorTelemetryTrack?
    let cursorSettings: CursorOverlaySettings

    init(
        timeRange: CMTimeRange,
        trackID: CMPersistentTrackID,
        styling: VideoBackgroundStyling,
        preferredTransform: CGAffineTransform,
        normalizedSize: CGSize,
        cropRect: CGRect,
        renderSize: CGSize,
        edits: TimelineEditSnapshot = .empty,
        editPlan: TimelineExportEditPlan = TimelineExportEditPlan(segments: [], outputDuration: 0),
        cursorTrack: CursorTelemetryTrack? = nil,
        cursorSettings: CursorOverlaySettings = .hidden
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.styling = styling
        self.preferredTransform = preferredTransform
        self.normalizedSize = normalizedSize
        self.cropRect = cropRect
        self.renderSize = renderSize
        self.edits = edits
        self.editPlan = editPlan
        self.cursorTrack = cursorTrack
        self.cursorSettings = cursorSettings.clamped
        super.init()
    }
}

enum VideoCompositorError: LocalizedError {
    case missingInstruction
    case missingSourceFrame
    case renderBufferUnavailable
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .missingInstruction: "Custom video instruction is missing."
        case .missingSourceFrame: "Source video frame is unavailable."
        case .renderBufferUnavailable: "Could not allocate render buffer."
        case .renderFailed: "Failed to render frame."
        }
    }
}

private struct CursorGlyphImage {
    var image: CIImage
    var tipOffset: CGPoint
}

private struct CursorGlyphCacheKey: Hashable {
    var style: CursorStyle
    var variant: CursorVariant
    var sizeKey: Int
}

final class VideoBackgroundCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let renderingQueue = DispatchQueue(label: "com.openrecorder.video.compositor", qos: .userInitiated)
    private let ciContext: CIContext
    private var renderContext: AVVideoCompositionRenderContext?
    private let renderContextLock = NSLock()
    private var cursorGlyphCache: [CursorGlyphCacheKey: CursorGlyphImage] = [:]

    override init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: true])
        } else {
            ciContext = CIContext(options: [.cacheIntermediates: true])
        }
        super.init()
    }

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable]()
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable]()
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextLock.lock()
        renderContext = newRenderContext
        renderContextLock.unlock()
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderingQueue.async { [weak self] in
            guard let self else {
                request.finish(with: VideoCompositorError.renderFailed)
                return
            }

            do {
                let composedBuffer = try self.composeFrame(for: request)
                request.finish(withComposedVideoFrame: composedBuffer)
            } catch {
                request.finish(with: error)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        renderingQueue.sync(flags: .barrier) {}
    }

    private func composeFrame(for request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        guard let instruction = request.videoCompositionInstruction as? VideoBackgroundCompositionInstruction else {
            throw VideoCompositorError.missingInstruction
        }

        guard let trackIDValue = instruction.requiredSourceTrackIDs?.first as? NSNumber else {
            throw VideoCompositorError.missingSourceFrame
        }
        let trackID = CMPersistentTrackID(trackIDValue.int32Value)
        guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
            throw VideoCompositorError.missingSourceFrame
        }

        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            throw VideoCompositorError.renderBufferUnavailable
        }

        let composedImage = try makeComposedImage(
            source: sourceBuffer,
            instruction: instruction,
            compositionTime: request.compositionTime.seconds
        )

        ciContext.render(
            composedImage,
            to: outputBuffer,
            bounds: CGRect(origin: .zero, size: instruction.renderSize),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        return outputBuffer
    }

    private func makeComposedImage(
        source: CVPixelBuffer,
        instruction: VideoBackgroundCompositionInstruction,
        compositionTime: Double
    ) throws -> CIImage {
        let renderSize = instruction.renderSize
        let renderRect = CGRect(origin: .zero, size: renderSize)

        var sourceImage = CIImage(cvPixelBuffer: source)
        sourceImage = sourceImage.transformed(by: instruction.preferredTransform)
        let cropRect = Self.coreImageCropRect(
            fromTopLeftRect: instruction.cropRect,
            sourceSize: instruction.normalizedSize
        )
        sourceImage = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))

        let minDim = min(renderSize.width, renderSize.height)
        let pad = instruction.styling.paddingRatio * minDim
        let innerSize = CGSize(
            width: max(2, renderSize.width - 2 * pad),
            height: max(2, renderSize.height - 2 * pad)
        )
        let innerRect = CGRect(
            x: (renderSize.width - innerSize.width) / 2,
            y: (renderSize.height - innerSize.height) / 2,
            width: innerSize.width,
            height: innerSize.height
        )

        let sourceSize = instruction.cropRect.size
        let frameScale = min(innerSize.width / max(sourceSize.width, 1), innerSize.height / max(sourceSize.height, 1))
        let frameSize = CGSize(width: sourceSize.width * frameScale, height: sourceSize.height * frameScale)
        let frameRect = CGRect(
            x: innerRect.midX - frameSize.width / 2,
            y: innerRect.midY - frameSize.height / 2,
            width: frameSize.width,
            height: frameSize.height
        )
        let sourceLayout = sourceLayout(frameRect: frameRect, styling: instruction.styling)
        let contentRect = sourceLayout.contentRect
        let scale = min(contentRect.width / max(sourceSize.width, 1), contentRect.height / max(sourceSize.height, 1))
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let scaledImage = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaledImage.extent
        let dx = contentRect.midX - scaledExtent.midX
        let dy = contentRect.midY - scaledExtent.midY
        let positionedImage = scaledImage.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        let placedRect = CGRect(
            x: contentRect.midX - scaledSize.width / 2,
            y: contentRect.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
        let cornerRadius = instruction.styling.borderRadiusRatio * minDim
        let maskedSource = applyRoundedMask(positionedImage, cornerRadius: cornerRadius, in: placedRect)

        var background = makeBackground(instruction.styling.background, extent: renderRect)
        if instruction.styling.backgroundBlurRatio > 0, !instruction.styling.background.isTransparent {
            let blurRadius = instruction.styling.backgroundBlurRatio * minDim
            background = applyGaussianBlur(background, radius: blurRadius).cropped(to: renderRect)
        }

        var composed = background
        let drawsInsetFill = instruction.styling.inset.isEnabled && instruction.styling.inset.opacity > 0
        if instruction.styling.inset.isEnabled {
            if instruction.styling.shadowIntensity > 0, drawsInsetFill {
                let shadowMask = makeRoundedFill(
                    color: CIColor.black,
                    in: sourceLayout.frameRect,
                    cornerRadius: cornerRadius
                )
                let shadow = makeShadow(
                    shadowMask,
                    intensity: instruction.styling.shadowIntensity,
                    in: sourceLayout.frameRect
                )
                composed = shadow.composited(over: composed)
            }
            if drawsInsetFill {
                let insetLayer = makeInsetLayer(
                    for: instruction.styling.inset,
                    in: sourceLayout.frameRect,
                    cornerRadius: cornerRadius
                )
                composed = insetLayer.composited(over: composed)
            }
        }
        if instruction.styling.shadowIntensity > 0 {
            if !drawsInsetFill {
                let shadow = makeShadow(maskedSource, intensity: instruction.styling.shadowIntensity, in: placedRect)
                composed = shadow.composited(over: composed)
            }
        }
        composed = maskedSource.composited(over: composed)
        if let cursor = makeCursorLayer(for: instruction, compositionTime: compositionTime, contentRect: contentRect) {
            composed = cursor.composited(over: composed)
        }

        return composed.cropped(to: renderRect)
    }

    private func sourceLayout(frameRect: CGRect, styling: VideoBackgroundStyling) -> VideoInsetLayout {
        guard styling.inset.isEnabled else {
            return VideoInsetLayout(frameRect: frameRect, contentRect: frameRect)
        }
        let coreImageBalance = VideoInsetBalance(
            left: styling.inset.balance.left,
            top: 1 - styling.inset.balance.top
        )
        return VideoInsetGeometry.layout(
            in: frameRect,
            amountRatio: styling.inset.amountRatio,
            balance: coreImageBalance
        )
    }

    private func makeCursorLayer(
        for instruction: VideoBackgroundCompositionInstruction,
        compositionTime: Double,
        contentRect: CGRect
    ) -> CIImage? {
        let settings = instruction.cursorSettings.clamped
        guard settings.isVisible,
              let track = instruction.cursorTrack,
              track.samples.isEmpty == false else {
            return nil
        }

        let sourceTime = instruction.editPlan.sourceTime(forOutputTime: compositionTime) ?? compositionTime
        guard let point = track.point(at: sourceTime, settings: settings) else {
            return nil
        }

        let outputPoint = cursorOutputPoint(
            telemetryPoint: point,
            outputTime: compositionTime,
            contentRect: contentRect,
            cropRect: instruction.cropRect,
            sourceSize: instruction.normalizedSize,
            instruction: instruction,
            track: track
        )
        let cursorSize = CursorOverlayGeometry.glyphSize(
            contentRect: contentRect,
            cropRect: instruction.cropRect,
            settings: settings
        )
        guard let glyph = cursorGlyphImage(
            size: cursorSize,
            style: settings.style,
            variant: settings.variant
        ) else {
            return nil
        }

        return glyph.image.transformed(
            by: CGAffineTransform(
                translationX: outputPoint.x - glyph.tipOffset.x,
                y: outputPoint.y - glyph.tipOffset.y
            )
        )
    }

    private func cursorOutputPoint(
        telemetryPoint: CGPoint,
        outputTime: Double,
        contentRect: CGRect,
        cropRect: CGRect,
        sourceSize: CGSize,
        instruction: VideoBackgroundCompositionInstruction,
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

        point.x = min(max(point.x, 0), instruction.renderSize.width)
        point.y = min(max(point.y, 0), instruction.renderSize.height)
        return point
    }

    private func cursorGlyphImage(size: CGFloat, style: CursorStyle, variant: CursorVariant) -> CursorGlyphImage? {
        let resolvedVariant = style.resolvedVariant(variant)
        let cacheKey = CursorGlyphCacheKey(
            style: style,
            variant: resolvedVariant,
            sizeKey: Int((size * 10).rounded())
        )
        if let cached = cursorGlyphCache[cacheKey] {
            return cached
        }

        guard let rendered = CursorPresetRenderer.renderedGlyph(
            style: style,
            variant: resolvedVariant,
            size: size
        ) else {
            return nil
        }

        let glyph = CursorGlyphImage(
            image: CIImage(cgImage: rendered.image),
            tipOffset: rendered.bottomLeftHotspot
        )
        cursorGlyphCache[cacheKey] = glyph
        return glyph
    }

    private func makeInsetLayer(for inset: VideoInsetStyling, in rect: CGRect, cornerRadius: CGFloat) -> CIImage {
        let color = CIColor(
            red: CGFloat(inset.color.red),
            green: CGFloat(inset.color.green),
            blue: CGFloat(inset.color.blue),
            alpha: CGFloat(max(0, min(inset.color.alpha * inset.opacity, 1)))
        )
        let fill = CIImage(color: color).cropped(to: rect)
        return applyRoundedMask(fill, cornerRadius: cornerRadius, in: rect)
    }

    private func makeRoundedFill(color: CIColor, in rect: CGRect, cornerRadius: CGFloat) -> CIImage {
        let fill = CIImage(color: color).cropped(to: rect)
        return applyRoundedMask(fill, cornerRadius: cornerRadius, in: rect)
    }

    private static func coreImageCropRect(fromTopLeftRect rect: CGRect, sourceSize: CGSize) -> CGRect {
        let clamped = VideoCropSelection.clampedPixelRect(rect, in: sourceSize)
        return CGRect(
            x: clamped.minX,
            y: max(0, sourceSize.height - clamped.maxY),
            width: clamped.width,
            height: clamped.height
        )
    }

    private func makeBackground(_ style: BackgroundStyle, extent: CGRect) -> CIImage {
        switch style {
        case .transparent:
            return CIImage(color: CIColor.clear).cropped(to: extent)
        case let .solid(color):
            let ciColor = CIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(color.alpha))
            return CIImage(color: ciColor).cropped(to: extent)
        case let .gradient(preset):
            return renderGradient(preset, extent: extent)
        case let .wallpaper(preset):
            return renderWallpaper(preset, extent: extent)
        }
    }

    private func renderGradient(_ preset: GradientPreset, extent: CGRect) -> CIImage {
        let width = max(Int(ceil(extent.width)), 1)
        let height = max(Int(ceil(extent.height)), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: CIColor.black).cropped(to: extent)
        }

        let stops = preset.sortedStops
        let cgColors = stops.map { $0.color.cgColor } as CFArray
        let locations = stops.map { CGFloat($0.position) }
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations) else {
            return CIImage(color: CIColor.black).cropped(to: extent)
        }

        let rect = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        switch preset.kind {
        case .linear:
            let endpoints = preset.endpoints(in: rect)
            context.drawLinearGradient(
                gradient,
                start: endpoints.start,
                end: endpoints.end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        case .radial:
            let endpoints = preset.endpoints(in: rect)
            let endRadius = preset.radialRadius(in: rect)
            context.drawRadialGradient(
                gradient,
                startCenter: endpoints.start,
                startRadius: 0,
                endCenter: endpoints.end,
                endRadius: endRadius,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        guard let cgImage = context.makeImage() else {
            return CIImage(color: CIColor.black).cropped(to: extent)
        }
        return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    private func renderWallpaper(_ preset: WallpaperPreset, extent: CGRect) -> CIImage {
        guard let url = preset.fullURL, let cgImage = WallpaperImageCache.cgImage(for: url) else {
            return CIImage(color: CIColor.gray).cropped(to: extent)
        }
        var image = CIImage(cgImage: cgImage)
        let scale = max(extent.width / max(image.extent.width, 1), extent.height / max(image.extent.height, 1))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = extent.midX - image.extent.midX
        let dy = extent.midY - image.extent.midY
        image = image.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        return image.cropped(to: extent)
    }

    private func applyGaussianBlur(_ image: CIImage, radius: Double) -> CIImage {
        guard radius > 0, let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage ?? image
    }

    private func applyRoundedMask(_ image: CIImage, cornerRadius: CGFloat, in rect: CGRect) -> CIImage {
        let width = max(Int(ceil(rect.width)), 1)
        let height = max(Int(ceil(rect.height)), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.setFillColor(NSColor.white.cgColor)
        let maskRect = CGRect(x: 0, y: 0, width: width, height: height)
        let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        context.addPath(CGPath(roundedRect: maskRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()

        guard let maskCG = context.makeImage() else { return image }
        let maskImage = CIImage(cgImage: maskCG).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))

        guard let filter = CIFilter(name: "CIBlendWithMask") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIImage(color: CIColor.clear).cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
        filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
        return filter.outputImage ?? image
    }

    private func makeShadow(_ image: CIImage, intensity: Double, in rect: CGRect) -> CIImage {
        let blurRadius = 38 * intensity
        let blurred = applyGaussianBlur(image, radius: blurRadius)
        let offset = blurred.transformed(by: CGAffineTransform(translationX: 0, y: -18 * intensity))
        return setOpacity(offset, alpha: 0.55 * intensity)
    }

    private func setOpacity(_ image: CIImage, alpha: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha)), forKey: "inputAVector")
        return filter.outputImage ?? image
    }
}
