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

enum CursorPresetRenderer {
    static let palette = CursorGlyphPalette(
        fill: SerializableColor(hex: "#FFFFFF"),
        stroke: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.84),
        shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.36)
    )

    static let macOSBlackPalette = CursorGlyphPalette(
        fill: SerializableColor(hex: "#1F2023"),
        stroke: SerializableColor(red: 1, green: 1, blue: 1, alpha: 0.84),
        shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.28)
    )

    static func palette(for style: CursorStyle) -> CursorGlyphPalette {
        switch style {
        case .macOSBlackArrow:
            return macOSBlackPalette
        case .arrow, .outlineArrow, .handPointer, .iBeam, .dotPointer:
            return palette
        }
    }

    static func drawing(style: CursorStyle, size: CGFloat, variant: CursorVariant = .standard) -> CursorGlyphDrawing {
        let resolvedSize = max(1, size)
        let resolvedVariant = style.resolvedVariant(variant)
        switch style {
        case .arrow, .macOSBlackArrow:
            return arrowDrawing(size: resolvedSize, fillsShape: true, variant: resolvedVariant)
        case .outlineArrow:
            return arrowDrawing(size: resolvedSize, fillsShape: false, variant: resolvedVariant)
        case .handPointer:
            return handDrawing(size: resolvedSize, variant: resolvedVariant)
        case .iBeam:
            return iBeamDrawing(size: resolvedSize, variant: resolvedVariant)
        case .dotPointer:
            return dotDrawing(size: resolvedSize, variant: resolvedVariant)
        }
    }

    static func renderedGlyph(style: CursorStyle, variant: CursorVariant, size: CGFloat) -> CursorRenderedGlyph? {
        let resolvedVariant = style.resolvedVariant(variant)
        let drawing = drawing(style: style, size: size, variant: resolvedVariant)
        let palette = palette(for: style)
        let margin = max(3, size * 0.22)
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
            offset: CGSize(width: 0, height: size * 0.08),
            blur: max(2, size * 0.18),
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

    private static func arrowDrawing(size: CGFloat, fillsShape: Bool, variant: CursorVariant) -> CursorGlyphDrawing {
        let points: (tail: CGFloat, shaft: CGFloat, heel: CGFloat, notch: CGFloat, head: CGFloat, height: CGFloat)
        let strokeScale: CGFloat
        switch variant {
        case .standard:
            points = (0.24, 0.45, 0.64, 0.43, 0.78, 1.30)
            strokeScale = fillsShape ? 0.08 : 0.11
        case .slim:
            points = (0.18, 0.37, 0.54, 0.35, 0.66, 1.30)
            strokeScale = fillsShape ? 0.064 : 0.09
        case .soft:
            points = (0.28, 0.47, 0.67, 0.46, 0.80, 1.26)
            strokeScale = fillsShape ? 0.075 : 0.10
        case .bold:
            points = (0.30, 0.52, 0.74, 0.50, 0.90, 1.33)
            strokeScale = fillsShape ? 0.10 : 0.14
        }

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
            strokeWidth: max(1.5, size * strokeScale),
            fillsShape: fillsShape
        )
    }

    private static func handDrawing(size: CGFloat, variant: CursorVariant) -> CursorGlyphDrawing {
        let xScale: CGFloat
        let strokeScale: CGFloat
        switch variant {
        case .standard:
            xScale = 1
            strokeScale = 0.07
        case .slim:
            xScale = 0.86
            strokeScale = 0.058
        case .soft:
            xScale = 1.02
            strokeScale = 0.064
        case .bold:
            xScale = 1.08
            strokeScale = 0.095
        }

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
        let resolvedPath: CGPath
        if xScale == 1 {
            resolvedPath = path
        } else {
            var transform = CGAffineTransform(translationX: hotspot.x, y: 0)
                .scaledBy(x: xScale, y: 1)
                .translatedBy(x: -hotspot.x, y: 0)
            resolvedPath = path.copy(using: &transform) ?? path
        }

        return CursorGlyphDrawing(
            path: resolvedPath,
            canvasSize: CGSize(width: size * max(1, xScale), height: size * 1.30),
            hotspot: hotspot,
            strokeWidth: max(1.4, size * strokeScale),
            fillsShape: true
        )
    }

    private static func iBeamDrawing(size: CGFloat, variant: CursorVariant) -> CursorGlyphDrawing {
        let capWidth: CGFloat
        let stemWidth: CGFloat
        let cornerRadius: CGFloat
        switch variant {
        case .standard:
            capWidth = 0.62
            stemWidth = 0.10
            cornerRadius = 0
        case .slim:
            capWidth = 0.48
            stemWidth = 0.06
            cornerRadius = 0
        case .soft:
            capWidth = 0.62
            stemWidth = 0.11
            cornerRadius = size * 0.035
        case .bold:
            capWidth = 0.74
            stemWidth = 0.16
            cornerRadius = 0
        }

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
            strokeWidth: max(1, size * (variant == .bold ? 0.052 : 0.04)),
            fillsShape: true
        )
    }

    private static func dotDrawing(size: CGFloat, variant: CursorVariant) -> CursorGlyphDrawing {
        let diameter: CGFloat
        let fillsShape: Bool
        let strokeScale: CGFloat
        switch variant {
        case .standard:
            diameter = size * 0.58
            fillsShape = true
            strokeScale = 0.08
        case .slim:
            diameter = size * 0.42
            fillsShape = true
            strokeScale = 0.06
        case .soft:
            diameter = size * 0.62
            fillsShape = false
            strokeScale = 0.10
        case .bold:
            diameter = size * 0.72
            fillsShape = true
            strokeScale = 0.09
        }
        let origin = CGPoint(x: (size * 0.90 - diameter) / 2, y: (size * 0.90 - diameter) / 2)
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: origin, size: CGSize(width: diameter, height: diameter)))

        return CursorGlyphDrawing(
            path: path,
            canvasSize: CGSize(width: size * 0.90, height: size * 0.90),
            hotspot: CGPoint(x: size * 0.45, y: size * 0.45),
            strokeWidth: max(1.4, size * strokeScale),
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
    var style: CursorStyle
    var variant: CursorVariant
    var scale: Double
    var alignsHotspot = false

    var body: some View {
        let size = max(12, 24 * CGFloat(scale))
        let resolvedVariant = style.resolvedVariant(variant)
        if let glyph = CursorPresetRenderer.renderedGlyph(style: style, variant: resolvedVariant, size: size) {
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
