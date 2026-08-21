import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum HUDWindowMetrics {
    static let height: CGFloat = 155
    static let horizontalScreenMargin: CGFloat = 32
    static let minWidth: CGFloat = 360
    static let defaultSize = CGSize(width: 720, height: height)

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
    func studioEditorPaneChrome(bg: Color = Theme.canvasBg, clipContent: Bool = true) -> some View {
        background(bg)
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
        HSplitView {
            primary
                .frame(minWidth: minPrimarySize, maxWidth: .infinity, maxHeight: .infinity)

            secondary
                .frame(
                    minWidth: minSecondarySize,
                    idealWidth: StudioSplitPaneSizing.normalizedSecondarySize(
                        secondarySize,
                        minimum: minSecondarySize,
                        maximum: maxSecondarySize
                    ),
                    maxWidth: maxSecondarySize,
                    maxHeight: .infinity
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: StudioSecondaryPaneWidthPreferenceKey.self,
                            value: proxy.size.width
                        )
                    }
                }
        }
        .accessibilityElement(children: .contain)
        .onAppear(perform: normalizeStoredSecondarySize)
        .onPreferenceChange(StudioSecondaryPaneWidthPreferenceKey.self) { measuredWidth in
            let normalized = StudioSplitPaneSizing.normalizedSecondarySize(
                measuredWidth,
                minimum: minSecondarySize,
                maximum: maxSecondarySize
            )
            if abs(secondarySize - normalized) > 0.5 {
                secondarySize = normalized
            }
        }
        .onChange(of: secondarySize) { _, newValue in
            let normalized = StudioSplitPaneSizing.normalizedSecondarySize(
                newValue,
                minimum: minSecondarySize,
                maximum: maxSecondarySize
            )
            if secondarySize != normalized {
                secondarySize = normalized
            }
        }
    }

    private func normalizeStoredSecondarySize() {
        secondarySize = StudioSplitPaneSizing.normalizedSecondarySize(
            secondarySize,
            minimum: minSecondarySize,
            maximum: maxSecondarySize
        )
    }
}

private struct StudioSecondaryPaneWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let candidate = nextValue()
        if candidate.isFinite, candidate > 0 {
            value = candidate
        }
    }
}

enum StudioSplitPaneSizing {
    static func normalizedSecondarySize(
        _ requestedSize: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        let safeMinimum = minimum.isFinite ? max(0, minimum) : 0
        let safeMaximum = maximum.isFinite ? max(safeMinimum, maximum) : safeMinimum
        guard requestedSize.isFinite else { return safeMinimum }
        return min(max(requestedSize, safeMinimum), safeMaximum)
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

    func makeNSView(context: Context) -> StudioKeyMonitorAttachmentView {
        let view = StudioKeyMonitorAttachmentView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.handler = handler
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: StudioKeyMonitorAttachmentView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.handler = handler
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
    }

    static func dismantleNSView(_ nsView: StudioKeyMonitorAttachmentView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        weak var view: StudioKeyMonitorAttachmentView?
        var handler: (NSEvent) -> Bool
        var isEnabled = true
        private var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let view = self.view,
                      let windowScope = view.windowScope.snapshot(),
                      StudioKeyEventScope.shouldHandle(
                          isEnabled: self.isEnabled,
                          ownerWindowNumber: windowScope.windowNumber,
                          eventWindowNumber: event.windowNumber,
                          ownerWindowIsKey: windowScope.isKey
                      ) else {
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

final class StudioKeyMonitorAttachmentView: NSView {
    override var isFlipped: Bool { true }

    nonisolated let windowScope = StudioKeyWindowScopeCache()
    private weak var observedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()

        guard let window else {
            windowScope.update(windowNumber: nil, isKey: false)
            return
        }

        observedWindow = window
        windowScope.update(windowNumber: window.windowNumber, isKey: window.isKeyWindow)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        windowScope.updateIsKey(true)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        windowScope.updateIsKey(false)
    }

    private func stopObservingWindow() {
        guard let observedWindow else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: observedWindow
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResignKeyNotification,
            object: observedWindow
        )
        self.observedWindow = nil
    }
}

struct StudioKeyWindowScope: Sendable {
    var windowNumber: Int
    var isKey: Bool
}

final class StudioKeyWindowScopeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var windowNumber: Int?
    private var isKey = false

    func update(windowNumber: Int?, isKey: Bool) {
        lock.lock()
        self.windowNumber = windowNumber
        self.isKey = isKey
        lock.unlock()
    }

    func updateIsKey(_ isKey: Bool) {
        lock.lock()
        self.isKey = isKey
        lock.unlock()
    }

    func snapshot() -> StudioKeyWindowScope? {
        lock.lock()
        defer { lock.unlock() }
        guard let windowNumber else { return nil }
        return StudioKeyWindowScope(windowNumber: windowNumber, isKey: isKey)
    }
}

enum StudioKeyEventScope {
    static func shouldHandle(
        isEnabled: Bool,
        ownerWindowNumber: Int?,
        eventWindowNumber: Int?,
        ownerWindowIsKey: Bool
    ) -> Bool {
        guard isEnabled,
              ownerWindowIsKey,
              let ownerWindowNumber,
              let eventWindowNumber else {
            return false
        }
        return ownerWindowNumber == eventWindowNumber
    }

    @MainActor
    static func isTextInputActive(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}


struct HUDSurface<Content: View>: View {
    var isRecording = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.layoutDirection, .leftToRight)
            .flipsForRightToLeftLayoutDirection(false)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.surfaceRaised.opacity(0.94), Theme.appBg.opacity(0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.21), Theme.borderStrong.opacity(0.18), Color.black.opacity(0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
            .shadow(color: Color.black.opacity(0.28), radius: 12, y: 6)
            .environment(\.layoutDirection, .leftToRight)
            .flipsForRightToLeftLayoutDirection(false)
    }
}

struct DragHandle: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Rectangle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 3.5, height: 3.5)
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 3.5, height: 3.5)
                }
            }
        }
        .frame(width: 28, height: 36)
        .background(Color.white.opacity(0.001), in: Rectangle())
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
    }
}

struct HUDPrimaryButton: View {
    var title: String
    var symbolName: String
    var isDestructive: Bool
    var shortcutText: String? = nil
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), action: action) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let shortcutText {
                    Text(shortcutText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background((isDestructive ? Theme.destructiveFg : Theme.actionPrimaryFg).opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: Theme.btnHeightLg)
            .padding(.horizontal, 14)
            .background(isDestructive ? Theme.destructive : Theme.actionPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .foregroundStyle(isDestructive ? Theme.destructiveFg : Theme.actionPrimaryFg)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Color.white.opacity(isDestructive ? 0.18 : 0.36), lineWidth: 1)
            }
            .shadow(color: (isDestructive ? Theme.destructive : Theme.actionPrimary).opacity(0.24), radius: 8, y: 2)
        }
        .layoutPriority(10)
    }
}

struct HUDPrimaryIconButton: View {
    var title: String
    var symbolName: String
    var isDestructive: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: Theme.btnHeightLg, height: Theme.btnHeightLg)
                .background(isDestructive ? Theme.destructive : Theme.actionPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                .foregroundStyle(isDestructive ? Theme.destructiveFg : Theme.actionPrimaryFg)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                        .stroke(Color.white.opacity(isDestructive ? 0.18 : 0.36), lineWidth: 1)
                }
                .shadow(color: (isDestructive ? Theme.destructive : Theme.actionPrimary).opacity(0.24), radius: 8, y: 2)
        }
    }
}

struct HUDIconActionButton: View {
    var symbolName: String
    var title: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: Theme.btnHeightLg, height: Theme.btnHeightLg)
                .foregroundStyle(tint.opacity(0.95))
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
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

            StudioButton(hitTarget: .rounded(Theme.radiusSm), action: action) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.statusError.opacity(0.18), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                    .foregroundStyle(Theme.statusError.opacity(0.95))
            }
        }
        .frame(height: Theme.btnHeightLg)
        .padding(.trailing, 4)
        .background(Theme.statusError.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(Theme.statusError.opacity(0.25), lineWidth: 1)
        }
    }
}

struct HUDModeSwitcher: View {
    @Binding var mode: CaptureMode
    var isDisabled: Bool
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 3) {
            modeButton(
                mode: .recording,
                symbolName: "video.fill",
                help: "Record Video (⌘R)"
            )
            modeButton(
                mode: .screenshot,
                symbolName: "camera.fill",
                help: "Capture Screenshot (⌘S)"
            )
        }
        .padding(3)
        .background(Theme.scrim, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }

    private func modeButton(mode targetMode: CaptureMode, symbolName: String, help: String) -> some View {
        let isSelected = mode == targetMode
        return StudioButton(hitTarget: .rounded(Theme.radiusSm), help: help) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                mode = targetMode
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                        .fill(Theme.accent)
                        .matchedGeometryEffect(id: "modeIndicator", in: animation)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                                .stroke(Theme.accent.opacity(0.8), lineWidth: 1)
                        }
                        .shadow(color: Theme.accent.opacity(0.35), radius: 5, y: 1)
                }

                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white : Theme.fgMuted)
            }
            .frame(width: 30, height: 30)
        }
        .disabled(isDisabled)
    }
}

struct CaptureModeButton: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(isActive ? Color.black.opacity(0.08) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 112)
            .frame(height: Theme.btnHeightLg)
            .padding(.horizontal, 12)
            .foregroundStyle(isActive ? Theme.actionPrimaryFg : Color.white.opacity(0.78))
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(isActive ? Theme.actionPrimary : Theme.overlayStrong)
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(isActive ? 0.18 : 0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
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
                .background(dotColor.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
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
        .frame(height: Theme.btnHeightLg)
        .background(Theme.scrim, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
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
        .frame(height: Theme.btnHeightLg)
        .background(Theme.scrim, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }
}

struct StatusDot: View {
    var tone: FlowTone

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
            .shadow(color: dotColor.opacity(0.65), radius: 4)
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
    var minWidth: CGFloat = 110
    var maxWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(tone: source == nil ? .amber : tone)
            Image(systemName: source?.kind == .window ? "macwindow" : source?.kind == .area ? "rectangle.dashed" : "display")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.fg)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
            Text(source?.name ?? "Source")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: max(40, maxWidth - 60), alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.fgSubtle)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .leading)
        .frame(height: Theme.btnHeightLg)
        .background(Theme.scrim.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(Theme.borderStrong.opacity(0.62), lineWidth: 1)
        }
        .roundedHitTarget(Theme.radiusMd)
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
        .frame(height: Theme.btnHeightLg)
    }
}

struct HUDToggle: View {
    var symbolName: String
    var isActive: Bool
    var title: String
    var isDisabled = false
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusSm), help: title, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(foregroundStyle)
                .background(
                    isActive
                        ? Theme.accent.opacity(0.18)
                        : (isHovering ? Color.white.opacity(0.08) : Color.clear),
                    in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                )
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            .stroke(Theme.accent.opacity(0.38), lineWidth: 1)
                    }
                }
        }
        .disabled(isDisabled)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "On" : "Off")
    }

    private var foregroundStyle: Color {
        if isDisabled {
            return Theme.fgDisabled
        }
        return isActive ? Theme.accent : Color.white.opacity(0.60)
    }
}


// MARK: - Design Tokens (shadcn-aligned semantic palette)
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
//   Timeline        timelineClip / timelineClipForeground / timelineClipBorder / timelineHandle / timelineCamera
//
// Prefer these over raw Color.white.opacity(N) or Color(red:...) literals.

enum Theme {
    // Corner Radii (Linear & Shadcn standard)
    static let radiusSm: CGFloat   = 5
    static let radiusMd: CGFloat   = 8
    static let radiusLg: CGFloat   = 10
    static let radiusXl: CGFloat   = 14
    static let radiusPill: CGFloat = 999

    // Spacing
    static let space1: CGFloat  = 2
    static let space2: CGFloat  = 4
    static let space3: CGFloat  = 8
    static let space4: CGFloat  = 12
    static let space5: CGFloat  = 16
    static let space6: CGFloat  = 20
    static let space8: CGFloat  = 24
    static let space10: CGFloat = 32

    // Control Heights
    static let btnHeightSm: CGFloat = 28
    static let btnHeightMd: CGFloat = 36
    static let btnHeightLg: CGFloat = 42

    // Icon Sizes
    static let iconSm: CGFloat = 12
    static let iconMd: CGFloat = 14
    static let iconLg: CGFloat = 18

    // Butter-Smooth Motion Animations
    static let springFast: Animation   = .spring(response: 0.22, dampingFraction: 0.84)
    static let springSmooth: Animation = .spring(response: 0.32, dampingFraction: 0.80)
    static let springBouncy: Animation = .spring(response: 0.38, dampingFraction: 0.74)

    // Surfaces — Harmonious Multi-Tier Neutral Greys
    static let appBg          = Color(red: 0.040, green: 0.040, blue: 0.048) // Canvas stage grey
    static let canvasBg       = Color(red: 0.040, green: 0.040, blue: 0.048) // Canvas preview grey
    static let navbarBg       = Color(red: 0.086, green: 0.086, blue: 0.098) // Top Navbar grey
    static let sidebarBg      = Color(red: 0.068, green: 0.068, blue: 0.078) // Right Inspector panel grey
    static let railBg         = Color(red: 0.056, green: 0.056, blue: 0.065) // Vertical icon rail grey
    static let timelineBg     = Color(red: 0.062, green: 0.062, blue: 0.072) // Bottom Timeline dock grey
    static let appBgMuted     = Color(red: 0.055, green: 0.055, blue: 0.067)
    static let surface        = Color(red: 0.086, green: 0.086, blue: 0.098)
    static let surfaceRaised  = Color(red: 0.105, green: 0.105, blue: 0.122)
    static let surfaceControl = Color(red: 0.125, green: 0.125, blue: 0.145)

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
