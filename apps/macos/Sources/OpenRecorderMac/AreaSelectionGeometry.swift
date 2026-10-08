import CoreGraphics

enum AreaSelectionResizeCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topLeft: "top left"
        case .topRight: "top right"
        case .bottomLeft: "bottom left"
        case .bottomRight: "bottom right"
        }
    }
    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: self == .topLeft || self == .bottomLeft ? rect.minX : rect.maxX,
                y: self == .topLeft || self == .topRight ? rect.minY : rect.maxY)
    }
}

enum AreaSelectionGeometry {
    static func moved(_ rect: CGRect, translation: CGSize, bounds: CGSize) -> CGRect {
        CGRect(x: min(max(0, rect.minX + translation.width), bounds.width - rect.width).rounded(),
               y: min(max(0, rect.minY + translation.height), bounds.height - rect.height).rounded(),
               width: rect.width, height: rect.height)
    }

    static func resized(_ rect: CGRect, corner: AreaSelectionResizeCorner, translation: CGSize, bounds: CGSize) -> CGRect {
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let x0 = left ? min(max(0, rect.minX + translation.width), rect.maxX - 8) : rect.minX
        let x1 = left ? rect.maxX : max(min(bounds.width, rect.maxX + translation.width), rect.minX + 8)
        let y0 = top ? min(max(0, rect.minY + translation.height), rect.maxY - 8) : rect.minY
        let y1 = top ? rect.maxY : max(min(bounds.height, rect.maxY + translation.height), rect.minY + 8)
        return CGRect(x: x0.rounded(), y: y0.rounded(), width: (x1 - x0).rounded(), height: (y1 - y0).rounded())
    }

    static func alignedSelectionRect(between start: CGPoint, and current: CGPoint) -> CGRect {
        let minX = min(start.x, current.x).rounded()
        let maxX = max(start.x, current.x).rounded()
        let minY = min(start.y, current.y).rounded()
        let maxY = max(start.y, current.y).rounded()

        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    static func captureArea(
        for selectionRect: CGRect,
        on screenFrame: CGRect,
        displayID: UInt32?
    ) -> CaptureArea {
        let minX = Int((screenFrame.minX + selectionRect.minX).rounded())
        let maxX = Int((screenFrame.minX + selectionRect.maxX).rounded())
        let minY = Int((screenFrame.maxY - selectionRect.maxY).rounded())
        let maxY = Int((screenFrame.maxY - selectionRect.minY).rounded())

        return CaptureArea(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1),
            height: max(maxY - minY, 1),
            displayID: displayID
        )
    }
}
