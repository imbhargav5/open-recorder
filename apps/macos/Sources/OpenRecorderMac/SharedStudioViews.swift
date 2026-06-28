import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum HUDWindowMetrics {
    static let height: CGFloat = 155
    static let horizontalScreenMargin: CGFloat = 32
    static let minWidth: CGFloat = 360
    static let defaultSize = CGSize(width: 620, height: height)

    static func clampedSize(for measuredSize: CGSize, screen: NSScreen?) -> CGSize {
        clampedSize(for: measuredSize, visibleFrame: screen?.visibleFrame)
    }

    static func clampedSize(for measuredSize: CGSize, visibleFrame: CGRect?) -> CGSize {
        let measuredWidth = measuredSize.width.isFinite && measuredSize.width > 0
            ? measuredSize.width.rounded(.up)
            : defaultSize.width
        let maximumWidth = visibleFrame.map { frame in
            max(minWidth, frame.width - horizontalScreenMargin * 2)
        } ?? CGFloat.greatestFiniteMagnitude
        let width = min(max(measuredWidth, minWidth), maximumWidth)

        return CGSize(width: width.rounded(.up), height: height)
    }
}

struct SizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        guard next != .zero else { return }
        value = next
    }
}

extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }

    func rectangularHitTarget() -> some View {
        contentShape(Rectangle())
    }

    func roundedHitTarget(_ cornerRadius: CGFloat) -> some View {
        contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func capsuleHitTarget() -> some View {
        contentShape(Capsule())
    }

    func circleHitTarget() -> some View {
        contentShape(Circle())
    }

    @ViewBuilder
    func studioEditorPaneChrome(clipContent: Bool = true) -> some View {
        let chrome = background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface.opacity(0.88))
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.055),
                                Color.white.opacity(0.012),
                                Color.black.opacity(0.045)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.borderStrong.opacity(0.72), lineWidth: 1)
            }

        if clipContent {
            chrome.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            chrome
        }
    }

    @ViewBuilder
    func studioHitTarget(_ target: StudioHitTarget) -> some View {
        switch target {
        case .rectangle:
            rectangularHitTarget()
        case .rounded(let cornerRadius):
            roundedHitTarget(cornerRadius)
        case .capsule:
            capsuleHitTarget()
        case .circle:
            circleHitTarget()
        }
    }
}

enum StudioHitTarget {
    case rectangle
    case rounded(CGFloat)
    case capsule
    case circle
}

enum StudioSplitPaneAxis {
    case horizontal
    case vertical

    func length(in size: CGSize) -> CGFloat {
        switch self {
        case .horizontal:
            size.width
        case .vertical:
            size.height
        }
    }
}

struct StudioSplitPane<Primary: View, Secondary: View>: View {
    var axis: StudioSplitPaneAxis
    var secondarySize: CGFloat
    var minPrimarySize: CGFloat
    var minSecondarySize: CGFloat
    var maxSecondarySize: CGFloat
    var spacing: CGFloat
    private let primary: Primary
    private let secondary: Secondary

    init(
        axis: StudioSplitPaneAxis,
        secondarySize: CGFloat,
        minPrimarySize: CGFloat,
        minSecondarySize: CGFloat,
        maxSecondarySize: CGFloat,
        spacing: CGFloat = 12,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.axis = axis
        self.secondarySize = secondarySize
        self.minPrimarySize = minPrimarySize
        self.minSecondarySize = minSecondarySize
        self.maxSecondarySize = maxSecondarySize
        self.spacing = spacing
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        GeometryReader { proxy in
            let totalSize = axis.length(in: proxy.size)
            let resolvedSecondarySize = clampedSecondarySize(totalSize: totalSize)
            let paneSpacing = resolvedSecondarySize > 0 ? spacing : 0
            let resolvedPrimarySize = max(0, totalSize - resolvedSecondarySize - paneSpacing)

            if axis == .horizontal {
                HStack(spacing: paneSpacing) {
                    primary
                        .frame(width: resolvedPrimarySize, height: proxy.size.height)
                        .clipped()
                    secondary
                        .frame(width: resolvedSecondarySize, height: proxy.size.height)
                        .clipped()
                }
            } else {
                VStack(spacing: paneSpacing) {
                    primary
                        .frame(width: proxy.size.width, height: resolvedPrimarySize)
                        .clipped()
                    secondary
                        .frame(width: proxy.size.width, height: resolvedSecondarySize)
                        .clipped()
                }
            }
        }
    }

    private func clampedSecondarySize(totalSize: CGFloat) -> CGFloat {
        let requestedSize = secondarySize
        let safeSize = requestedSize.isFinite && requestedSize > 0 ? requestedSize : minSecondarySize
        return clampedSecondarySize(safeSize, totalSize: totalSize)
    }

    private func clampedSecondarySize(_ requestedSize: CGFloat, totalSize: CGFloat) -> CGFloat {
        let availablePaneSize = max(0, totalSize)
        guard availablePaneSize > 0 else { return 0 }

        let idealUpperBound = min(maxSecondarySize, max(0, availablePaneSize - minPrimarySize))
        if idealUpperBound >= minSecondarySize {
            return min(max(requestedSize, minSecondarySize), idealUpperBound)
        }

        let visiblePaneSize = min(96, availablePaneSize / 2)
        let fallbackUpperBound = max(0, availablePaneSize - visiblePaneSize)
        let fallbackLowerBound = min(visiblePaneSize, fallbackUpperBound)
        return min(max(requestedSize, fallbackLowerBound), fallbackUpperBound)
    }
}

struct ResizableStudioSplitPane<Primary: View, Secondary: View>: View {
    @Binding var secondarySize: CGFloat
    var minPrimarySize: CGFloat
    var minSecondarySize: CGFloat
    var maxSecondarySize: CGFloat
    var spacing: CGFloat
    private let primary: Primary
    private let secondary: Secondary

    init(
        secondarySize: Binding<CGFloat>,
        minPrimarySize: CGFloat,
        minSecondarySize: CGFloat,
        maxSecondarySize: CGFloat,
        spacing: CGFloat = 12,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self._secondarySize = secondarySize
        self.minPrimarySize = minPrimarySize
        self.minSecondarySize = minSecondarySize
        self.maxSecondarySize = maxSecondarySize
        self.spacing = spacing
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedSecondarySize = clampedSecondarySize(secondarySize, totalSize: proxy.size.width)
            let resolvedPrimarySize = max(0, proxy.size.width - resolvedSecondarySize - spacing)

            HStack(spacing: 0) {
                primary
                    .frame(width: resolvedPrimarySize, height: proxy.size.height)
                    .clipped()

                SidebarResizeHandle()
                    .frame(width: spacing, height: proxy.size.height)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                secondarySize = clampedSecondarySize(
                                    resolvedSecondarySize - value.translation.width,
                                    totalSize: proxy.size.width
                                )
                            }
                    )

                secondary
                    .frame(width: resolvedSecondarySize, height: proxy.size.height)
                    .zIndex(1)
            }
        }
        .onChange(of: secondarySize) { _, newValue in
            secondarySize = min(max(newValue, minSecondarySize), maxSecondarySize)
        }
    }

    private func clampedSecondarySize(_ requestedSize: CGFloat, totalSize: CGFloat) -> CGFloat {
        let maxAllowedByPrimary = max(0, totalSize - minPrimarySize - spacing)
        let upperBound = min(maxSecondarySize, maxAllowedByPrimary)
        guard upperBound >= minSecondarySize else {
            return max(0, upperBound)
        }
        return min(max(requestedSize, minSecondarySize), upperBound)
    }
}

struct SidebarResizeHandle: View {
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            Capsule()
                .fill(isHovering ? Theme.borderStrong.opacity(0.72) : Color.clear)
                .frame(width: 3, height: 42)
        }
        .rectangularHitTarget()
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.pop()
            }
        }
    }
}

struct StudioButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    var hitTarget: StudioHitTarget
    var help: String?
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    init(
        hitTarget: StudioHitTarget = .rectangle,
        help: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.hitTarget = hitTarget
        self.help = help
        self.action = action
        self.label = label
    }

    var body: some View {
        let control = Button(action: action) {
            label()
                .studioHitTarget(hitTarget)
                .scaleEffect(isHovering && isEnabled ? 1.018 : 1)
                .brightness(isHovering && isEnabled ? 0.035 : 0)
                .animation(.snappy(duration: 0.16), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }

        if let help {
            control.help(help)
        } else {
            control
        }
    }
}

struct StudioMenu<Label: View, Content: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    var hitTarget: StudioHitTarget
    var help: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    init(
        hitTarget: StudioHitTarget = .rectangle,
        help: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.hitTarget = hitTarget
        self.help = help
        self.content = content
        self.label = label
    }

    var body: some View {
        let control = Menu {
            content()
        } label: {
            label()
                .studioHitTarget(hitTarget)
                .scaleEffect(isHovering && isEnabled ? 1.018 : 1)
                .brightness(isHovering && isEnabled ? 0.035 : 0)
                .animation(.snappy(duration: 0.16), value: isHovering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovering in
            isHovering = hovering
        }

        if let help {
            control.help(help)
        } else {
            control
        }
    }
}

struct StudioKeyDownMonitor: NSViewRepresentable {
    var isEnabled = true
    var handler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.handler = handler
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.handler = handler
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        weak var view: NSView?
        var handler: (NSEvent) -> Bool
        var isEnabled = true
        private var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else {
                    return event
                }
                return self.handler(event) ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}


// Recording HUD gradient top color. Kept private because only the recording
// state uses it.
private let hudRecordingGradientTop = Color(red: 0.16, green: 0.10, blue: 0.11)

struct HUDSurface<Content: View>: View {
    var isRecording = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isRecording
                                    ? [hudRecordingGradientTop.opacity(0.96), Theme.appBg.opacity(0.94)]
                                    : [Theme.surfaceRaised.opacity(0.94), Theme.appBg.opacity(0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isRecording ? 0.17 : 0.21),
                                    (isRecording ? Theme.destructive : Theme.borderStrong).opacity(isRecording ? 0.30 : 0.18),
                                    Color.black.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
    }
}

struct DragHandle: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 3.5, height: 3.5)
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 3.5, height: 3.5)
                }
            }
        }
        .frame(width: 28, height: 36)
        .background(Color.white.opacity(0.001), in: Capsule())
        .accessibilityLabel("Drag")
    }
}

struct HUDDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 2)
    }
}

struct HUDControlGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(4)
        .background(Theme.scrim, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }
}

struct HUDPrimaryButton: View {
    var title: String
    var symbolName: String
    var isDestructive: Bool
    var shortcutText: String? = nil
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .capsule, action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: symbolName)
                    .labelStyle(.titleAndIcon)

                if let shortcutText {
                    Text(shortcutText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background((isDestructive ? Theme.destructiveFg : Theme.actionPrimaryFg).opacity(0.14), in: Capsule())
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 116)
            .frame(height: 40)
            .padding(.horizontal, 14)
            .background(isDestructive ? Theme.destructive : Theme.actionPrimary, in: Capsule())
            .foregroundStyle(isDestructive ? Theme.destructiveFg : Theme.actionPrimaryFg)
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isDestructive ? 0.18 : 0.36), lineWidth: 1)
            }
            .shadow(color: (isDestructive ? Theme.destructive : Theme.actionPrimary).opacity(0.22), radius: 12, y: 5)
        }
    }
}

struct HUDPrimaryIconButton: View {
    var title: String
    var symbolName: String
    var isDestructive: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .circle, help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 42, height: 40)
                .background(isDestructive ? Theme.destructive : Theme.actionPrimary, in: Circle())
                .foregroundStyle(isDestructive ? Theme.destructiveFg : Theme.actionPrimaryFg)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isDestructive ? 0.18 : 0.36), lineWidth: 1)
                }
                .shadow(color: (isDestructive ? Theme.destructive : Theme.actionPrimary).opacity(0.22), radius: 12, y: 5)
        }
    }
}

struct HUDIconActionButton: View {
    var symbolName: String
    var title: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .circle, help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(tint.opacity(0.95))
                .background(tint.opacity(0.14), in: Circle())
                .overlay {
                    Circle()
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                }
        }
    }
}

struct HUDPermissionGroup: View {
    var action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label("Permission", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Theme.statusError.opacity(0.95))
                .padding(.leading, 10)

            StudioButton(hitTarget: .capsule, action: action) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Theme.statusError.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.statusError.opacity(0.95))
            }
        }
        .frame(height: 38)
        .padding(.trailing, 4)
        .background(Theme.statusError.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Theme.statusError.opacity(0.25), lineWidth: 1)
        }
    }
}

struct CaptureModeButton: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .capsule, action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(isActive ? Color.black.opacity(0.08) : Color.white.opacity(0.055), in: Circle())
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 118)
            .frame(height: 40)
            .padding(.horizontal, 13)
            .foregroundStyle(isActive ? Theme.actionPrimaryFg : Color.white.opacity(0.78))
            .background {
                Capsule()
                    .fill(isActive ? Theme.actionPrimary : Theme.overlayStrong)
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(isActive ? 0.18 : 0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(Capsule())
                    }
            }
            .overlay {
                Capsule()
                    .stroke(isActive ? Color.white.opacity(0.24) : Theme.borderStrong.opacity(0.68), lineWidth: 1)
            }
        }
    }
}
enum FlowTone {
    case blue
    case green
    case red
    case amber
}

struct FlowLabel: View {
    var tone: FlowTone
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: label.localizedCaseInsensitiveContains("screenshot") ? "camera.viewfinder" : "record.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dotColor)
                .frame(width: 24, height: 24)
                .background(dotColor.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(Theme.fgSubtle)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(Theme.fgMuted)
            }
        }
        .frame(width: 112, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(Theme.scrim, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }

    private var dotColor: Color {
        switch tone {
        case .blue: Theme.statusInfo
        case .green: Theme.statusSuccess
        case .red: Theme.statusError
        case .amber: Theme.statusWarning
        }
    }
}

struct CompactFlowLabel: View {
    var tone: FlowTone
    var value: String

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(tone: tone)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.fgMuted)
        }
        .frame(width: 82, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(Theme.scrim, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }
}

struct StatusDot: View {
    var tone: FlowTone

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .shadow(color: dotColor.opacity(0.65), radius: 7)
    }

    private var dotColor: Color {
        switch tone {
        case .blue:  Theme.statusInfo
        case .green: Theme.statusSuccess
        case .red:   Theme.statusError
        case .amber: Theme.statusWarning
        }
    }
}

struct SourceChip: View {
    var source: CaptureSource?
    var tone: FlowTone = .green
    var minWidth: CGFloat = 132
    var maxWidth: CGFloat = 198

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(tone: source == nil ? .amber : tone)
            Image(systemName: source?.kind == .window ? "macwindow" : source?.kind == .area ? "rectangle.dashed" : "display")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.fgMuted)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.055), in: Circle())
            Text(source?.name ?? "Choose source")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: max(48, maxWidth - 58), alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .leading)
        .frame(height: 38)
        .background(Theme.scrim.opacity(0.92), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Theme.borderStrong.opacity(0.62), lineWidth: 1)
        }
        .capsuleHitTarget()
    }
}

struct CaptureStatusChip: View {
    var message: String
    var isError: Bool
    var maxWidth: CGFloat = 130

    var body: some View {
        HStack(spacing: 6) {
            if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.statusError.opacity(0.95))
            }
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isError ? Theme.statusError.opacity(0.95) : Theme.fgMuted)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(.horizontal, 4)
        .frame(height: 38)
    }
}

struct HUDToggle: View {
    var symbolName: String
    var isActive: Bool
    var title: String
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .circle, help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(foregroundStyle)
                .background(backgroundStyle, in: Circle())
                .overlay {
                    Circle()
                        .stroke(strokeStyle, lineWidth: 1)
                }
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "On" : "Off")
    }

    private var foregroundStyle: Color {
        if isDisabled {
            return Theme.fgDisabled
        }
        return isActive ? Theme.accent.opacity(0.95) : Color.white.opacity(0.55)
    }

    private var backgroundStyle: Color {
        if isDisabled {
            return Color.white.opacity(0.035)
        }
        return isActive ? Theme.accent.opacity(0.16) : Theme.overlay
    }

    private var strokeStyle: Color {
        if isDisabled {
            return Theme.overlay
        }
        return isActive ? Theme.accent.opacity(0.35) : Theme.border
    }
}


// MARK: - Design Tokens (shadcn-aligned, dark theme)
//
// Semantic color tokens for the app. Naming follows shadcn/ui conventions
// adapted to SwiftUI (avoiding clashes with Color.primary / Color.secondary).
//
// Usage groups:
//   Surfaces        appBg / appBgMuted / surface / surfaceRaised / surfaceControl
//   Foregrounds     fg / fgMuted / fgSubtle / fgDisabled
//   Strokes         border / borderStrong / borderSubtle
//   Actions         actionPrimary(+Fg) / accent(+Fg) / destructive(+Fg)
//   Overlays        overlay / overlayStrong / scrim
//   Status          statusError / statusWarning / statusSuccess / statusInfo
//
// Prefer these over raw Color.white.opacity(N) or Color(red:...) literals.

enum Theme {
    // Surfaces
    static let appBg          = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let appBgMuted     = Color(red: 0.055, green: 0.055, blue: 0.067)
    static let surface        = Color(red: 0.075, green: 0.075, blue: 0.088)
    static let surfaceRaised  = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let surfaceControl = Color(red: 0.12, green: 0.12, blue: 0.145)

    // Foregrounds
    static let fg         = Color.white
    static let fgMuted    = Color.white.opacity(0.62)
    static let fgSubtle   = Color.white.opacity(0.40)
    static let fgDisabled = Color.white.opacity(0.25)

    // Strokes
    static let border        = Color.white.opacity(0.10)
    static let borderStrong  = Color.white.opacity(0.18)
    static let borderSubtle  = Color.white.opacity(0.06)

    // Actions
    static let actionPrimary    = Color.white
    static let actionPrimaryFg  = Color(red: 0.035, green: 0.035, blue: 0.043)

    static let accent           = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let accentFg         = Color.white

    static let destructive      = Color.red.opacity(0.86)
    static let destructiveFg    = Color.white

    // Overlays
    static let overlay        = Color.white.opacity(0.06)
    static let overlayStrong  = Color.white.opacity(0.10)
    static let scrim          = Color.black.opacity(0.20)

    // Status
    static let statusError    = Color.red
    static let statusWarning  = Color.yellow
    static let statusSuccess  = Color.green
    static let statusInfo     = Color.blue

    // Timeline palette
    static let timelineClip           = Color(red: 0.06, green: 0.34, blue: 1.0)
    static let timelineClipForeground = Color.white.opacity(0.94)
    static let timelineClipBorder     = Color(red: 0.28, green: 0.62, blue: 1.0).opacity(0.88)
    static let timelineHandle         = Color(red: 0.34, green: 0.68, blue: 1.0)
    static let timelineCamera         = Color(red: 0.02, green: 0.66, blue: 0.58)
}
