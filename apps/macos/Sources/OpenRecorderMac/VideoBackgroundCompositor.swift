import AVFoundation
import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal

struct VideoBackgroundStyling: Equatable {
    var background: BackgroundStyle
    var paddingRatio: Double
    var borderRadiusRatio: Double
    var shadowIntensity: Double
    var backgroundBlurRatio: Double

    static let none = VideoBackgroundStyling(
        background: .transparent,
        paddingRatio: 0,
        borderRadiusRatio: 0,
        shadowIntensity: 0,
        backgroundBlurRatio: 0
    )

    var isPassthrough: Bool {
        background.isTransparent &&
            paddingRatio == 0 &&
            borderRadiusRatio == 0 &&
            shadowIntensity == 0 &&
            backgroundBlurRatio == 0
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
    let renderSize: CGSize
    let edits: TimelineEditSnapshot
    let editPlan: TimelineExportEditPlan

    init(
        timeRange: CMTimeRange,
        trackID: CMPersistentTrackID,
        styling: VideoBackgroundStyling,
        preferredTransform: CGAffineTransform,
        normalizedSize: CGSize,
        renderSize: CGSize,
        edits: TimelineEditSnapshot = .empty,
        editPlan: TimelineExportEditPlan = TimelineExportEditPlan(segments: [], outputDuration: 0)
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.styling = styling
        self.preferredTransform = preferredTransform
        self.normalizedSize = normalizedSize
        self.renderSize = renderSize
        self.edits = edits
        self.editPlan = editPlan
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

final class VideoBackgroundCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let renderingQueue = DispatchQueue(label: "com.openrecorder.video.compositor", qos: .userInitiated)
    private let ciContext: CIContext
    private var renderContext: AVVideoCompositionRenderContext?
    private let renderContextLock = NSLock()

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
        let normalizedRect = CGRect(origin: .zero, size: instruction.normalizedSize)
        sourceImage = sourceImage.cropped(to: normalizedRect)

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

        let sourceSize = instruction.normalizedSize
        let scale = min(innerSize.width / max(sourceSize.width, 1), innerSize.height / max(sourceSize.height, 1))
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let scaledImage = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaledImage.extent
        let dx = innerRect.midX - scaledExtent.midX
        let dy = innerRect.midY - scaledExtent.midY
        var positionedImage = scaledImage.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        let placedRect = CGRect(
            x: innerRect.midX - scaledSize.width / 2,
            y: innerRect.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
        if let zoom = activeZoom(for: instruction, at: compositionTime) {
            positionedImage = applyZoom(to: positionedImage, zoom: zoom, in: placedRect)
        }
        let cornerRadius = instruction.styling.borderRadiusRatio * minDim
        let maskedSource = applyRoundedMask(positionedImage, cornerRadius: cornerRadius, in: placedRect)

        var background = makeBackground(instruction.styling.background, extent: renderRect)
        if instruction.styling.backgroundBlurRatio > 0, !instruction.styling.background.isTransparent {
            let blurRadius = instruction.styling.backgroundBlurRatio * minDim
            background = applyGaussianBlur(background, radius: blurRadius).cropped(to: renderRect)
        }

        var composed = background
        if instruction.styling.shadowIntensity > 0 {
            let shadow = makeShadow(maskedSource, intensity: instruction.styling.shadowIntensity, in: placedRect)
            composed = shadow.composited(over: composed)
        }
        composed = maskedSource.composited(over: composed)

        return composed.cropped(to: renderRect)
    }

    private func activeZoom(for instruction: VideoBackgroundCompositionInstruction, at outputTime: Double) -> TimelineZoomRegion? {
        guard outputTime.isFinite else { return nil }
        return instruction.edits.zoomRegions
            .sorted { $0.span.start < $1.span.start }
            .last { zoom in
                let start = instruction.editPlan.outputTime(forSourceTime: zoom.span.start) ?? zoom.span.start
                let end = instruction.editPlan.outputTime(forSourceTime: zoom.span.end) ?? zoom.span.end
                return outputTime >= start && outputTime < end
            }
    }

    private func applyZoom(to image: CIImage, zoom: TimelineZoomRegion, in rect: CGRect) -> CIImage {
        let depth = CGFloat(max(1, zoom.depth))
        guard depth > 1 else { return image }
        let focus = CGPoint(
            x: rect.minX + rect.width * CGFloat(zoom.focusX),
            y: rect.minY + rect.height * CGFloat(1 - zoom.focusY)
        )
        let transform = CGAffineTransform(translationX: -focus.x, y: -focus.y)
            .concatenating(CGAffineTransform(scaleX: depth, y: depth))
            .concatenating(CGAffineTransform(translationX: focus.x, y: focus.y))
        return image.transformed(by: transform)
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
