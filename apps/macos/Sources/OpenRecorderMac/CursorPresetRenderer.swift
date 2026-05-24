import AppKit
import CoreGraphics
import SwiftUI

struct CursorGlyphPalette {
    var fill: SerializableColor
    var stroke: SerializableColor
    var shadow: SerializableColor
}

struct CursorGlyphDrawing {
    var path: CGPath
    var canvasSize: CGSize
    var hotspot: CGPoint
    var strokeWidth: CGFloat
    var fillsShape: Bool
}

struct CursorRenderedGlyph {
    var image: CGImage
    var canvasSize: CGSize
    var hotspot: CGPoint

    var bottomLeftHotspot: CGPoint {
        CGPoint(x: hotspot.x, y: canvasSize.height - hotspot.y)
    }

    var coreAnimationAnchorPoint: CGPoint {
        CGPoint(
            x: hotspot.x / max(canvasSize.width, 1),
            y: 1 - hotspot.y / max(canvasSize.height, 1)
        )
    }
}

enum CursorStyleRenderer {
    static func drawing(styleID: CursorStyleID, size: CGFloat) -> CursorGlyphDrawing {
        let definition = CursorStyleRegistry.definition(for: CursorStyleRegistry.resolvedStyleID(styleID))
        return drawing(renderKind: definition?.renderKind, size: size * CGFloat(definition?.defaultScale ?? 1))
    }

    static func renderedGlyph(styleID: CursorStyleID, size: CGFloat) -> CursorRenderedGlyph? {
        let resolvedStyleID = CursorStyleRegistry.resolvedStyleID(styleID)
        guard let definition = CursorStyleRegistry.definition(for: resolvedStyleID) else {
            return nil
        }
        let resolvedSize = max(1, size * CGFloat(definition.defaultScale))
        if case .rasterAsset(let name, let hotspotRule) = definition.renderKind {
            return rasterGlyph(name: name, hotspotRule: hotspotRule, size: resolvedSize)
        }

        let drawing = drawing(renderKind: definition.renderKind, size: resolvedSize)
        let palette = palette(for: definition.renderKind)
        let margin = max(3, resolvedSize * 0.22)
        let pixelSize = CGSize(
            width: ceil(drawing.canvasSize.width + margin * 2),
            height: ceil(drawing.canvasSize.height + margin * 2)
        )
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: max(1, Int(pixelSize.width)),
            height: max(1, Int(pixelSize.height)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: pixelSize))
        context.translateBy(x: 0, y: pixelSize.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: margin, y: margin)
        context.setShadow(
            offset: CGSize(width: 0, height: resolvedSize * 0.045),
            blur: max(1, resolvedSize * 0.10),
            color: palette.shadow.cgColor
        )
        draw(drawing, in: context, palette: palette)

        guard let image = context.makeImage() else {
            return nil
        }

        return CursorRenderedGlyph(
            image: image,
            canvasSize: pixelSize,
            hotspot: CGPoint(x: margin + drawing.hotspot.x, y: margin + drawing.hotspot.y)
        )
    }

    private static func drawing(renderKind: CursorRenderKind?, size: CGFloat) -> CursorGlyphDrawing {
        let resolvedSize = max(1, size)
        switch renderKind {
        case .hand:
            return handDrawing(size: resolvedSize)
        case .iBeam:
            return iBeamDrawing(size: resolvedSize)
        case .dot(_, _, _, let fillsShape):
            return dotDrawing(size: resolvedSize, diameterScale: 0.58, fillsShape: fillsShape)
        case .ring:
            return dotDrawing(size: resolvedSize, diameterScale: 0.82, fillsShape: false)
        case .spotlight:
            return dotDrawing(size: resolvedSize, diameterScale: 0.90, fillsShape: true)
        case .arrow, .rasterAsset, nil:
            return arrowDrawing(size: resolvedSize, fillsShape: true)
        }
    }

    private static func palette(for renderKind: CursorRenderKind) -> CursorGlyphPalette {
        switch renderKind {
        case .arrow(let fill, let stroke, let shadow),
             .hand(let fill, let stroke, let shadow),
             .iBeam(let fill, let stroke, let shadow),
             .dot(let fill, let stroke, let shadow, _),
             .spotlight(let fill, let stroke, let shadow):
            return CursorGlyphPalette(fill: fill, stroke: stroke, shadow: shadow)
        case .ring(let stroke, let shadow):
            return CursorGlyphPalette(
                fill: SerializableColor(red: 1, green: 1, blue: 1, alpha: 0),
                stroke: stroke,
                shadow: shadow
            )
        case .rasterAsset:
            return CursorGlyphPalette(
                fill: SerializableColor(hex: "#FFFFFF"),
                stroke: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.84),
                shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.36)
            )
        }
    }

    private static func rasterGlyph(name: String, hotspotRule: CursorHotspotRule, size: CGFloat) -> CursorRenderedGlyph? {
        guard let image = NSImage(named: name) else { return nil }
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = size / max(sourceSize.width, sourceSize.height)
        let canvasSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        var rect = CGRect(origin: .zero, size: canvasSize)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }

        return CursorRenderedGlyph(
            image: cgImage,
            canvasSize: canvasSize,
            hotspot: hotspot(for: hotspotRule, canvasSize: canvasSize)
        )
    }

    private static func hotspot(for rule: CursorHotspotRule, canvasSize: CGSize) -> CGPoint {
        switch rule {
        case .topLeft:
            return .zero
        case .center:
            return CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        case .proportional(let x, let y):
            return CGPoint(x: canvasSize.width * x, y: canvasSize.height * y)
        }
    }

    private static func draw(_ drawing: CursorGlyphDrawing, in context: CGContext, palette: CursorGlyphPalette) {
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setLineWidth(drawing.strokeWidth)

        if drawing.fillsShape {
            context.addPath(drawing.path)
            context.setFillColor(palette.fill.cgColor)
            context.fillPath()
        }

        context.addPath(drawing.path)
        context.setStrokeColor(palette.stroke.cgColor)
        context.strokePath()
    }

    private static func arrowDrawing(size: CGFloat, fillsShape: Bool) -> CursorGlyphDrawing {
        let points: (tail: CGFloat, shaft: CGFloat, heel: CGFloat, notch: CGFloat, head: CGFloat, height: CGFloat) = (0.24, 0.45, 0.64, 0.43, 0.78, 1.30)
        let strokeScale: CGFloat = fillsShape ? 0.058 : 0.09

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: size * 1.18))
        path.addLine(to: CGPoint(x: size * points.tail, y: size * 0.88))
        path.addLine(to: CGPoint(x: size * points.shaft, y: size * points.height))
        path.addLine(to: CGPoint(x: size * points.heel, y: size * (points.height - 0.07)))
        path.addLine(to: CGPoint(x: size * points.notch, y: size * 0.82))
        path.addLine(to: CGPoint(x: size * points.head, y: size * 0.76))
        path.closeSubpath()

        return CursorGlyphDrawing(
            path: path,
            canvasSize: CGSize(width: size * (points.head + 0.08), height: size * (points.height + 0.06)),
            hotspot: .zero,
            strokeWidth: max(1, size * strokeScale),
            fillsShape: fillsShape
        )
    }

    private static func handDrawing(size: CGFloat) -> CursorGlyphDrawing {
        let strokeScale: CGFloat = 0.052

        let path = CGMutablePath()
        path.move(to: CGPoint(x: size * 0.47, y: size * 0.02))
        path.addCurve(
            to: CGPoint(x: size * 0.62, y: size * 0.15),
            control1: CGPoint(x: size * 0.56, y: size * 0.02),
            control2: CGPoint(x: size * 0.62, y: size * 0.07)
        )
        path.addLine(to: CGPoint(x: size * 0.62, y: size * 0.54))
        path.addCurve(
            to: CGPoint(x: size * 0.76, y: size * 0.49),
            control1: CGPoint(x: size * 0.66, y: size * 0.49),
            control2: CGPoint(x: size * 0.72, y: size * 0.47)
        )
        path.addCurve(
            to: CGPoint(x: size * 0.91, y: size * 0.67),
            control1: CGPoint(x: size * 0.85, y: size * 0.52),
            control2: CGPoint(x: size * 0.91, y: size * 0.59)
        )
        path.addLine(to: CGPoint(x: size * 0.85, y: size * 1.00))
        path.addCurve(
            to: CGPoint(x: size * 0.60, y: size * 1.24),
            control1: CGPoint(x: size * 0.81, y: size * 1.15),
            control2: CGPoint(x: size * 0.73, y: size * 1.24)
        )
        path.addLine(to: CGPoint(x: size * 0.39, y: size * 1.24))
        path.addCurve(
            to: CGPoint(x: size * 0.18, y: size * 1.09),
            control1: CGPoint(x: size * 0.29, y: size * 1.24),
            control2: CGPoint(x: size * 0.22, y: size * 1.18)
        )
        path.addLine(to: CGPoint(x: size * 0.04, y: size * 0.82))
        path.addCurve(
            to: CGPoint(x: size * 0.17, y: size * 0.66),
            control1: CGPoint(x: size * -0.01, y: size * 0.72),
            control2: CGPoint(x: size * 0.07, y: size * 0.62)
        )
        path.addLine(to: CGPoint(x: size * 0.35, y: size * 0.81))
        path.addLine(to: CGPoint(x: size * 0.35, y: size * 0.15))
        path.addCurve(
            to: CGPoint(x: size * 0.47, y: size * 0.02),
            control1: CGPoint(x: size * 0.35, y: size * 0.07),
            control2: CGPoint(x: size * 0.40, y: size * 0.02)
        )
        path.closeSubpath()

        let hotspot = CGPoint(x: size * 0.54, y: size * 0.02)

        return CursorGlyphDrawing(
            path: path,
            canvasSize: CGSize(width: size, height: size * 1.30),
            hotspot: hotspot,
            strokeWidth: max(1, size * strokeScale),
            fillsShape: true
        )
    }

    private static func iBeamDrawing(size: CGFloat) -> CursorGlyphDrawing {
        let capWidth: CGFloat = 0.62
        let stemWidth: CGFloat = 0.10
        let cornerRadius: CGFloat = 0

        let path = CGMutablePath()
        addIBeamRect(
            CGRect(x: size * (0.5 - capWidth / 2), y: 0, width: size * capWidth, height: size * 0.12),
            to: path,
            cornerRadius: cornerRadius
        )
        addIBeamRect(
            CGRect(x: size * (0.5 - stemWidth / 2), y: size * 0.06, width: size * stemWidth, height: size * 1.08),
            to: path,
            cornerRadius: cornerRadius
        )
        addIBeamRect(
            CGRect(x: size * (0.5 - capWidth / 2), y: size * 1.08, width: size * capWidth, height: size * 0.12),
            to: path,
            cornerRadius: cornerRadius
        )

        return CursorGlyphDrawing(
            path: path,
            canvasSize: CGSize(width: size, height: size * 1.20),
            hotspot: CGPoint(x: size * 0.50, y: size * 0.60),
            strokeWidth: max(1, size * 0.04),
            fillsShape: true
        )
    }

    private static func dotDrawing(size: CGFloat, diameterScale: CGFloat, fillsShape: Bool) -> CursorGlyphDrawing {
        let diameter = size * diameterScale
        let strokeScale: CGFloat = fillsShape ? 0.055 : 0.10
        let origin = CGPoint(x: (size * 0.90 - diameter) / 2, y: (size * 0.90 - diameter) / 2)
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: origin, size: CGSize(width: diameter, height: diameter)))

        return CursorGlyphDrawing(
            path: path,
            canvasSize: CGSize(width: size * 0.90, height: size * 0.90),
            hotspot: CGPoint(x: size * 0.45, y: size * 0.45),
            strokeWidth: max(1, size * strokeScale),
            fillsShape: fillsShape
        )
    }

    private static func addIBeamRect(_ rect: CGRect, to path: CGMutablePath, cornerRadius: CGFloat) {
        guard cornerRadius > 0 else {
            path.addRect(rect)
            return
        }

        path.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
    }
}

struct CursorGlyphView: View {
    var styleID: CursorStyleID
    var scale: Double
    var glyphSize: CGFloat? = nil
    var alignsHotspot = false

    var body: some View {
        let size = glyphSize.map { max(1, $0) } ?? max(12, 24 * CGFloat(scale))
        if let glyph = CursorStyleRenderer.renderedGlyph(styleID: styleID, size: size) {
            Image(nsImage: NSImage(cgImage: glyph.image, size: glyph.canvasSize))
                .resizable()
                .frame(width: glyph.canvasSize.width, height: glyph.canvasSize.height)
                .offset(
                    x: alignsHotspot ? -glyph.hotspot.x : 0,
                    y: alignsHotspot ? -glyph.hotspot.y : 0
                )
                .allowsHitTesting(false)
        }
    }
}
