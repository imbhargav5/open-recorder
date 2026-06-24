import CoreGraphics

enum CursorOverlayGeometry {
    static let defaultSourceGlyphSize: CGFloat = 20

    static func displayScale(contentRect: CGRect, cropRect: CGRect) -> CGFloat {
        guard contentRect.width.isFinite,
              contentRect.height.isFinite,
              cropRect.width.isFinite,
              cropRect.height.isFinite,
              contentRect.width > 0,
              contentRect.height > 0 else {
            return 0
        }

        let standardizedCrop = cropRect.standardized
        guard standardizedCrop.width > 0,
              standardizedCrop.height > 0 else {
            return 0
        }

        let widthScale = contentRect.width / standardizedCrop.width
        let heightScale = contentRect.height / standardizedCrop.height
        let scale = min(widthScale, heightScale)
        return scale.isFinite ? max(scale, 0) : 0
    }

    static func glyphSize(displayScale: CGFloat, settings: CursorOverlaySettings) -> CGFloat {
        let resolvedScale = displayScale.isFinite ? max(displayScale, 0) : 0
        let multiplier = CGFloat(settings.clamped.size)
        return max(1, defaultSourceGlyphSize * resolvedScale * multiplier)
    }

    static func glyphSize(contentRect: CGRect, cropRect: CGRect, settings: CursorOverlaySettings) -> CGFloat {
        glyphSize(
            displayScale: displayScale(contentRect: contentRect, cropRect: cropRect),
            settings: settings
        )
    }
}
