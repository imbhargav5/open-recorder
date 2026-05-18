import AVFoundation
import AppKit
import SwiftUI

enum VideoCropAspect: String, CaseIterable, Identifiable {
    case any
    case widescreen
    case standard
    case square
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .widescreen: "16:9"
        case .standard: "4:3"
        case .square: "1:1"
        case .custom: "Custom"
        }
    }

    func ratio(for selection: VideoCropSelection, sourceSize: CGSize) -> CGFloat? {
        switch self {
        case .any:
            return nil
        case .widescreen:
            return 16.0 / 9.0
        case .standard:
            return 4.0 / 3.0
        case .square:
            return 1
        case .custom:
            if let customSize = selection.sizing.customSize,
               customSize.width > 0,
               customSize.height > 0 {
                return customSize.width / customSize.height
            }
            return selection.previewAspectRatio(in: sourceSize)
        }
    }
}

enum VideoCropKeyboardAdjustment: Equatable {
    case move(dx: Int, dy: Int)
    case resize(widthDelta: Int, heightDelta: Int)

    init?(event: NSEvent) {
        guard event.type == .keyDown,
              let adjustment = Self.make(keyCode: event.keyCode, modifierFlags: event.modifierFlags) else {
            return nil
        }
        self = adjustment
    }

    static func make(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> VideoCropKeyboardAdjustment? {
        guard modifierFlags.intersection([.control, .option]).isEmpty,
              let arrow = VideoCropKeyboardArrow(keyCode: keyCode) else {
            return nil
        }

        let amount = modifierFlags.contains(.shift) ? 10 : 1
        if modifierFlags.contains(.command) {
            switch arrow {
            case .left:
                return .resize(widthDelta: -amount, heightDelta: 0)
            case .right:
                return .resize(widthDelta: amount, heightDelta: 0)
            case .up:
                return .resize(widthDelta: 0, heightDelta: amount)
            case .down:
                return .resize(widthDelta: 0, heightDelta: -amount)
            }
        }

        switch arrow {
        case .left:
            return .move(dx: -amount, dy: 0)
        case .right:
            return .move(dx: amount, dy: 0)
        case .up:
            return .move(dx: 0, dy: -amount)
        case .down:
            return .move(dx: 0, dy: amount)
        }
    }
}

private enum VideoCropKeyboardArrow {
    case left
    case right
    case up
    case down

    init?(keyCode: UInt16) {
        switch keyCode {
        case 123:
            self = .left
        case 124:
            self = .right
        case 125:
            self = .down
        case 126:
            self = .up
        default:
            return nil
        }
    }
}

struct VideoCropDialog: View {
    var videoURL: URL
    var initialTime: Double
    var onConfirm: (VideoCropSelection) -> Void
    var onCancel: () -> Void

    @State private var playback = VideoPlaybackController()
    @State private var driver: VideoCropDriver

    init(
        videoURL: URL,
        initialSelection: VideoCropSelection,
        initialTime: Double,
        sourceSize: CGSize,
        onConfirm: @escaping (VideoCropSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.videoURL = videoURL
        self.initialTime = initialTime
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _driver = State(initialValue: VideoCropDriver(initialSelection: initialSelection, sourceSize: sourceSize))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .frame(height: 78)
                .padding(.horizontal, 24)

            VideoCropCanvas(
                playback: playback,
                selection: driver.selectionBinding,
                aspect: driver.aspectBinding,
                sourceSize: driver.state.effectiveSourceSize
            )
            .padding(.horizontal, 24)
            .padding(.top, 2)

            footer
                .frame(height: 94)
        }
        .frame(width: 960, height: 720)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.25, blue: 0.35),
                    Color(red: 0.13, green: 0.22, blue: 0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            StudioKeyDownMonitor { event in
                handleKeyboardAdjustment(event)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            driver.configure(onConfirm: onConfirm, onCancel: onCancel)
            startStillPreview()
        }
        .onDisappear {
            driver.send(.shortcutsPresented(false))
        }
        .task(id: videoURL) {
            if let loadedSize = await VideoCropMetadataLoader.sourceSize(for: videoURL) {
                await MainActor.run {
                    driver.send(.sourceSizeLoaded(loadedSize))
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            trafficLights

            Spacer(minLength: 16)

            Text("Size")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.36))

            CropNumberField(value: widthBinding)
            Text("x")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
            CropNumberField(value: heightBinding)

            Menu {
                ForEach(VideoCropAspect.allCases) { option in
                    Button(option.title) {
                        applyAspect(option)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle")
                    Text(driver.state.aspect.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: 36)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text("Position")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.36))
                .padding(.leading, 8)

            CropNumberField(value: xBinding)
            CropNumberField(value: yBinding)

            Button {
                resetCrop()
            } label: {
                Label("Reset", systemImage: "crop")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 36)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Button {
                driver.send(.shortcutsPresented(!driver.state.isShortcutDropdownPresented))
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white.opacity(0.88))
                    .background(
                        Color.white.opacity(driver.state.isShortcutDropdownPresented ? 0.13 : 0.07),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
            }
            .buttonStyle(.plain)
            .help("Keyboard shortcuts")
            .popover(isPresented: driver.shortcutBinding, arrowEdge: .top) {
                VideoCropKeyboardShortcutsDropdown()
            }
        }
    }

    private var trafficLights: some View {
        HStack(spacing: 9) {
            Circle().fill(Color(red: 1.0, green: 0.25, blue: 0.27))
            Circle().fill(Color.white.opacity(0.22))
            Circle().fill(Color.white.opacity(0.22))
        }
        .frame(width: 60, height: 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                driver.send(.confirmRequested)
            } label: {
                Label("Confirm changes", systemImage: "return")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: 36)
                    .padding(.horizontal, 12)
                    .background(Color(red: 0.33, green: 0.20, blue: 1.0), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                driver.send(.cancelRequested)
            } label: {
                Text("Discard changes")
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: 36)
                    .padding(.horizontal, 13)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08))
                    }
                    .foregroundStyle(.white.opacity(0.92))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var effectiveSourceSize: CGSize {
        driver.state.effectiveSourceSize
    }

    private var currentPixelRect: CGRect {
        driver.state.currentPixelRect
    }

    private var widthBinding: Binding<Int> {
        driver.widthBinding()
    }

    private var heightBinding: Binding<Int> {
        driver.heightBinding()
    }

    private var xBinding: Binding<Int> {
        driver.xBinding()
    }

    private var yBinding: Binding<Int> {
        driver.yBinding()
    }

    private func handleKeyboardAdjustment(_ event: NSEvent) -> Bool {
        guard let adjustment = VideoCropKeyboardAdjustment(event: event) else { return false }
        applyKeyboardAdjustment(adjustment)
        return true
    }

    private func applyKeyboardAdjustment(_ adjustment: VideoCropKeyboardAdjustment) {
        driver.send(.keyboardAdjusted(adjustment))
    }

    private func applyAspect(_ option: VideoCropAspect) {
        driver.send(.aspectSelected(option))
    }

    private func resetCrop() {
        driver.send(.reset)
    }

    private func startStillPreview() {
        playback.load(url: videoURL)
        playback.pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            playback.seek(to: initialTime)
            playback.pause()
        }
    }
}

private struct VideoCropKeyboardShortcutsDropdown: View {
    private let shortcuts = [
        VideoCropShortcutHelpItem(keys: "←", action: "Move left by 1px"),
        VideoCropShortcutHelpItem(keys: "→", action: "Move right by 1px"),
        VideoCropShortcutHelpItem(keys: "↑", action: "Move up by 1px"),
        VideoCropShortcutHelpItem(keys: "↓", action: "Move down by 1px"),
        VideoCropShortcutHelpItem(keys: "⇧ ←", action: "Move left by 10px"),
        VideoCropShortcutHelpItem(keys: "⇧ →", action: "Move right by 10px"),
        VideoCropShortcutHelpItem(keys: "⇧ ↑", action: "Move up by 10px"),
        VideoCropShortcutHelpItem(keys: "⇧ ↓", action: "Move down by 10px"),
        VideoCropShortcutHelpItem(keys: "⌘ ←", action: "Reduce width by 1px"),
        VideoCropShortcutHelpItem(keys: "⌘ →", action: "Increase width by 1px"),
        VideoCropShortcutHelpItem(keys: "⌘ ↑", action: "Increase height by 1px"),
        VideoCropShortcutHelpItem(keys: "⌘ ↓", action: "Reduce height by 1px"),
        VideoCropShortcutHelpItem(keys: "⌘ ⇧ ←", action: "Reduce width by 10px"),
        VideoCropShortcutHelpItem(keys: "⌘ ⇧ →", action: "Increase width by 10px"),
        VideoCropShortcutHelpItem(keys: "⌘ ⇧ ↑", action: "Increase height by 10px"),
        VideoCropShortcutHelpItem(keys: "⌘ ⇧ ↓", action: "Reduce height by 10px")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shortcuts) { shortcut in
                HStack(spacing: 12) {
                    Text(shortcut.keys)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .frame(width: 54, height: 24)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }

                    Text(shortcut.action)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.64))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.10, green: 0.13, blue: 0.16))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct VideoCropShortcutHelpItem: Identifiable {
    var keys: String
    var action: String

    var id: String { keys }
}

private struct VideoCropCanvas: View {
    var playback: VideoPlaybackController
    @Binding var selection: VideoCropSelection
    @Binding var aspect: VideoCropAspect
    var sourceSize: CGSize

    @State private var drawStart: CGPoint?
    @State private var moveStartRect: CGRect?
    @State private var resizeStartRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let safeSourceSize = VideoCropSelection.safeSourceSize(sourceSize)
            let videoFrame = VideoCropGeometry.fittedVideoFrame(sourceSize: safeSourceSize, in: proxy.size)
            let cropRect = selection.pixelRect(in: safeSourceSize)
            let displayRect = VideoCropGeometry.displayRect(for: cropRect, sourceSize: safeSourceSize, videoFrame: videoFrame)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.18)

                NativeVideoPlayer(playback: playback)
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .position(x: videoFrame.midX, y: videoFrame.midY)
                    .clipped()

                drawHitArea(videoFrame: videoFrame, sourceSize: safeSourceSize)

                dimmedOutsideCrop(videoFrame: videoFrame, cropRect: displayRect)
                    .allowsHitTesting(false)

                cropOverlay(displayRect: displayRect, videoFrame: videoFrame, sourceSize: safeSourceSize)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func drawHitArea(videoFrame: CGRect, sourceSize: CGSize) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: videoFrame.width, height: videoFrame.height)
            .position(x: videoFrame.midX, y: videoFrame.midY)
            .contentShape(Rectangle())
            .gesture(drawGesture(videoFrame: videoFrame, sourceSize: sourceSize))
    }

    private func dimmedOutsideCrop(videoFrame: CGRect, cropRect: CGRect) -> some View {
        Group {
            dimRect(CGRect(x: videoFrame.minX, y: videoFrame.minY, width: videoFrame.width, height: max(0, cropRect.minY - videoFrame.minY)))
            dimRect(CGRect(x: videoFrame.minX, y: cropRect.maxY, width: videoFrame.width, height: max(0, videoFrame.maxY - cropRect.maxY)))
            dimRect(CGRect(x: videoFrame.minX, y: cropRect.minY, width: max(0, cropRect.minX - videoFrame.minX), height: cropRect.height))
            dimRect(CGRect(x: cropRect.maxX, y: cropRect.minY, width: max(0, videoFrame.maxX - cropRect.maxX), height: cropRect.height))
        }
    }

    private func dimRect(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.48))
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .position(x: rect.midX, y: rect.midY)
    }

    private func cropOverlay(displayRect: CGRect, videoFrame: CGRect, sourceSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)
                .contentShape(Rectangle())
                .gesture(moveGesture(videoFrame: videoFrame, sourceSize: sourceSize))

            CropGuideLines()
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)
                .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white.opacity(0.92), lineWidth: 1.4)
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)
                .allowsHitTesting(false)

            ForEach(CropHandle.allCases) { handle in
                CropHandleView()
                    .position(handle.point(in: displayRect))
                    .gesture(resizeGesture(handle: handle, videoFrame: videoFrame, sourceSize: sourceSize))
            }
        }
    }

    private func drawGesture(videoFrame: CGRect, sourceSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if drawStart == nil {
                    drawStart = clamped(value.startLocation, to: videoFrame)
                }
                guard let drawStart else { return }
                let current = clamped(value.location, to: videoFrame)
                var displayRect = CGRect(
                    x: min(drawStart.x, current.x),
                    y: min(drawStart.y, current.y),
                    width: abs(current.x - drawStart.x),
                    height: abs(current.y - drawStart.y)
                )
                if let ratio = aspect.ratio(for: selection, sourceSize: sourceSize) {
                    displayRect = rect(displayRect, adjustedTo: ratio, in: videoFrame)
                }
                let pixelRect = VideoCropGeometry.pixelRect(for: displayRect, sourceSize: sourceSize, videoFrame: videoFrame)
                selection = selection
                    .withPixelRect(pixelRect, in: sourceSize)
                    .withSizing(.custom(width: Int(pixelRect.width.rounded()), height: Int(pixelRect.height.rounded())))
            }
            .onEnded { _ in
                drawStart = nil
            }
    }

    private func moveGesture(videoFrame: CGRect, sourceSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if moveStartRect == nil {
                    moveStartRect = selection.pixelRect(in: sourceSize)
                }
                guard let moveStartRect else { return }
                let dx = value.translation.width / max(videoFrame.width, 1) * sourceSize.width
                let dy = value.translation.height / max(videoFrame.height, 1) * sourceSize.height
                selection = selection.withPixelRect(moveStartRect.offsetBy(dx: dx, dy: dy), in: sourceSize)
            }
            .onEnded { _ in
                moveStartRect = nil
            }
    }

    private func resizeGesture(handle: CropHandle, videoFrame: CGRect, sourceSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if resizeStartRect == nil {
                    resizeStartRect = selection.pixelRect(in: sourceSize)
                }
                guard let resizeStartRect else { return }
                let point = pixelPoint(for: value.location, videoFrame: videoFrame, sourceSize: sourceSize)
                var nextRect = handle.resizedRect(from: resizeStartRect, to: point)
                if let ratio = aspect.ratio(for: selection, sourceSize: sourceSize) {
                    nextRect = rect(nextRect, adjustedTo: ratio, in: CGRect(origin: .zero, size: sourceSize))
                }
                nextRect = VideoCropSelection.clampedPixelRect(nextRect, in: sourceSize)
                selection = selection
                    .withPixelRect(nextRect, in: sourceSize)
                    .withSizing(.custom(width: Int(nextRect.width.rounded()), height: Int(nextRect.height.rounded())))
            }
            .onEnded { _ in
                resizeStartRect = nil
            }
    }

    private func pixelPoint(for displayPoint: CGPoint, videoFrame: CGRect, sourceSize: CGSize) -> CGPoint {
        let clampedPoint = clamped(displayPoint, to: videoFrame)
        return CGPoint(
            x: (clampedPoint.x - videoFrame.minX) / max(videoFrame.width, 1) * sourceSize.width,
            y: (clampedPoint.y - videoFrame.minY) / max(videoFrame.height, 1) * sourceSize.height
        )
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func rect(_ rect: CGRect, adjustedTo ratio: CGFloat, in bounds: CGRect) -> CGRect {
        guard ratio.isFinite, ratio > 0 else { return rect }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var width = rect.width
        var height = rect.height
        if width / max(height, 1) > ratio {
            width = height * ratio
        } else {
            height = width / ratio
        }
        let adjusted = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        return adjusted.intersection(bounds).isNull ? rect : adjusted
    }
}

private struct CropNumberField: View {
    @Binding var value: Int

    var body: some View {
        TextField("", value: $value, formatter: NumberFormatter.cropInteger)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(width: 64, height: 36)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct CropGuideLines: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
            }
            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }
    }
}

private struct CropHandleView: View {
    var body: some View {
        Circle()
            .fill(Color.black.opacity(0.92))
            .frame(width: 10, height: 10)
            .overlay {
                Circle()
                    .stroke(Color.white, lineWidth: 1.4)
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}

private enum CropHandle: CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var id: String {
        String(describing: self)
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .right:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .left:
            CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func resizedRect(from rect: CGRect, to point: CGPoint) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch self {
        case .topLeft:
            minX = point.x
            minY = point.y
        case .top:
            minY = point.y
        case .topRight:
            maxX = point.x
            minY = point.y
        case .right:
            maxX = point.x
        case .bottomRight:
            maxX = point.x
            maxY = point.y
        case .bottom:
            maxY = point.y
        case .bottomLeft:
            minX = point.x
            maxY = point.y
        case .left:
            minX = point.x
        }

        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }
}

private enum VideoCropMetadataLoader {
    static func sourceSize(for url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform) else {
            return nil
        }
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let size = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return nil
        }
        return size
    }
}

private extension NumberFormatter {
    static let cropInteger: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximumFractionDigits = 0
        formatter.generatesDecimalNumbers = false
        return formatter
    }()
}
