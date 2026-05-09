import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct AreaSelectionWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                if let selectionRect {
                    Rectangle()
                        .fill(Color.clear)
                        .overlay {
                            Rectangle()
                                .stroke(Color.white, lineWidth: 2)
                        }
                        .background(Color.white.opacity(0.08))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                }

                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 26, weight: .medium))
                    Text("Drag to select an area")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Release to start \(model.captureMode == .recording ? "recording" : "capturing"). Press Esc to cancel.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(selectionRect == nil ? 1 : 0)
            }
            .rectangularHitTarget()
            .gesture(selectionGesture(in: proxy.size))
            .onKeyPress(.escape) {
                model.cancelInteractiveAreaSelection()
                dismiss()
                dismissWindow(id: "area-selector")
                return .handled
            }
        }
        .focusable()
        .focusedValue(\.areaSelectionIsFocused, true)
        .onAppear {
            dragStart = nil
            dragCurrent = nil
            DispatchQueue.main.async {
                if !model.isAreaSelectionActive {
                    dismiss()
                    dismissWindow(id: "area-selector")
                }
            }
        }
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    private func selectionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = clamped(value.startLocation, to: size)
                }
                dragCurrent = clamped(value.location, to: size)
            }
            .onEnded { _ in
                guard let rect = selectionRect, rect.width >= 8, rect.height >= 8 else {
                    dragStart = nil
                    dragCurrent = nil
                    return
                }

                dismiss()
                dismissWindow(id: "area-selector")
                let area = captureArea(for: rect)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    model.completeInteractiveAreaSelection(area)
                }
            }
    }

    private func clamped(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
    }

    private func captureArea(for rect: CGRect) -> CaptureArea {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(origin: .zero, size: CGSize(width: 900, height: 600))
        return CaptureArea(
            x: Int((screenFrame.minX + rect.minX).rounded()),
            y: Int((screenFrame.maxY - rect.maxY).rounded()),
            width: max(Int(rect.width.rounded()), 1),
            height: max(Int(rect.height.rounded()), 1),
            displayID: (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )
    }
}

struct AreaSelectionFocusKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var areaSelectionIsFocused: Bool? {
        get { self[AreaSelectionFocusKey.self] }
        set { self[AreaSelectionFocusKey.self] = newValue }
    }
}

