import CoreGraphics
import Foundation

enum CameraLayout: String, CaseIterable, Identifiable {
    case overlay
    case cameraOnly = "camera-only"
    case split
    case sideBySide = "side-by-side"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overlay: "Overlay"
        case .cameraOnly: "Camera only"
        case .split: "Split screen"
        case .sideBySide: "Screen + small camera"
        }
    }
    var hasScreenPanel: Bool { self == .split || self == .sideBySide }
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

    static func frames(in canvas: CGSize, screenAspectRatio: CGFloat, settings: FacecamSettings) -> Self {
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
        let gap = min(base * settings.resolvedLayoutGap / 100, content.width * 0.4)
        let width = (content.width - gap) * settings.resolvedCameraWidth / 100
        let cameraX = settings.resolvedCameraOnLeft ? content.minX : content.maxX - width
        let screenX = settings.resolvedCameraOnLeft ? content.minX + width + gap : content.minX
        let screenSlot = CGRect(x: screenX, y: content.minY, width: content.width - gap - width, height: content.height)
        let fitted = PreviewStageLayout.fittedSize(forAspectRatio: screenAspectRatio, in: screenSlot.size)
        let fittedScreen = CGRect(x: screenSlot.midX - fitted.width / 2, y: screenSlot.midY - fitted.height / 2,
                            width: fitted.width, height: fitted.height)
        // Split uses a full-height portrait panel; the smaller camera is a centered square.
        let height = settings.resolvedLayout == .split ? content.height : min(width, content.height)
        return Self(screen: settings.resolvedScreenFit == .cover ? screenSlot : fittedScreen, camera: CGRect(x: cameraX, y: content.midY - height / 2, width: width, height: height))
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
