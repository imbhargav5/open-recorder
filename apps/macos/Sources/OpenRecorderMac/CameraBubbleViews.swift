import AVFoundation
import AppKit
import SwiftUI

enum CameraBubbleShape: String, CaseIterable, Identifiable, Codable {
    case circle
    case square
    case rectangle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: return "Circle"
        case .square: return "Square"
        case .rectangle: return "Rectangle"
        }
    }

    var symbolName: String {
        switch self {
        case .circle: return "circle.fill"
        case .square: return "square.fill"
        case .rectangle: return "rectangle.fill"
        }
    }
}

struct CameraBubbleWindowView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("camera_bubble_shape") private var selectedShape: CameraBubbleShape = .circle
    @AppStorage("camera_bubble_diameter") private var storedDiameter: Double = 220.0
    @AppStorage("camera_bubble_mirrored") private var isMirrored: Bool = true

    @State private var liveDiameter: Double = 220.0
    @State private var isHovering = false
    @State private var isResizing = false

    private let minDiameter: Double = 130.0
    private let maxDiameter: Double = 460.0

    private var currentDimensions: CGSize {
        let clamped = max(minDiameter, min(liveDiameter, maxDiameter))
        switch selectedShape {
        case .circle, .square:
            return CGSize(width: clamped, height: clamped)
        case .rectangle:
            let width = clamped * 1.35
            let height = width * (9.0 / 16.0)
            return CGSize(width: width, height: height)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Camera Feed (Anchor: its center never shifts)
            ZStack(alignment: .bottomTrailing) {
                shapedVideoPreview
                    .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 5)

                // Elegant corner resize grip inside the bubble
                if isHovering || isResizing {
                    resizeGrip
                        .padding(selectedShape == .circle ? 16 : 10)
                        .transition(.opacity)
                }
            }
            .frame(width: currentDimensions.width, height: currentDimensions.height)
            .padding(.bottom, 42) // Stable space for toolbar below without shifting center

            // Floating Controls Pill Below the Bubble
            if isHovering || isResizing {
                floatingControlsPill
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .padding(.bottom, 2)
            }
        }
        .padding(14)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selectedShape)
        .onAppear {
            liveDiameter = max(minDiameter, min(storedDiameter, maxDiameter))
            model.prepareCameraIfNeeded()
        }
    }

    @ViewBuilder
    private var videoContent: some View {
        if let session = model.cameraCaptureSession, session.isRunning {
            CameraVideoPreviewRepresentable(session: session, isMirrored: isMirrored)
        } else {
            cameraFallbackView
        }
    }

    @ViewBuilder
    private var shapedVideoPreview: some View {
        let borderStroke = LinearGradient(
            colors: [
                Color.white.opacity(0.30),
                Color.white.opacity(0.10),
                Color.black.opacity(0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        switch selectedShape {
        case .circle:
            videoContent
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(borderStroke, lineWidth: 1.2)
                }
        case .square:
            let radius = min(32.0, currentDimensions.width * 0.18)
            videoContent
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(borderStroke, lineWidth: 1.2)
                }
        case .rectangle:
            let radius = min(24.0, currentDimensions.height * 0.16)
            videoContent
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(borderStroke, lineWidth: 1.2)
                }
        }
    }

    private var cameraFallbackView: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.10)
            VStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.70))
                Text("Starting Camera...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.60))
            }
        }
    }

    private var floatingControlsPill: some View {
        HStack(spacing: 8) {
            // Shape Switcher
            HStack(spacing: 3) {
                ForEach(CameraBubbleShape.allCases) { shape in
                    let isSelected = selectedShape == shape
                    Button {
                        selectedShape = shape
                    } label: {
                        Image(systemName: shape.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.40))
                            .frame(width: 22, height: 22)
                            .background(
                                isSelected ? Color.white.opacity(0.20) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(shape.title)
                }
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 14)

            // Mirror Flip
            Button {
                isMirrored.toggle()
            } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isMirrored ? Color.white : Color.white.opacity(0.40))
                    .frame(width: 22, height: 22)
                    .background(
                        isMirrored ? Color.white.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help("Mirror Camera Preview")

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 14)

            // Close / Turn Off Button
            Button {
                model.disableCamera()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Turn Off Camera")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.88),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
    }

    private var resizeGrip: some View {
        ZStack {
            CameraResizeGripRepresentable(
                onResizeDelta: { delta in
                    isResizing = true
                    liveDiameter = max(minDiameter, min(liveDiameter + delta, maxDiameter))
                },
                onResizeEnded: {
                    isResizing = false
                    storedDiameter = liveDiameter
                }
            )

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(isResizing ? 0.95 : 0.65))
                .allowsHitTesting(false)
        }
        .frame(width: 22, height: 22)
        .background(
            Color.black.opacity(isResizing ? 0.75 : 0.45),
            in: Circle()
        )
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 4, y: 2)
        .help("Drag to resize camera bubble")
    }
}

struct CameraResizeGripRepresentable: NSViewRepresentable {
    var onResizeDelta: (CGFloat) -> Void
    var onResizeEnded: () -> Void

    func makeNSView(context: Context) -> CameraResizeGripNSView {
        let view = CameraResizeGripNSView()
        view.onResizeDelta = onResizeDelta
        view.onResizeEnded = onResizeEnded
        return view
    }

    func updateNSView(_ nsView: CameraResizeGripNSView, context: Context) {
        nsView.onResizeDelta = onResizeDelta
        nsView.onResizeEnded = onResizeEnded
    }
}

final class CameraResizeGripNSView: NSView {
    override var isFlipped: Bool { true }
    var onResizeDelta: ((CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?

    private var initialMouseScreenLocation: NSPoint = .zero

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseScreenLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let currentMouseScreenLocation = NSEvent.mouseLocation
        let deltaX = currentMouseScreenLocation.x - initialMouseScreenLocation.x
        let deltaY = initialMouseScreenLocation.y - currentMouseScreenLocation.y // Invert screen Y
        let delta = (deltaX + deltaY) * 0.85
        initialMouseScreenLocation = currentMouseScreenLocation
        onResizeDelta?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        onResizeEnded?()
    }
}

struct CameraVideoPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession
    var isMirrored: Bool = true

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.previewLayer.session = session
        view.setMirrored(isMirrored)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        nsView.setMirrored(isMirrored)
    }
}

final class CameraPreviewNSView: NSView {
    override var isFlipped: Bool { true }

    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    func setMirrored(_ mirrored: Bool) {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}
