import CoreGraphics

enum AreaSelectionGeometry {
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
