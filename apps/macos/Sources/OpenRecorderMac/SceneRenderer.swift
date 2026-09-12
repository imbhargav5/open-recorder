import CoreImage
import CoreGraphics

struct SceneMockupLayout {
    var frame: CGRect
    var content: CGRect
    var radius: CGFloat

    static func make(in rect: CGRect, mediaAspect: CGFloat, style: MockupStyle, radius: CGFloat) -> Self {
        guard style != .none else { return Self(frame: rect, content: rect, radius: radius) }
        let aspect: CGFloat
        switch style {
        case .phone: aspect = 0.5
        case .tablet: aspect = 0.75
        default: aspect = mediaAspect
        }
        let size = CGSize(width: min(rect.width, rect.height * aspect), height: min(rect.height, rect.width / aspect))
        let frame = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        let edge = min(size.width, size.height) * (style == .phone || style == .tablet ? 0.045 : 0.015)
        let top = style == .browser || style == .window ? min(size.width, size.height) * 0.085 : edge
        let inner = CGRect(x: frame.minX + edge, y: frame.minY + edge,
                           width: max(1, frame.width - 2 * edge), height: max(1, frame.height - edge - top))
        let fit = CGSize(width: min(inner.width, inner.height * mediaAspect), height: min(inner.height, inner.width / mediaAspect))
        let content = CGRect(x: inner.midX - fit.width / 2, y: inner.midY - fit.height / 2, width: fit.width, height: fit.height)
        return Self(frame: frame, content: content, radius: min(size.width, size.height) * (style == .phone || style == .tablet ? 0.1 : 0.025))
    }
}

/// Owned by one rendering queue. Caches are bounded to the current frame style and size.
final class SceneRenderer {
    private struct ArtworkKey: Equatable {
        var frame: CGRect
        var style: MockupStyle
        var dark: Bool
        var highlight: Bool
        var radius: CGFloat
    }
    private var artworkCache: (ArtworkKey, CIImage)?
    private var maskCache: (CGRect, CGFloat, CIImage)?

    static func roundedMask(in rect: CGRect, radius: CGFloat) -> CIImage {
        let filter = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect), "inputRadius": max(0, radius), "inputColor": CIColor.white
        ])!
        return filter.outputImage!.cropped(to: rect)
    }

    func mask(_ image: CIImage, in rect: CGRect, radius: CGFloat) -> CIImage {
        let shape: CIImage
        if let cache = maskCache, cache.0 == rect, cache.1 == radius { shape = cache.2 }
        else {
            shape = Self.roundedMask(in: rect, radius: radius)
            maskCache = (rect, radius, shape)
        }
        return image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: shape
        ]).cropped(to: rect)
    }

    func render(media: CIImage, mediaRect: CGRect, frame: CGRect, canvas: CGSize,
                settings: SceneSettings, time: Double, radius: CGFloat, shadow: Double) -> CIImage {
        let layout = SceneMockupLayout.make(in: frame, mediaAspect: mediaRect.width / max(1, mediaRect.height), style: settings.mockup, radius: radius)
        let sx = layout.content.width / max(1, mediaRect.width), sy = layout.content.height / max(1, mediaRect.height)
        let fitted = media.cropped(to: mediaRect)
            .transformed(by: CGAffineTransform(translationX: -mediaRect.minX, y: -mediaRect.minY))
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: layout.content.minX, y: layout.content.minY))
        var card = mask(fitted, in: layout.content, radius: settings.mockup == .none ? radius : min(radius, layout.radius / 2))
        let artwork = frameArtwork(layout: layout, settings: settings)
        card = card.composited(over: artwork).cropped(to: layout.frame)
        if settings.edgeHighlight {
            card = edgeStroke(in: layout.frame, radius: layout.radius).composited(over: card)
        }
        let geometry = SceneGeometry.evaluate(frame: layout.frame, canvas: canvas, pose: settings.pose(at: time))
        let projected = card.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(cgPoint: geometry.topLeft), "inputTopRight": CIVector(cgPoint: geometry.topRight),
            "inputBottomLeft": CIVector(cgPoint: geometry.bottomLeft), "inputBottomRight": CIVector(cgPoint: geometry.bottomRight)
        ])
        guard shadow > 0 else { return projected }
        let amount = sceneClamp(shadow, 0...1)
        let unit = min(canvas.width, canvas.height) / 1080
        let drop = projected.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount * 0.55)
        ]).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 38 * amount * unit])
            .transformed(by: CGAffineTransform(translationX: 0, y: -18 * amount * unit))
        return projected.composited(over: drop)
    }

    private func frameArtwork(layout: SceneMockupLayout, settings: SceneSettings) -> CIImage {
        let key = ArtworkKey(frame: layout.frame, style: settings.mockup, dark: settings.darkMockup,
                             highlight: settings.edgeHighlight, radius: layout.radius)
        if let cache = artworkCache, cache.0 == key { return cache.1 }
        let rect = layout.frame
        let gray: CGFloat = settings.darkMockup ? 0.12 : 0.92
        var image = settings.mockup == .none ? CIImage.empty() : CIImage(color: CIColor(red: gray, green: gray, blue: gray)).cropped(to: rect)
        if settings.mockup == .browser || settings.mockup == .window {
            let r = min(rect.width, rect.height) * 0.009
            for (index, color) in [CIColor(red: 1, green: 0.36, blue: 0.32), CIColor(red: 1, green: 0.75, blue: 0.2), CIColor(red: 0.22, green: 0.78, blue: 0.35)].enumerated() {
                let dot = CGRect(x: rect.minX + r * (3 + CGFloat(index) * 3), y: rect.maxY - r * 5, width: r * 2, height: r * 2)
                image = CIImage(color: color).cropped(to: dot).applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: Self.roundedMask(in: dot, radius: r)
                ]).composited(over: image)
            }
        }
        image = image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: Self.roundedMask(in: rect, radius: layout.radius)
        ])
        artworkCache = (key, image)
        return image
    }

    private func edgeStroke(in rect: CGRect, radius: CGFloat) -> CIImage {
        let outer = Self.roundedMask(in: rect, radius: radius)
        let edge = max(1, min(rect.width, rect.height) / 400)
        let inner = Self.roundedMask(in: rect.insetBy(dx: edge, dy: edge), radius: max(0, radius - edge))
        return outer.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.35)])
    }
}
