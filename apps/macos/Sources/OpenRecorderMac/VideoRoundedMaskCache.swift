import AppKit
import CoreImage

/// One invariant raster per content role. Placement is applied by the compositor.
final class VideoRoundedMaskCache: @unchecked Sendable {
    enum Role: Hashable { case recording, facecam }
    private struct Key: Equatable {
        let width: Int, height: Int
        let radius: CGFloat
        init(size: CGSize, cornerRadius: CGFloat) {
            width = max(Int(ceil(size.width)), 1)
            height = max(Int(ceil(size.height)), 1)
            radius = max(0, min(cornerRadius, min(size.width, size.height) / 2))
        }
    }
    private struct Entry { let key: Key; let image: CIImage }
    private let lock = NSLock()
    private var entries: [Role: Entry] = [:]

    func mask(size: CGSize, cornerRadius: CGFloat, role: Role) -> CIImage? {
        lock.lock(); defer { lock.unlock() }
        let key = Key(size: size, cornerRadius: cornerRadius)
        if let entry = entries[role], entry.key == key { return entry.image }
        // Replace the role even if allocation fails; never retain obsolete geometry.
        entries[role] = nil
        guard let image = Self.makeMask(key: key) else { return nil }
        entries[role] = Entry(key: key, image: image)
        return image
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(keepingCapacity: true)
    }

    static func makeMask(size: CGSize, cornerRadius: CGFloat) -> CIImage? {
        makeMask(key: Key(size: size, cornerRadius: cornerRadius))
    }

    private static func makeMask(key: Key) -> CIImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: key.width, height: key.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        let rect = CGRect(x: 0, y: 0, width: key.width, height: key.height)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: key.radius, cornerHeight: key.radius, transform: nil))
        context.fillPath()
        return context.makeImage().map { CIImage(cgImage: $0) }
    }
}
