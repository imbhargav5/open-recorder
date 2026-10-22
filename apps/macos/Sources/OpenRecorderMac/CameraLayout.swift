import CoreGraphics
import Foundation

enum CameraLayout: String, CaseIterable, Identifiable {
    case overlay
    case screenOnly = "screen-only"
    case cameraOnly = "camera-only"
    case split
    /// A stacked, full-width split intended for portrait canvases.
    case verticalSplit = "vertical-split"
    case sideBySide = "side-by-side"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overlay: "Overlay"
        case .screenOnly: "Screen only"
        case .cameraOnly: "Camera only"
        case .split: "Split screen"
        case .verticalSplit: "Stacked split"
        case .sideBySide: "Screen + small camera"
        }
    }
    var hasScreenPanel: Bool { self == .split || self == .verticalSplit || self == .sideBySide }
    var isVerticalSplit: Bool { self == .verticalSplit }
    var hidesCamera: Bool { self == .screenOnly }
}

enum CameraScreenFit: String, CaseIterable, Identifiable {
    case fit
    case cover

    var id: String { rawValue }
    var title: String { self == .fit ? "Fit" : "Cover" }
}

/// Shared top-left-origin geometry for the editor and exported frames.
/// Percentages divide the usable width after padding and the gap are removed.
struct CameraLayoutGeometry {
    var screen: CGRect
    var camera: CGRect

    static func clamp(_ value: Double?, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// Panel decorations use 1080p as their reference, so previews and exports scale together.
    static func decorationScale(in canvas: CGSize, settings: FacecamSettings) -> CGFloat {
        settings.resolvedLayout == .overlay ? 1 : min(canvas.width, canvas.height) / 1080
    }

    /// The screen zoom must never pan the overlay camera off canvas. Gently
    /// shrink its existing frame in place, including its border and shadow.
    /// Blending by overlayAmount keeps layout transitions continuous.
    static func overlayZoomTransform(frame: CGRect, depth: Double, overlayAmount: CGFloat, shrinkAmount: CGFloat = 0.15) -> CGAffineTransform {
        guard !frame.isEmpty, depth.isFinite, depth > 1 else { return .identity }
        let zoom = CameraLayoutMotion.ease(min(1, (depth - 1) / 0.75))
        let amount = CGFloat(clamp(Double(shrinkAmount), to: 0...0.75, fallback: 0.15))
        let scale = 1 - amount * CGFloat(zoom) * min(1, max(0, overlayAmount))
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                tx: frame.midX * (1 - scale), ty: frame.midY * (1 - scale))
    }

    static func frames(in canvas: CGSize, screenAspectRatio: CGFloat, settings: FacecamSettings) -> Self {
        if settings.resolvedLayout == .screenOnly,
           canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0 {
            let base = min(canvas.width, canvas.height)
            let padding = base * settings.resolvedLayoutPadding / 100
            let content = CGRect(origin: .zero, size: canvas).insetBy(dx: padding, dy: padding)
            return Self(screen: content, camera: .zero)
        }
        guard canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0,
              settings.enabled, settings.resolvedLayout != .overlay else {
            return Self(screen: .zero, camera: .zero)
        }
        let base = min(canvas.width, canvas.height)
        let padding = base * settings.resolvedLayoutPadding / 100
        let content = CGRect(origin: .zero, size: canvas).insetBy(dx: padding, dy: padding)
        if settings.resolvedLayout == .cameraOnly {
            return Self(screen: .zero, camera: content)
        }
        let isVertical = settings.resolvedLayout.isVerticalSplit
        let gap = min(base * settings.resolvedLayoutGap / 100, (isVertical ? content.height : content.width) * 0.4)
        let share = (isVertical ? content.height : content.width - gap) * settings.resolvedCameraWidth / 100
        let cameraFrame: CGRect
        let screenSlot: CGRect
        if isVertical {
            let cameraY = settings.resolvedCameraAbove ? content.minY : content.maxY - share
            let screenY = settings.resolvedCameraAbove ? content.minY + share + gap : content.minY
            cameraFrame = CGRect(x: content.minX, y: cameraY, width: content.width, height: share)
            screenSlot = CGRect(x: content.minX, y: screenY, width: content.width, height: content.height - share - gap)
        } else {
            let cameraX = settings.resolvedCameraOnLeft ? content.minX : content.maxX - share
            let screenX = settings.resolvedCameraOnLeft ? content.minX + share + gap : content.minX
            let cameraHeight = settings.resolvedLayout == .split ? content.height : min(share, content.height)
            cameraFrame = CGRect(x: cameraX, y: content.midY - cameraHeight / 2, width: share, height: cameraHeight)
            screenSlot = CGRect(x: screenX, y: content.minY, width: content.width - gap - share, height: content.height)
        }
        let fitted = PreviewStageLayout.fittedSize(forAspectRatio: screenAspectRatio, in: screenSlot.size)
        let fittedScreen = CGRect(x: screenSlot.midX - fitted.width / 2, y: screenSlot.midY - fitted.height / 2,
                            width: fitted.width, height: fitted.height)
        return Self(screen: settings.resolvedScreenFit == .cover ? screenSlot : fittedScreen, camera: cameraFrame)
    }

    /// Center-crop within the user's existing crop, preserving source coordinates for cursor and zoom tracking.
    static func screenCrop(in crop: CGRect, panel: CGSize, fit: CameraScreenFit) -> CGRect {
        guard fit == .cover, crop.width > 0, crop.height > 0, panel.width > 0, panel.height > 0 else { return crop }
        let scale = max(panel.width / crop.width, panel.height / crop.height)
        let size = CGSize(width: panel.width / scale, height: panel.height / scale)
        return CGRect(x: crop.midX - size.width / 2, y: crop.midY - size.height / 2, width: size.width, height: size.height)
    }

    static func screenCornerRadius(in canvas: CGSize, settings: FacecamSettings) -> CGFloat {
        CGFloat(settings.resolvedScreenCornerRadius) * decorationScale(in: canvas, settings: settings)
    }

}
