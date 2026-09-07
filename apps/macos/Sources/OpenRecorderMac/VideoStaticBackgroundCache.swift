import CoreImage
import CoreVideo
import Foundation

/// Keeps at most one rendered background. Dynamic source frames, shadows and overlays
/// never enter this cache. A separate IOSurface avoids rebuilding static CI graphs
/// without enabling unbounded intermediate caching for the video itself.
final class VideoStaticBackgroundCache {
    private struct Key: Equatable {
        let style: BackgroundStyle
        let extent: CGRect
        let blurRadius: Double
    }

    private let context: CIContext
    private let lock = NSLock()
    private var entry: (key: Key, image: CIImage)?

    init(context: CIContext) {
        self.context = context
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        entry = nil
    }

    func image(style: BackgroundStyle, extent: CGRect, blurRadius: Double, makeImage: () -> CIImage) -> CIImage {
        // Context changes/cancellation can arrive off the compositor's rendering queue.
        lock.lock()
        defer { lock.unlock() }

        switch style {
        case .solid, .transparent:
            // Constant colors are cheaper as CI generators than as uploaded bitmaps.
            entry = nil
            return makeImage()
        case .gradient, .wallpaper:
            break
        }

        let key = Key(style: style, extent: extent, blurRadius: blurRadius)
        if let entry, entry.key == key { return entry.image }
        entry = nil
        let source = makeImage()
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0,
              extent.width <= CGFloat(Int32.max), extent.height <= CGFloat(Int32.max) else { return source }

        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(ceil(extent.width)), Int(ceil(extent.height)),
            kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return source }
        let bounds = CGRect(origin: .zero, size: extent.size)
        context.render(
            source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)),
            to: buffer, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        // CIImage retains its pixel buffer; replacing the sole entry releases the old surface.
        let image = CIImage(cvPixelBuffer: buffer)
            .cropped(to: bounds)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        entry = (key, image)
        return image
    }
}
