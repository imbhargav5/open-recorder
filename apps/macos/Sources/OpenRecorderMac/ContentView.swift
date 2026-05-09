import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppWindowRole {
    case hud
    case sourceSelector
    case areaSelector
    case studio
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var measuredHUDSize = HUDWindowMetrics.defaultSize
    var role: AppWindowRole = .studio
    var editorSession: EditorSession?

    var body: some View {
        Group {
            switch role {
            case .hud:
                hudWindowContent
            case .sourceSelector:
                SourceSelectorWindowView()
                    .frame(width: SourceSelectorWindowMetrics.width)
                    .background(WindowConfigurator(role: .sourceSelector))
            case .areaSelector:
                AreaSelectionWindowView()
                    .background(WindowConfigurator(role: .areaSelector, isPresented: model.isAreaSelectionActive))
            case .studio:
                StudioWindowView(editorSession: editorSession)
                    .background(WindowConfigurator(role: .studio))
            }
        }
        .overlay(WindowCommandBridge().allowsHitTesting(false))
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            model.openProjectFile(at: url)
        }
    }

    @ViewBuilder
    private var hudWindowContent: some View {
        let preferredSize = preferredHUDSize

        ZStack {
            HUDOverlayWindowView()
                .fixedSize(horizontal: true, vertical: false)
                .readSize { size in
                    updateMeasuredHUDSize(size)
                }
                .hidden()
                .allowsHitTesting(false)

            HUDOverlayWindowView()
                .frame(maxWidth: preferredSize.width, maxHeight: preferredSize.height)
        }
        .frame(width: preferredSize.width, height: preferredSize.height)
        .background(WindowConfigurator(role: .hud, preferredSize: preferredSize))
    }

    private var preferredHUDSize: CGSize {
        HUDWindowMetrics.clampedSize(for: measuredHUDSize, screen: NSScreen.main)
    }

    private func updateMeasuredHUDSize(_ size: CGSize) {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size != measuredHUDSize else {
            return
        }

        measuredHUDSize = size
    }
}

struct SettingsView: View {
    var body: some View {
        SettingsStudioView()
    }
}

enum HUDWindowMetrics {
    static let height: CGFloat = 155
    static let horizontalScreenMargin: CGFloat = 32
    static let minWidth: CGFloat = 360
    static let defaultSize = CGSize(width: 780, height: height)

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

private struct SizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        guard next != .zero else { return }
        value = next
    }
}

private extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

private enum NativeWindowRole {
    case hud
    case sourceSelector
    case areaSelector
    case studio
}

private struct WindowConfigurator: NSViewRepresentable {
    var role: NativeWindowRole
    var preferredSize: CGSize?
    var isPresented = true

    func makeNSView(context: Context) -> WindowConfigurationView {
        let view = WindowConfigurationView()
        view.role = role
        view.preferredSize = preferredSize
        view.isPresented = isPresented
        return view
    }

    func updateNSView(_ nsView: WindowConfigurationView, context: Context) {
        nsView.role = role
        nsView.preferredSize = preferredSize
        nsView.isPresented = isPresented
        nsView.configureWindow()
    }
}

private final class WindowConfigurationView: NSView {
    var role: NativeWindowRole = .studio {
        didSet {
            if role != oldValue {
                configuredRole = nil
            }
        }
    }
    var preferredSize: CGSize? {
        didSet {
            if preferredSize != oldValue {
                configuredRole = nil
            }
        }
    }
    var isPresented = true

    private var configuredRole: NativeWindowRole?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        if role == .areaSelector {
            guard isPresented else {
                window.close()
                return
            }
            configuredRole = role
            configureAreaSelector(window)
            return
        }
        guard configuredRole != role else { return }
        configuredRole = role

        switch role {
        case .hud:
            configureHUD(window)
        case .sourceSelector:
            configureSourceSelector(window)
        case .areaSelector:
            configureAreaSelector(window)
        case .studio:
            configureStudio(window)
        }
    }

    private func configureHUD(_ window: NSWindow) {
        let size = HUDWindowMetrics.clampedSize(
            for: preferredSize ?? HUDWindowMetrics.defaultSize,
            screen: window.screen ?? NSScreen.main
        )
        window.title = "Open Recorder"
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { button in
            window.standardWindowButton(button)?.isHidden = true
        }
        positionBottomCenter(window, contentSize: size)
    }

    private func configureSourceSelector(_ window: NSWindow) {
        window.title = "Choose Source"
        window.setContentSize(NSSize(width: SourceSelectorWindowMetrics.width, height: SourceSelectorWindowMetrics.compactHeight))
        window.minSize = NSSize(width: SourceSelectorWindowMetrics.minWidth, height: SourceSelectorWindowMetrics.minHeight)
        window.maxSize = NSSize(width: 1400, height: SourceSelectorWindowMetrics.maxHeight)
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.070, alpha: 1)
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.center()
    }

    private func configureAreaSelector(_ window: NSWindow) {
        let screenFrame = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 900, height: 600)
        window.title = "Select Area"
        window.setFrame(screenFrame, display: true)
        window.minSize = screenFrame.size
        window.maxSize = screenFrame.size
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .fullSizeContentView]
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { button in
            window.standardWindowButton(button)?.isHidden = true
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureStudio(_ window: NSWindow) {
        window.title = "Open Recorder Editor"
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize = NSSize(width: 800, height: 600)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.070, alpha: 1)
        window.hasShadow = true
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.center()
    }

    private func positionBottomCenter(_ window: NSWindow, contentSize: NSSize) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - contentSize.width / 2,
            y: visibleFrame.minY + 26
        )
        window.setFrame(NSRect(origin: origin, size: contentSize), display: true)
    }
}

enum SourceSelectorWindowMetrics {
    static let width: CGFloat = 660
    static let minWidth: CGFloat = 520
    static let compactHeight: CGFloat = 454
    static let minHeight: CGFloat = 360
    static let maxHeight: CGFloat = 1200
    static let outerPadding: CGFloat = 16
}

private struct SourceSelectorCardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = SourceSelectorWindowMetrics.compactHeight - (SourceSelectorWindowMetrics.outerPadding * 2)

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SourceSelectorWindowSizer: NSViewRepresentable {
    var size: CGSize

    func makeNSView(context: Context) -> SourceSelectorWindowSizingView {
        let view = SourceSelectorWindowSizingView()
        view.preferredContentSize = size
        return view
    }

    func updateNSView(_ nsView: SourceSelectorWindowSizingView, context: Context) {
        nsView.preferredContentSize = size
        nsView.applyPreferredContentSize()
    }
}

private final class SourceSelectorWindowSizingView: NSView {
    var preferredContentSize: CGSize = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPreferredContentSize()
    }

    func applyPreferredContentSize() {
        guard let window, preferredContentSize.width > 0, preferredContentSize.height > 0 else { return }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }

            let targetContentSize = NSSize(
                width: self.preferredContentSize.width,
                height: min(max(self.preferredContentSize.height, SourceSelectorWindowMetrics.minHeight), SourceSelectorWindowMetrics.maxHeight)
            )
            let currentContentSize = window.contentView?.bounds.size ?? window.contentRect(forFrameRect: window.frame).size
            guard abs(currentContentSize.width - targetContentSize.width) > 0.5 ||
                    abs(currentContentSize.height - targetContentSize.height) > 0.5 else {
                return
            }

            let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
            var nextFrame = window.frame
            nextFrame.origin.x += (nextFrame.width - targetFrameSize.width) / 2
            nextFrame.origin.y += (nextFrame.height - targetFrameSize.height) / 2
            nextFrame.size = targetFrameSize

            if let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                nextFrame.origin.x = min(max(nextFrame.origin.x, visibleFrame.minX), visibleFrame.maxX - nextFrame.width)
                nextFrame.origin.y = min(max(nextFrame.origin.y, visibleFrame.minY), visibleFrame.maxY - nextFrame.height)
            }

            window.setFrame(nextFrame, display: true)
        }
    }
}

private struct WindowCommandBridge: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                handle(model.windowCommand)
            }
            .onChange(of: model.windowCommand?.id) { _, _ in
                handle(model.windowCommand)
            }
    }

    private func handle(_ command: NativeWindowCommand?) {
        guard let command = model.consumeWindowCommand(command) else { return }

        switch command.action {
        case .showHUD:
            openWindow(id: "hud")
        case .showSourceSelector:
            openWindow(id: "source-selector")
        case .showAreaSelector:
            openWindow(id: "area-selector")
        case .showStudio:
            if let editorSession = command.editorSession {
                openWindow(id: "editor", value: editorSession)
            } else {
                openWindow(id: "studio")
            }
        case .closeSourceSelector:
            dismissWindow(id: "source-selector")
        case .closeAreaSelector:
            dismissWindow(id: "area-selector")
        }
    }
}

private struct HUDOverlayWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            Color.clear

            if model.captureFlow == .choice {
                HUDSurface {
                    HStack(spacing: 12) {
                        DragHandle()

                        CaptureModeButton(
                            title: "Screenshot",
                            symbolName: "camera",
                            isActive: false
                        ) {
                            model.beginCapture(.screenshot)
                            openWindow(id: "source-selector")
                        }

                        CaptureModeButton(
                            title: "Record Video",
                            symbolName: "video",
                            isActive: false
                        ) {
                            model.beginCapture(.recording)
                            openWindow(id: "source-selector")
                        }
                    }
                }
            } else {
                CaptureHUD(sourceTab: .constant(model.captureMode == .screenshot ? .screens : .screens))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
    }
}

private struct SourceSelectorWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var sourceTab: SourceSelectorTab = .screens
    @State private var preferredHeight: CGFloat = SourceSelectorWindowMetrics.compactHeight

    private var visibleTabs: [SourceSelectorTab] {
        SourceSelectorTab.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            SourceSelectorCard(
                sourceTab: $sourceTab,
                visibleTabs: visibleTabs,
                onCancel: {
                    model.cancelCapture()
                    dismissWindow(id: "source-selector")
                },
                onShare: {
                    if let selectedSource = model.selectedSource {
                        model.selectSource(selectedSource)
                    }
                    dismissWindow(id: "source-selector")
                },
                onDrawArea: {
                    model.selectInteractiveAreaSource()
                    dismissWindow(id: "source-selector")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        model.requestInteractiveAreaSelection()
                    }
                }
            )
            .padding(16)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SourceSelectorCardHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
        }
        .background(SourceSelectorWindowSizer(size: CGSize(width: SourceSelectorWindowMetrics.width, height: preferredHeight)))
        .background(Color.studioBackground.ignoresSafeArea())
        .onPreferenceChange(SourceSelectorCardHeightPreferenceKey.self) { cardHeight in
            let nextHeight = ceil(cardHeight + (SourceSelectorWindowMetrics.outerPadding * 2))
            guard abs(preferredHeight - nextHeight) > 0.5 else { return }
            preferredHeight = nextHeight
        }
        .onAppear {
            model.reloadSources()
        }
    }
}

private struct StudioWindowView: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?

    var body: some View {
        StudioShell(editorSession: editorSession)
            .onAppear {
                if model.selectedSection == .capture {
                    model.selectedSection = .editor
                }
            }
    }
}

private struct AreaSelectionWindowView: View {
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
            .contentShape(Rectangle())
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

private struct AreaSelectionFocusKey: FocusedValueKey {
    typealias Value = Bool
}

private extension FocusedValues {
    var areaSelectionIsFocused: Bool? {
        get { self[AreaSelectionFocusKey.self] }
        set { self[AreaSelectionFocusKey.self] = newValue }
    }
}

private struct StudioShell: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?
    @State private var sidebarExpanded = true

    var body: some View {
        HStack(spacing: 0) {
            StudioSidebar(isExpanded: sidebarExpanded)

            VStack(spacing: 0) {
                StudioTitleBar(sidebarExpanded: $sidebarExpanded, editorSession: editorSession)
                detailView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.studioBackground)
        .animation(.easeInOut(duration: 0.18), value: sidebarExpanded)
        .onAppear {
            if model.selectedSection == .capture {
                model.selectedSection = .editor
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selectedSection {
        case .capture:
            EditorStudioView(editorSession: editorSession)
        case .projects:
            ProjectsStudioView()
        case .editor:
            EditorStudioView(editorSession: editorSession)
        case .settings:
            SettingsStudioView()
        }
    }
}

private struct StudioSidebar: View {
    @EnvironmentObject private var model: AppModel
    var isExpanded: Bool

    private let items: [AppSection] = [.editor, .projects]
    private var isScreenshotEditor: Bool {
        model.currentScreenshotURL != nil && model.currentVideoURL == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: isExpanded ? 10 : 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brand.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.brand.opacity(0.24), lineWidth: 1)
                        }
                    Image(systemName: isScreenshotEditor ? "photo.fill" : "video.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brand)
                }
                .frame(width: 36, height: 36)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Recorder")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(isScreenshotEditor ? "Image Studio" : "Studio")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .padding(.horizontal, isExpanded ? 12 : 10)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.studioBorder)

            VStack(spacing: 4) {
                ForEach(items) { section in
                    SidebarButton(
                        title: section.title,
                        symbolName: sidebarSymbol(for: section),
                        isActive: model.selectedSection == section,
                        isExpanded: isExpanded
                    ) {
                        model.selectedSection = section
                    }
                }
            }
            .padding(8)

            Spacer()

            Divider()
                .overlay(Color.studioBorder)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            SidebarButton(title: "Help", symbolName: "questionmark.circle", isActive: false, isExpanded: isExpanded) {
                model.statusMessage = "Keyboard shortcuts are coming to the native editor."
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)

            if isExpanded {
                StatusFooter()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: isExpanded ? 224 : 56)
        .background(Color.studioPanel.opacity(0.95))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(width: 1)
        }
    }

    private func sidebarSymbol(for section: AppSection) -> String {
        switch section {
        case .editor: isScreenshotEditor ? "photo" : "video"
        case .projects: "folder.badge.gearshape"
        case .capture: "record.circle"
        case .settings: "gearshape"
        }
    }
}

private struct SidebarButton: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    var isExpanded = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isExpanded ? 9 : 0) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18, height: 18)
                if isExpanded {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isExpanded ? 10 : 0)
            .foregroundStyle(isActive ? Color.brand : Color.secondary)
            .background(isActive ? Color.brand.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct StatusFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.service.isAvailable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .shadow(color: model.service.isAvailable ? Color.green.opacity(0.55) : Color.orange.opacity(0.55), radius: 5)
            Text(model.statusMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StudioTitleBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var sidebarExpanded: Bool
    var editorSession: EditorSession?

    var body: some View {
        ZStack {
            HStack {
                Button {
                    sidebarExpanded.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                if model.selectedSection == .editor, let videoURL {
                    Button {
                        model.exportCurrentRecording(videoURL)
                    } label: {
                        Label("Export Video", systemImage: "arrow.down.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                } else if model.selectedSection == .editor, screenshotURL != nil {
                    Button {
                        model.requestScreenshotExport()
                    } label: {
                        Label("Export PNG", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
                if model.selectedSection == .editor, let editorBadge {
                    Text(editorBadge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(height: 48)
        .background(Color.studioPanel.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)
        }
    }

    private var title: String {
        switch model.selectedSection {
        case .capture:
            "Capture"
        case .projects:
            "Projects"
        case .settings:
            "Settings"
        case .editor:
            editorSession?.title ??
                model.currentVideoURL?.lastPathComponent ??
                    model.currentScreenshotURL?.lastPathComponent ??
                    "Open Recorder Editor"
        }
    }

    private var editorBadge: String? {
        if let editorSession {
            return editorSession.kind.badge
        }
        if model.currentVideoURL != nil {
            return EditorMediaKind.video.badge
        }
        if model.currentScreenshotURL != nil {
            return EditorMediaKind.screenshot.badge
        }
        return nil
    }

    private var videoURL: URL? {
        if let editorSession {
            return editorSession.kind == .video ? editorSession.url : nil
        }
        return model.currentVideoURL
    }

    private var screenshotURL: URL? {
        if let editorSession {
            return editorSession.kind == .screenshot ? editorSession.url : nil
        }
        return model.currentScreenshotURL
    }
}

private enum SourceSelectorTab: String, CaseIterable, Identifiable {
    case screens
    case windows
    case area

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screens: "Screens"
        case .windows: "Windows"
        case .area: "Area"
        }
    }

    var symbolName: String {
        switch self {
        case .screens: "display"
        case .windows: "macwindow"
        case .area: "rectangle.dashed"
        }
    }
}

private struct CaptureStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sourceTab: SourceSelectorTab = .screens

    private var visibleTabs: [SourceSelectorTab] {
        SourceSelectorTab.allCases
    }

    var body: some View {
        ZStack {
            Color.studioBackground

            if model.captureFlow == .choice {
                VStack {
                    Spacer()
                    CaptureChoiceHUD(sourceTab: $sourceTab)
                        .padding(.bottom, 56)
                }
            } else {
                VStack(spacing: 18) {
                    Spacer(minLength: 10)
                    SourceSelectorCard(
                        sourceTab: $sourceTab,
                        visibleTabs: visibleTabs,
                        onDrawArea: {
                            model.requestInteractiveAreaSelection()
                        }
                    )
                        .frame(maxWidth: 860)
                    CaptureHUD(sourceTab: $sourceTab)
                        .padding(.bottom, 12)
                }
                .padding(16)
                .background(Color.studioMutedBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CaptureChoiceHUD: View {
    @EnvironmentObject private var model: AppModel
    @Binding var sourceTab: SourceSelectorTab

    var body: some View {
        HUDSurface {
            HStack(spacing: 12) {
                DragHandle()

                CaptureModeButton(
                    title: "Screenshot",
                    symbolName: "camera",
                    isActive: false
                ) {
                    model.beginCapture(.screenshot)
                    sourceTab = .screens
                }

                CaptureModeButton(
                    title: "Record Video",
                    symbolName: "video",
                    isActive: false
                ) {
                    model.beginCapture(.recording)
                }
            }
        }
    }
}

private struct SourceSelectorCard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var sourceTab: SourceSelectorTab
    var visibleTabs: [SourceSelectorTab]
    var onCancel: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onDrawArea: (() -> Void)? = nil

    private var sources: [CaptureSource] {
        switch sourceTab {
        case .screens:
            model.capture.sources.filter { $0.kind == .display }
        case .windows:
            model.capture.sources.filter { $0.kind == .window }
        case .area:
            model.capture.sources.filter { $0.kind == .area }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose what to share")
                        .font(.system(size: 18, weight: .semibold))
                    Text(selectorDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.capture.sources.filter { $0.kind != .area }.count) sources")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.studioBorder)
                    }
            }
            .padding(16)

            VStack(spacing: 14) {
                SourceTabs(sourceTab: $sourceTab, visibleTabs: visibleTabs)

                if sources.isEmpty {
                    SourceEmptyState(sourceTab: sourceTab, onDrawArea: onDrawArea)
                } else {
                    SourceGrid(sources: sources, sourceTab: sourceTab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            HStack {
                Button {
                    onCancel?()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(height: 34)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    model.reloadSources()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(height: 34)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onShare?()
                } label: {
                    Text("Share Source")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(canShareSource ? Color.brand : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(canShareSource ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canShareSource || onShare == nil)
            }
            .padding(16)
        }
        .background(Color.studioPanel.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 26, y: 18)
    }

    private var selectorDescription: String {
        if model.captureMode == .screenshot {
            "Pick a screen, app window, or drawn area for this screenshot."
        } else {
            "Pick a screen, app window, or drawn area for the next recording."
        }
    }

    private var canShareSource: Bool {
        guard let selectedSource = model.selectedSource else {
            return false
        }
        return sources.contains { $0.id == selectedSource.id }
    }
}

private struct SourceTabs: View {
    @Binding var sourceTab: SourceSelectorTab
    var visibleTabs: [SourceSelectorTab]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { tab in
                Button {
                    sourceTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbolName)
                        Text(tab.title)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .foregroundStyle(sourceTab == tab ? Color.primary : Color.secondary)
                    .background(sourceTab == tab ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.studioControl, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct SourceGrid: View {
    @EnvironmentObject private var model: AppModel
    var sources: [CaptureSource]
    var sourceTab: SourceSelectorTab

    private var columns: [GridItem] {
        let count = sourceTab == .windows ? 3 : min(max(sources.count, 1), 3)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        if sourceTab == .windows {
            ScrollView(.vertical) {
                grid
                    .padding(.trailing, 2)
            }
            .frame(maxHeight: 356)
            .scrollClipDisabled(false)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            grid
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(sources) { source in
                SourceTile(
                    source: source,
                    isSelected: model.selectedSource?.id == source.id,
                    isCompact: sourceTab == .windows
                ) {
                    model.selectSource(source)
                }
            }
        }
        .clipped()
    }
}

private struct SourceTile: View {
    var source: CaptureSource
    var isSelected: Bool
    var isCompact: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if isCompact {
                squareContent
            } else {
                standardContent
            }
        }
        .buttonStyle(.plain)
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            SourceThumbnailPreview(
                source: source,
                isSelected: isSelected,
                isCompact: isCompact
            )
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)

            labels
        }
        .padding(8)
        .background(Color.studioCard.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.brand : Color.studioBorder, lineWidth: isSelected ? 2 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var squareContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            SourceThumbnailPreview(
                source: source,
                isSelected: isSelected,
                isCompact: isCompact
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            labels
        }
        .padding(4)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioCard.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.brand : Color.studioBorder, lineWidth: isSelected ? 2 : 1)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(source.name)
                    .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Text("Selected")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            Text(source.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewAspectRatio: CGFloat {
        source.kind == .window ? 1.6 : 16.0 / 9.0
    }
}

private struct SourceThumbnailPreview: View {
    var source: CaptureSource
    var isSelected: Bool
    var isCompact: Bool

    private var aspectRatio: CGFloat {
        source.kind == .window ? 1.6 : 16.0 / 9.0
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let previewSize = fittedPreviewSize(in: size)

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.045))

                if let thumbnail = source.thumbnailData,
                   let image = NSImage(data: thumbnail) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: previewSize.width, height: previewSize.height)
                        .clipped()
                } else {
                    thumbnailPlaceholder
                        .frame(width: previewSize.width, height: previewSize.height)
                }

                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Color.brand, in: Circle())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .frame(width: size.width, height: size.height, alignment: .center)
        }
        .clipped()
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Image(systemName: source.kind == .window ? "macwindow" : source.kind == .area ? "rectangle.dashed" : "display")
                .font(.system(size: isCompact ? 18 : 24, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func fittedPreviewSize(in size: CGSize) -> CGSize {
        let maxWidth = max(size.width, 1)
        let maxHeight = max(size.height, 1)
        let heightFromWidth = maxWidth / aspectRatio

        if heightFromWidth <= maxHeight {
            return CGSize(width: maxWidth, height: heightFromWidth)
        }

        return CGSize(width: maxHeight * aspectRatio, height: maxHeight)
    }
}

private struct SourceEmptyState: View {
    var sourceTab: SourceSelectorTab
    var onDrawArea: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: sourceTab.symbolName)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            Text(sourceTab == .area ? "Draw a capture area" : "No sources available")
                .font(.system(size: 15, weight: .semibold))
            Text(sourceTab == .area ? "Select the part of the screen you want to capture." : "Try a different tab or make sure the source is visible.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if sourceTab == .area {
                Button {
                    onDrawArea?()
                } label: {
                    Label("Draw Selection", systemImage: "rectangle.dashed")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(height: 34)
                        .padding(.horizontal, 12)
                        .background(Color.brand, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}

private struct CaptureHUD: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Binding var sourceTab: SourceSelectorTab

    var body: some View {
        HUDSurface(isRecording: model.capture.isRecording) {
            if model.captureMode == .recording {
                recordingControls
            } else {
                screenshotControls
            }
        }
    }

    private var recordingControls: some View {
        ViewThatFits(in: .horizontal) {
            fullRecordingControls
            compactRecordingControls
            narrowRecordingControls
        }
    }

    private var fullRecordingControls: some View {
        HStack(spacing: 8) {
            sharedLeadingControls

            FlowLabel(
                tone: model.capture.isRecording ? .red : .blue,
                label: model.capture.isRecording ? "Recording" : "Ready",
                value: model.capture.isRecording ? recordingPhaseLabel : "Video"
            )

            sourcePicker()
                .layoutPriority(2)

            permissionControls

            HUDDivider()

            HUDControlGroup {
                HUDToggle(symbolName: model.includeSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill", isActive: model.includeSystemAudio, title: "System Audio") {
                    model.includeSystemAudio.toggle()
                }
                HUDToggle(symbolName: model.includeMicrophone ? "mic.fill" : "mic.slash.fill", isActive: model.includeMicrophone, title: "Microphone") {
                    model.includeMicrophone.toggle()
                }
                deviceMenu(
                    symbolName: "mic.badge.plus",
                    title: "Microphone Device",
                    devices: model.microphoneDevices,
                    selectedDeviceID: $model.selectedMicrophoneDeviceID
                )
                HUDToggle(symbolName: model.includeCamera ? "video.fill" : "video.slash.fill", isActive: model.includeCamera, title: "Facecam") {
                    model.includeCamera.toggle()
                }
                deviceMenu(
                    symbolName: "video.badge.plus",
                    title: "Camera Device",
                    devices: model.cameraDevices,
                    selectedDeviceID: $model.selectedCameraDeviceID
                )
            }

            HUDPrimaryButton(
                title: model.capture.isRecording ? "Stop" : startStopTitle,
                symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                isDestructive: model.capture.isRecording
            ) {
                toggleRecording()
            }
        }
    }

    private var compactRecordingControls: some View {
        HStack(spacing: 6) {
            compactLeadingControls

            CompactFlowLabel(
                tone: model.capture.isRecording ? .red : .blue,
                value: model.capture.isRecording ? recordingPhaseLabel : "Video"
            )

            sourcePicker(width: 154, textWidth: 100)

            compactPermissionControls

            compactCaptureControlGroup

            HUDPrimaryButton(
                title: model.capture.isRecording ? "Stop" : startStopTitle,
                symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                isDestructive: model.capture.isRecording
            ) {
                toggleRecording()
            }
        }
    }

    private var narrowRecordingControls: some View {
        HStack(spacing: 6) {
            backButton

            StatusDot(tone: model.capture.isRecording ? .red : .blue)

            sourcePicker(width: 118, textWidth: 66)

            narrowCaptureOptionsMenu

            HUDPrimaryIconButton(
                title: model.capture.isRecording ? "Stop" : startStopTitle,
                symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                isDestructive: model.capture.isRecording
            ) {
                toggleRecording()
            }
        }
    }

    private var screenshotControls: some View {
        ViewThatFits(in: .horizontal) {
            fullScreenshotControls
            compactScreenshotControls
        }
    }

    private var fullScreenshotControls: some View {
        HStack(spacing: 8) {
            sharedLeadingControls
            FlowLabel(
                tone: model.statusMessage.localizedCaseInsensitiveContains("permission") ? .red : .blue,
                label: "Screenshot",
                value: model.selectedSource == nil ? "Source" : "Ready"
            )

            sourcePicker()
                .layoutPriority(2)

            permissionControls

            HUDPrimaryButton(
                title: "Capture",
                symbolName: "camera.fill",
                isDestructive: false
            ) {
                model.takeScreenshot()
            }
        }
    }

    private var compactScreenshotControls: some View {
        HStack(spacing: 6) {
            compactLeadingControls

            CompactFlowLabel(
                tone: model.statusMessage.localizedCaseInsensitiveContains("permission") ? .red : .blue,
                value: model.selectedSource == nil ? "Source" : "Ready"
            )

            sourcePicker(width: 154, textWidth: 100)

            compactPermissionControls

            HUDPrimaryIconButton(
                title: "Capture",
                symbolName: "camera.fill",
                isDestructive: false
            ) {
                model.takeScreenshot()
            }
        }
    }

    private var sharedLeadingControls: some View {
        HStack(spacing: 8) {
            DragHandle()
            backButton
            HUDDivider()
        }
    }

    private var compactLeadingControls: some View {
        HStack(spacing: 6) {
            DragHandle()
            backButton
        }
    }

    private var backButton: some View {
        Button {
            if !model.capture.isRecording {
                model.cancelCapture()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 38, height: 38)
                .foregroundStyle(Color.white.opacity(model.capture.isRecording ? 0.25 : 0.70))
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(model.capture.isRecording)
        .help("Back")
    }

    private func sourcePicker(width: CGFloat = 208, textWidth: CGFloat = 154) -> some View {
        Button {
            model.requestWindow(.showSourceSelector)
            openWindow(id: "source-selector")
        } label: {
            SourceChip(source: model.selectedSource, width: width, textWidth: textWidth)
        }
        .buttonStyle(.plain)
        .help("Choose Source")
    }

    private var compactCaptureControlGroup: some View {
        HUDControlGroup {
            captureToggles
            compactDeviceMenu
        }
    }

    @ViewBuilder
    private var captureToggles: some View {
        HUDToggle(symbolName: model.includeSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill", isActive: model.includeSystemAudio, title: "System Audio") {
            model.includeSystemAudio.toggle()
        }
        HUDToggle(symbolName: model.includeMicrophone ? "mic.fill" : "mic.slash.fill", isActive: model.includeMicrophone, title: "Microphone") {
            model.includeMicrophone.toggle()
        }
        HUDToggle(symbolName: model.includeCamera ? "video.fill" : "video.slash.fill", isActive: model.includeCamera, title: "Facecam") {
            model.includeCamera.toggle()
        }
    }

    private var compactDeviceMenu: some View {
        Menu {
            Section("Microphone Device") {
                deviceSelectionItems(devices: model.microphoneDevices, selectedDeviceID: $model.selectedMicrophoneDeviceID)
            }
            Section("Camera Device") {
                deviceSelectionItems(devices: model.cameraDevices, selectedDeviceID: $model.selectedCameraDeviceID)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Devices")
    }

    private var narrowCaptureOptionsMenu: some View {
        Menu {
            Button(model.includeSystemAudio ? "Turn Off System Audio" : "Turn On System Audio") {
                model.includeSystemAudio.toggle()
            }
            Button(model.includeMicrophone ? "Turn Off Microphone" : "Turn On Microphone") {
                model.includeMicrophone.toggle()
            }
            Button(model.includeCamera ? "Turn Off Facecam" : "Turn On Facecam") {
                model.includeCamera.toggle()
            }
            Section("Microphone Device") {
                deviceSelectionItems(devices: model.microphoneDevices, selectedDeviceID: $model.selectedMicrophoneDeviceID)
            }
            Section("Camera Device") {
                deviceSelectionItems(devices: model.cameraDevices, selectedDeviceID: $model.selectedCameraDeviceID)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(Color.white.opacity(0.70))
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Capture Options")
    }

    @ViewBuilder
    private var permissionControls: some View {
        if model.statusMessage.localizedCaseInsensitiveContains("permission") {
            HUDPermissionGroup {
                openRelevantPrivacySettings()
            }
        } else if let captureStatusMessage {
            CaptureStatusChip(message: captureStatusMessage, isError: false)
        }
    }

    @ViewBuilder
    private var compactPermissionControls: some View {
        if model.statusMessage.localizedCaseInsensitiveContains("permission") {
            HUDIconActionButton(symbolName: "exclamationmark.triangle.fill", title: "Open Privacy Settings", tint: .red) {
                openRelevantPrivacySettings()
            }
        } else if let captureStatusMessage {
            CaptureStatusChip(message: captureStatusMessage, isError: false, maxWidth: 96)
        }
    }

    private var captureStatusMessage: String? {
        let message = model.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              message != "Ready",
              message != "Rust service ready",
              !message.hasPrefix("Selected "),
              !message.hasPrefix("Opened ") else {
            return nil
        }

        if message.localizedCaseInsensitiveContains("permission") {
            return "Permission needed"
        }
        if message.localizedCaseInsensitiveContains("starting") {
            return "Starting..."
        }
        if message.localizedCaseInsensitiveContains("choose") {
            return "Choose source"
        }
        return message
    }

    private func openRelevantPrivacySettings() {
        let message = model.statusMessage.lowercased()
        if message.contains("microphone") {
            model.openMicrophoneSettings()
        } else if message.contains("camera") {
            model.openCameraSettings()
        } else if message.contains("accessibility") {
            model.openAccessibilitySettings()
        } else {
            model.openPrivacySettings()
        }
    }

    private var recordingPhaseLabel: String {
        switch model.recordingPhase {
        case .starting:
            "Starting"
        case .recording:
            "Live"
        case .stopping:
            "Saving"
        case .interrupted:
            "Interrupted"
        case .idle:
            "Live"
        }
    }

    private var startStopTitle: String {
        model.recordingPhase == .starting ? "Starting" : "Record"
    }

    private func toggleRecording() {
        model.capture.isRecording ? model.stopRecording() : model.startRecording()
    }

    private func deviceMenu(
        symbolName: String,
        title: String,
        devices: [CaptureDeviceInfo],
        selectedDeviceID: Binding<String?>
    ) -> some View {
        Menu {
            deviceSelectionItems(devices: devices, selectedDeviceID: selectedDeviceID)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(title)
    }

    @ViewBuilder
    private func deviceSelectionItems(devices: [CaptureDeviceInfo], selectedDeviceID: Binding<String?>) -> some View {
        Button("System Default") {
            selectedDeviceID.wrappedValue = nil
        }
        ForEach(devices) { device in
            Button(device.isDefault ? "\(device.name) (Default)" : device.name) {
                selectedDeviceID.wrappedValue = device.id
            }
        }
        if devices.isEmpty {
            Text("No devices found")
        }
    }
}

private struct HUDSurface<Content: View>: View {
    var isRecording = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isRecording
                                ? [Color(red: 0.16, green: 0.10, blue: 0.11), Color(red: 0.045, green: 0.043, blue: 0.055)]
                                : [Color(red: 0.10, green: 0.10, blue: 0.13), Color(red: 0.045, green: 0.043, blue: 0.055)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(isRecording ? Color.red.opacity(0.24) : Color.white.opacity(0.15), lineWidth: 1)
                    }
            }
            .shadow(color: Color.black.opacity(0.36), radius: 28, y: 18)
    }
}

private struct DragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(width: 28, height: 36)
            .background(Color.white.opacity(0.001), in: Capsule())
    }
}

private struct HUDDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 2)
    }
}

private struct HUDControlGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(4)
        .background(Color.black.opacity(0.20), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct HUDPrimaryButton: View {
    var title: String
    var symbolName: String
    var isDestructive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 100)
                .frame(height: 40)
                .padding(.horizontal, 14)
                .background(isDestructive ? Color.red.opacity(0.86) : Color.white, in: Capsule())
                .foregroundStyle(isDestructive ? Color.white : Color.studioBackground)
        }
        .buttonStyle(.plain)
    }
}

private struct HUDPrimaryIconButton: View {
    var title: String
    var symbolName: String
    var isDestructive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 42, height: 40)
                .background(isDestructive ? Color.red.opacity(0.86) : Color.white, in: Circle())
                .foregroundStyle(isDestructive ? Color.white : Color.studioBackground)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct HUDIconActionButton: View {
    var symbolName: String
    var title: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct HUDPermissionGroup: View {
    var action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label("Permission", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.red.opacity(0.95))
                .padding(.leading, 10)

            Button(action: action) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.red.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.red.opacity(0.95))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 38)
        .padding(.trailing, 4)
        .background(Color.red.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct CaptureModeButton: View {
    var title: String
    var symbolName: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 104)
                .frame(height: 38)
                .padding(.horizontal, 14)
                .foregroundStyle(isActive ? Color.studioBackground : Color.white.opacity(0.72))
                .background(isActive ? Color.white : Color.white.opacity(0.07), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(isActive ? 0 : 0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private enum FlowTone {
    case blue
    case red
    case amber
}

private struct FlowLabel: View {
    var tone: FlowTone
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(0.65), radius: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.40))
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.84))
            }
        }
        .frame(width: 104, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.08))
        }
    }

    private var dotColor: Color {
        switch tone {
        case .blue: Color.blue
        case .red: Color.red
        case .amber: Color.yellow
        }
    }
}

private struct CompactFlowLabel: View {
    var tone: FlowTone
    var value: String

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(tone: tone)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.white.opacity(0.84))
        }
        .frame(width: 74, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.08))
        }
    }
}

private struct StatusDot: View {
    var tone: FlowTone

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .shadow(color: dotColor.opacity(0.65), radius: 7)
    }

    private var dotColor: Color {
        switch tone {
        case .blue: Color.blue
        case .red: Color.red
        case .amber: Color.yellow
        }
    }
}

private struct SourceChip: View {
    var source: CaptureSource?
    var width: CGFloat = 208
    var textWidth: CGFloat = 154

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(source == nil ? Color.yellow : Color.green)
                .frame(width: 8, height: 8)
            Image(systemName: source?.kind == .window ? "macwindow" : source?.kind == .area ? "rectangle.dashed" : "display")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.65))
            Text(source?.name ?? "Choose source")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: textWidth, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(width: width, alignment: .leading)
        .frame(height: 38)
        .background(Color.black.opacity(0.20), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct CaptureStatusChip: View {
    var message: String
    var isError: Bool
    var maxWidth: CGFloat = 130

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isError ? Color.red.opacity(0.95) : Color.white.opacity(0.76))
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background((isError ? Color.red : Color.white).opacity(isError ? 0.12 : 0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke((isError ? Color.red : Color.white).opacity(isError ? 0.28 : 0.10), lineWidth: 1)
            }
    }
}

private struct HUDToggle: View {
    var symbolName: String
    var isActive: Bool
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(isActive ? Color.blue.opacity(0.95) : Color.white.opacity(0.55))
                .background(isActive ? Color.blue.opacity(0.16) : Color.white.opacity(0.06), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isActive ? Color.blue.opacity(0.35) : Color.white.opacity(0.09), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct EditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var editorSession: EditorSession?

    var body: some View {
        if screenshotURL != nil {
            ScreenshotEditorStudioView(screenshotURL: screenshotURL)
        } else {
            VideoEditorStudioView(videoURL: videoURL, recordingSession: recordingSession)
        }
    }

    private var videoURL: URL? {
        if let editorSession {
            return editorSession.kind == .video ? editorSession.url : nil
        }
        return model.currentVideoURL
    }

    private var screenshotURL: URL? {
        if let editorSession {
            return editorSession.kind == .screenshot ? editorSession.url : nil
        }
        return model.currentScreenshotURL
    }

    private var recordingSession: RecordingSession? {
        editorSession?.recordingSession ?? model.lastEditorSession?.recordingSession
    }
}

private struct VideoEditorStudioView: View {
    var videoURL: URL?
    var recordingSession: RecordingSession?
    @State private var borderRadius = 12.0
    @State private var padding = 18.0
    @State private var shadow = 0.35
    @State private var backgroundBlur = 0.0
    @State private var loopCursor = false
    @State private var cursorSize = 1.0
    @State private var cursorSmoothing = 0.40

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                VideoPreviewPanel(videoURL: videoURL, recordingSession: recordingSession)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                TimelinePanel()
                    .frame(height: 240)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SettingsInspector(
                borderRadius: $borderRadius,
                padding: $padding,
                shadow: $shadow,
                backgroundBlur: $backgroundBlur,
                loopCursor: $loopCursor,
                cursorSize: $cursorSize,
                cursorSmoothing: $cursorSmoothing,
                recordingSession: recordingSession
            )
            .frame(width: 320)
        }
        .padding(16)
        .background(Color.studioMutedBackground)
    }
}

private enum ScreenshotBackgroundMode: String, CaseIterable, Identifiable {
    case gradient
    case color
    case transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gradient: "Gradient"
        case .color: "Color"
        case .transparent: "None"
        }
    }
}

private struct ScreenshotGradientPreset {
    var colors: [NSColor]

    var linearGradient: LinearGradient {
        LinearGradient(
            colors: colors.map { Color(nsColor: $0) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ScreenshotEditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var screenshotURL: URL?
    @State private var backgroundMode: ScreenshotBackgroundMode = .gradient
    @State private var gradientIndex = 0
    @State private var solidColor = Color(red: 0.055, green: 0.055, blue: 0.067)
    @State private var padding = 56.0
    @State private var backgroundRoundness = 28.0
    @State private var backgroundShadow = 0.0
    @State private var imageRoundness = 10.0
    @State private var imageShadow = 0.45
    @State private var isExportDialogPresented = false

    private let gradients: [ScreenshotGradientPreset] = [
        ScreenshotGradientPreset(colors: [
            NSColor(red: 0.11, green: 0.17, blue: 0.25, alpha: 1),
            NSColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1)
        ]),
        ScreenshotGradientPreset(colors: [
            NSColor(red: 0.12, green: 0.10, blue: 0.19, alpha: 1),
            NSColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        ]),
        ScreenshotGradientPreset(colors: [
            NSColor(red: 0.10, green: 0.18, blue: 0.14, alpha: 1),
            NSColor(red: 0.03, green: 0.04, blue: 0.04, alpha: 1)
        ]),
        ScreenshotGradientPreset(colors: [
            NSColor(red: 0.20, green: 0.18, blue: 0.14, alpha: 1),
            NSColor(red: 0.05, green: 0.04, blue: 0.04, alpha: 1)
        ])
    ]

    var body: some View {
        HStack(spacing: 16) {
            ScreenshotCanvas(
                image: image,
                backgroundMode: backgroundMode,
                gradient: selectedGradient.linearGradient,
                solidColor: solidColor,
                padding: padding,
                backgroundRoundness: backgroundRoundness,
                backgroundShadow: backgroundShadow,
                imageRoundness: imageRoundness,
                imageShadow: imageShadow
            )
            .layoutPriority(1)

            ScreenshotSettingsPanel(
                backgroundMode: $backgroundMode,
                gradientIndex: $gradientIndex,
                solidColor: $solidColor,
                padding: $padding,
                backgroundRoundness: $backgroundRoundness,
                backgroundShadow: $backgroundShadow,
                imageRoundness: $imageRoundness,
                imageShadow: $imageShadow,
                gradients: gradients,
                onExport: {
                    isExportDialogPresented = true
                }
            )
            .frame(width: 320)
        }
        .padding(16)
        .background(Color.studioMutedBackground)
        .sheet(isPresented: $isExportDialogPresented) {
            ScreenshotExportDialog(
                onSave: saveComposedPNG,
                onCopy: copyComposedPNG
            )
            .frame(width: 360)
        }
        .onChange(of: model.screenshotExportRequestID) { _, requestID in
            guard requestID != nil, screenshotURL != nil else { return }
            isExportDialogPresented = true
        }
    }

    private var image: NSImage? {
        guard let url = screenshotURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private var selectedGradient: ScreenshotGradientPreset {
        guard gradients.indices.contains(gradientIndex) else {
            return gradients[0]
        }
        return gradients[gradientIndex]
    }

    private func saveComposedPNG() {
        guard let data = renderComposedPNG() else {
            model.statusMessage = "Failed to render screenshot."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedExportFileName

        guard panel.runModal() == .OK, let targetURL = panel.url else {
            return
        }

        do {
            try data.write(to: targetURL, options: .atomic)
            model.statusMessage = "Exported \(targetURL.lastPathComponent)"
        } catch {
            model.statusMessage = error.localizedDescription
        }
    }

    private func copyComposedPNG() {
        guard let data = renderComposedPNG() else {
            model.statusMessage = "Failed to render screenshot."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        if let image = NSImage(data: data), let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }
        model.statusMessage = "Screenshot PNG copied"
    }

    private var suggestedExportFileName: String {
        let baseName = screenshotURL?.deletingPathExtension().lastPathComponent ?? "screenshot"
        return "\(baseName)-export.png"
    }

    private func renderComposedPNG() -> Data? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let exportPadding = max(CGFloat(padding), 0)
        let shadowMargin = max(CGFloat(backgroundShadow), CGFloat(imageShadow)) > 0
            ? ceil(max(CGFloat(backgroundShadow), CGFloat(imageShadow)) * 56)
            : 0
        let backgroundRect = CGRect(
            x: shadowMargin,
            y: shadowMargin,
            width: imageSize.width + exportPadding * 2,
            height: imageSize.height + exportPadding * 2
        )
        let imageRect = CGRect(
            x: backgroundRect.minX + exportPadding,
            y: backgroundRect.minY + exportPadding,
            width: imageSize.width,
            height: imageSize.height
        )
        let width = max(Int(ceil(backgroundRect.width + shadowMargin * 2)), 1)
        let height = max(Int(ceil(backgroundRect.height + shadowMargin * 2)), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        drawExportBackground(in: context, rect: backgroundRect)
        drawExportImageShadow(in: context, rect: imageRect)

        context.saveGState()
        context.addPath(CGPath(
            roundedRect: imageRect,
            cornerWidth: CGFloat(imageRoundness),
            cornerHeight: CGFloat(imageRoundness),
            transform: nil
        ))
        context.clip()
        context.draw(cgImage, in: imageRect)
        context.restoreGState()

        guard let exportedImage = context.makeImage() else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: exportedImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    private func drawExportBackground(in context: CGContext, rect: CGRect) {
        let shouldDrawBackground = backgroundMode != .transparent

        if backgroundShadow > 0, shouldDrawBackground {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: 14 * CGFloat(backgroundShadow)),
                blur: 34 * CGFloat(backgroundShadow),
                color: NSColor.black.withAlphaComponent(0.45 * backgroundShadow).cgColor
            )
            context.setFillColor(NSColor.black.withAlphaComponent(0.01).cgColor)
            context.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: CGFloat(backgroundRoundness),
                cornerHeight: CGFloat(backgroundRoundness),
                transform: nil
            ))
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: CGFloat(backgroundRoundness),
            cornerHeight: CGFloat(backgroundRoundness),
            transform: nil
        ))
        context.clip()

        switch backgroundMode {
        case .gradient:
            let colors = selectedGradient.colors.map { $0.cgColor } as CFArray
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.maxX, y: rect.maxY),
                    options: []
                )
            }
        case .color:
            context.setFillColor(nsColor(from: solidColor).cgColor)
            context.fill(rect)
        case .transparent:
            break
        }

        context.restoreGState()

        if shouldDrawBackground {
            context.saveGState()
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
            context.setLineWidth(1)
            context.addPath(CGPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                cornerWidth: CGFloat(backgroundRoundness),
                cornerHeight: CGFloat(backgroundRoundness),
                transform: nil
            ))
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawExportImageShadow(in context: CGContext, rect: CGRect) {
        guard imageShadow > 0 else { return }

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 18 * CGFloat(imageShadow)),
            blur: 38 * CGFloat(imageShadow),
            color: NSColor.black.withAlphaComponent(0.55 * imageShadow).cgColor
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.01).cgColor)
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: CGFloat(imageRoundness),
            cornerHeight: CGFloat(imageRoundness),
            transform: nil
        ))
        context.fillPath()
        context.restoreGState()
    }

    private func nsColor(from color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.sRGB) ?? NSColor.clear
    }
}

private struct ScreenshotExportDialog: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: () -> Void
    var onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 34, height: 34)
                    .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Export PNG")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Save or copy the composed screenshot.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                Button {
                    onSave()
                    dismiss()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.white)

                Button {
                    onCopy()
                    dismiss()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.primary)
            }

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(Color.studioPanel)
    }
}

private struct ScreenshotCanvas: View {
    var image: NSImage?
    var backgroundMode: ScreenshotBackgroundMode
    var gradient: LinearGradient
    var solidColor: Color
    var padding: Double
    var backgroundRoundness: Double
    var backgroundShadow: Double
    var imageRoundness: Double
    var imageShadow: Double

    var body: some View {
        ZStack {
            if let image {
                screenshotStage(image)
                    .padding(32)
            } else {
                EmptyEditorState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 22, y: 14)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func screenshotStage(_ image: NSImage) -> some View {
        ZStack {
            stageBackground
                .clipShape(RoundedRectangle(cornerRadius: backgroundRoundness, style: .continuous))
                .shadow(
                    color: Color.black.opacity(0.45 * backgroundShadow),
                    radius: 34 * backgroundShadow,
                    y: 14 * backgroundShadow
                )
                .overlay {
                    RoundedRectangle(cornerRadius: backgroundRoundness, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: imageRoundness, style: .continuous))
                .shadow(
                    color: Color.black.opacity(0.55 * imageShadow),
                    radius: 38 * imageShadow,
                    y: 18 * imageShadow
                )
                .padding(CGFloat(padding))
        }
    }

    @ViewBuilder
    private var stageBackground: some View {
        switch backgroundMode {
        case .gradient:
            gradient
        case .color:
            solidColor
        case .transparent:
            Checkerboard()
        }
    }
}

private struct ScreenshotSettingsPanel: View {
    @EnvironmentObject private var model: AppModel
    @Binding var backgroundMode: ScreenshotBackgroundMode
    @Binding var gradientIndex: Int
    @Binding var solidColor: Color
    @Binding var padding: Double
    @Binding var backgroundRoundness: Double
    @Binding var backgroundShadow: Double
    @Binding var imageRoundness: Double
    @Binding var imageShadow: Double
    var gradients: [ScreenshotGradientPreset]
    var onExport: () -> Void

    private let colorSwatches: [Color] = [
        Color(red: 0.055, green: 0.055, blue: 0.067),
        Color(red: 0.95, green: 0.96, blue: 0.98),
        Color(red: 0.10, green: 0.16, blue: 0.24),
        Color(red: 0.13, green: 0.19, blue: 0.14),
        Color(red: 0.24, green: 0.13, blue: 0.18),
        Color(red: 0.23, green: 0.20, blue: 0.13)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    backgroundControls
                    InspectorGroup(title: "Background Layer", symbolName: "rectangle.fill") {
                        InspectorSlider(title: "Padding", valueText: "\(Int(padding))px", value: $padding, range: 0...140, step: 1)
                        InspectorSlider(title: "Roundness", valueText: "\(Int(backgroundRoundness))px", value: $backgroundRoundness, range: 0...64, step: 1)
                        InspectorSlider(title: "Shadow", valueText: "\(Int(backgroundShadow * 100))%", value: $backgroundShadow, range: 0...1, step: 0.01)
                    }
                    InspectorGroup(title: "Image Layer", symbolName: "photo") {
                        InspectorSlider(title: "Roundness", valueText: "\(Int(imageRoundness))px", value: $imageRoundness, range: 0...48, step: 1)
                        InspectorSlider(title: "Shadow", valueText: "\(Int(imageShadow * 100))%", value: $imageShadow, range: 0...1, step: 0.01)
                    }
                }
                .padding(14)
            }

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            HStack(spacing: 8) {
                InspectorFooterButton(title: "Reveal File", symbolName: "folder") {
                    if let url = model.currentScreenshotURL {
                        model.reveal(url.path)
                    }
                }
                InspectorFooterButton(title: "Export", symbolName: "square.and.arrow.up") {
                    onExport()
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.025))
        }
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 12)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "photo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 30)
                .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text("Screenshot Settings")
                    .font(.system(size: 14, weight: .semibold))
                Text("Separate background and image layer styling.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06))
        }
    }

    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Background")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                ForEach(ScreenshotBackgroundMode.allCases) { mode in
                    Button {
                        backgroundMode = mode
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(backgroundMode == mode ? Color.brand : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(backgroundMode == mode ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if backgroundMode == .gradient {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(gradients.indices, id: \.self) { index in
                        Button {
                            gradientIndex = index
                        } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(gradients[index].linearGradient)
                                .frame(height: 44)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(gradientIndex == index ? Color.brand : Color.white.opacity(0.10), lineWidth: gradientIndex == index ? 2 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if backgroundMode == .color {
                HStack(spacing: 8) {
                    ForEach(colorSwatches.indices, id: \.self) { index in
                        Button {
                            solidColor = colorSwatches[index]
                        } label: {
                            Circle()
                                .fill(colorSwatches[index])
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Circle()
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 18
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0...rows {
                for column in 0...columns {
                    let isLight = (row + column).isMultiple(of: 2)
                    let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(rect), with: .color(isLight ? Color.white.opacity(0.18) : Color.white.opacity(0.08)))
                }
            }
        }
        .background(Color.black.opacity(0.25))
    }
}

private struct VideoPreviewPanel: View {
    var videoURL: URL?
    var recordingSession: RecordingSession?
    @StateObject private var playback = VideoPlaybackController()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if videoURL != nil {
                    ZStack(alignment: .bottomTrailing) {
                        PlaybackPreview(playback: playback)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        recordingSessionBadges
                    }
                    .padding(16)
                } else {
                    EmptyEditorState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            HStack {
                Spacer(minLength: 0)
                PlaybackControlStrip(playback: playback)
                    .frame(maxWidth: 700)
                Spacer(minLength: 0)
            }
                .frame(height: 54)
                .padding(.horizontal, 12)
        }
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 22, y: 14)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            syncPlaybackURL(videoURL)
        }
        .onChange(of: videoURL) { _, newURL in
            syncPlaybackURL(newURL)
        }
    }

    private func syncPlaybackURL(_ url: URL?) {
        if let url {
            playback.load(url: url)
        } else {
            playback.clear()
        }
    }

    @ViewBuilder
    private var recordingSessionBadges: some View {
        if let recordingSession {
            VStack(alignment: .trailing, spacing: 6) {
                if recordingSession.facecamVideoPath != nil {
                    Label("Facecam captured", systemImage: "video.fill")
                }
                if recordingSession.cursorTelemetryPath != nil {
                    Label("Cursor telemetry", systemImage: "cursorarrow.motionlines")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(Color.white)
            .padding(12)
        }
    }
}

@MainActor
private final class VideoPlaybackController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var currentTime = 0.0
    @Published var duration = 0.0
    @Published var isPlaying = false

    private var currentURL: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        if currentURL == url, player != nil {
            return
        }

        teardownPlayer()
        currentURL = url
        currentTime = 0
        duration = 0
        isPlaying = false

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        attachTimeObserver(to: player)

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.seek(to: 0)
            }
        }

        let asset = AVURLAsset(url: url)
        Task { [weak self] in
            let loadedDuration = try? await asset.load(.duration)
            let seconds = loadedDuration?.seconds ?? 0
            await MainActor.run {
                guard let self, self.currentURL == url else { return }
                self.duration = seconds.isFinite && seconds > 0 ? seconds : 0
            }
        }
    }

    func clear() {
        teardownPlayer()
        currentURL = nil
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    func togglePlayback() {
        guard let player else { return }

        if isPlaying {
            pause()
        } else {
            if duration > 0, currentTime >= duration {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let clamped = min(max(seconds, 0), upperBound)
        currentTime = clamped
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func attachTimeObserver(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                guard let self, seconds.isFinite else { return }
                self.currentTime = seconds

                let itemDuration = self.player?.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite, itemDuration > 0, self.duration == 0 {
                    self.duration = itemDuration
                }
            }
        }
    }

    private func teardownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil

        player?.pause()
        player = nil
    }

}

private struct EmptyEditorState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 32))
                .foregroundStyle(Color.brand)
                .frame(width: 66, height: 66)
                .background(Color.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.brand.opacity(0.22))
                }
            Text("No Recording Open")
                .font(.system(size: 18, weight: .semibold))
            Text("Start a recording or open a project to edit and export.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PlaybackControlStrip: View {
    @ObservedObject var playback: VideoPlaybackController

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(playback.isPlaying ? Color.white.opacity(0.10) : Color.white, in: Circle())
                    .foregroundStyle(playback.isPlaying ? Color.white : Color.black)
            }
            .buttonStyle(.plain)
            .disabled(playback.player == nil)
            .opacity(playback.player == nil ? 0.45 : 1)

            Text(formatPlaybackTime(playback.currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.76))
                .frame(width: 42, alignment: .trailing)

            ElasticSlider(
                value: Binding(
                    get: { playback.currentTime },
                    set: { playback.seek(to: $0) }
                ),
                range: 0...max(playback.duration, 0.01),
                step: 0.01
            )
            .accessibilityLabel("Playback position")
            .disabled(playback.player == nil)

            Text(formatPlaybackTime(playback.duration))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
                .frame(width: 42, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.58), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 14, y: 8)
    }
}

private func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else {
        return "0:00"
    }

    let minutes = Int(seconds) / 60
    let remainingSeconds = Int(seconds) % 60
    return "\(minutes):\(String(format: "%02d", remainingSeconds))"
}

private struct PlaybackPreview: View {
    @ObservedObject var playback: VideoPlaybackController

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NativeVideoPlayer(playback: playback)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.studioBorder)
                }

            Button {
                playback.togglePlayback()
            } label: {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: 34)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.64), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(playback.player == nil)
            .opacity(playback.player == nil ? 0.45 : 1)
            .padding(14)
        }
    }
}

private final class PlayerLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            preconditionFailure("PlayerLayerView requires an AVPlayerLayer backing layer.")
        }
        return playerLayer
    }
}

private struct NativeVideoPlayer: NSViewRepresentable {
    @ObservedObject var playback: VideoPlaybackController

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = playback.player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.playerLayer.player = playback.player
    }

    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}

private struct TimelinePanel: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TimelineTool(title: "Zoom", symbolName: "plus.magnifyingglass")
                TimelineTool(title: "Suggest", symbolName: "sparkles")
                TimelineTool(title: "Trim", symbolName: "scissors")
                TimelineTool(title: "Annotate", symbolName: "text.bubble")
                TimelineTool(title: "Speed", symbolName: "speedometer")
                Spacer()
                Text("16:9")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.studioBorder)
                    }
            }
            .padding(12)

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            VStack(spacing: 0) {
                TimelineRuler()
                TimelineLayerRow(
                    label: "Zoom",
                    hint: "Press Z to add zoom",
                    accent: Color.blue
                )
                TimelineLayerRow(
                    label: "Trim",
                    hint: "Press T to add trim",
                    accent: Color.red
                )
                TimelineLayerRow(
                    label: "Annotation",
                    hint: "Press A to add annotation",
                    accent: Color.purple
                )
                TimelineLayerRow(
                    label: "Speed",
                    hint: "Press S to add speed",
                    accent: Color.orange
                )
                TimelineLayerRow(
                    label: "Audio",
                    hint: "No audio regions",
                    accent: Color.green
                )
            }
            .padding(12)
        }
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 10)
    }
}

private struct TimelineTool: View {
    var title: String
    var symbolName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.secondary)
        .frame(height: 30)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct TimelineRuler: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 96)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    HStack {
                        ForEach(0..<6, id: \.self) { index in
                            Text(index == 0 ? "0:00" : "0:\(String(format: "%02d", index * 10))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.72))
                                .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : .center)
                        }
                    }

                    Rectangle()
                        .fill(Color.brand.opacity(0.95))
                        .frame(width: 1, height: 228)
                        .offset(x: proxy.size.width * 0.18)
                }
            }
        }
        .frame(height: 24)
    }
}

private struct TimelineLayerRow: View {
    var label: String
    var hint: String
    var accent: Color

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.86))
                .lineLimit(1)
                .frame(width: 96, height: 42, alignment: .leading)
                .padding(.leading, 10)
                .background(Color.white.opacity(0.025))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.095, green: 0.095, blue: 0.11))

                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.64))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: 42)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)
        }
    }
}

private struct SettingsInspector: View {
    @EnvironmentObject private var model: AppModel
    @Binding var borderRadius: Double
    @Binding var padding: Double
    @Binding var shadow: Double
    @Binding var backgroundBlur: Double
    @Binding var loopCursor: Bool
    @Binding var cursorSize: Double
    @Binding var cursorSmoothing: Double
    var recordingSession: RecordingSession?

    @State private var activeTab: InspectorTab = .appearance

    var body: some View {
        HStack(spacing: 0) {
            inspectorRail
            inspectorContent
        }
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 12)
    }

    private func openExternal(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var inspectorRail: some View {
        VStack(spacing: 8) {
            ForEach(InspectorTab.allCases) { tab in
                InspectorRailButton(tab: tab, isActive: activeTab == tab) {
                    activeTab = tab
                }
            }
        }
        .frame(width: 56)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(width: 1)
        }
    }

    private var inspectorContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inspectorHeader
                    tabContent
                }
                .padding(12)
            }

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            inspectorFooter
        }
    }

    private var inspectorHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: activeTab.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 30)
                .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(activeTab.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(activeTab.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(activeTab.id)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06))
        }
    }

    private var inspectorFooter: some View {
        HStack(spacing: 8) {
            InspectorFooterButton(title: "Report Bug", symbolName: "ladybug") {
                openExternal("https://github.com/imbhargav5/open-recorder/issues/new/choose")
            }
            InspectorFooterButton(title: "Star on GitHub", symbolName: "star") {
                openExternal("https://github.com/imbhargav5/open-recorder")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.025))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .appearance:
            InspectorSlider(title: "Shadow", valueText: "\(Int(shadow * 100))%", value: $shadow, range: 0...1, step: 0.01)
            InspectorSlider(title: "Roundness", valueText: "\(Int(borderRadius))px", value: $borderRadius, range: 0...25, step: 0.5)
            InspectorSlider(title: "Padding", valueText: "\(Int(padding))%", value: $padding, range: 0...100, step: 1)
            InspectorSlider(title: "Background Blur", valueText: String(format: "%.1fpx", backgroundBlur), value: $backgroundBlur, range: 0...8, step: 0.25)
            Button {} label: {
                Label("Crop Video", systemImage: "crop")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            BackgroundPalette()
        case .cursor:
            InspectorSwitch(title: "Show Cursor", isOn: $model.showCursor)
            InspectorSwitch(title: "Loop Cursor", isOn: $loopCursor)
            InspectorSlider(title: "Size", valueText: String(format: "%.2fx", cursorSize), value: $cursorSize, range: 0.5...10, step: 0.05)
            InspectorSlider(title: "Smoothing", valueText: String(format: "%.2f", cursorSmoothing), value: $cursorSmoothing, range: 0...2, step: 0.01)
        case .camera:
            InspectorSwitch(title: "Facecam", isOn: .constant(recordingSession?.facecamVideoPath != nil))
            InspectorSlider(title: "Facecam Size", valueText: "24%", value: .constant(24), range: 12...40, step: 1)
            InspectorSlider(title: "Border Width", valueText: "4px", value: .constant(4), range: 0...16, step: 1)
            if let path = recordingSession?.facecamVideoPath {
                SessionAssetRow(title: "Facecam File", path: path)
            }
            PositionGrid()
        case .audio:
            InspectorSwitch(title: "Mute Preview", isOn: .constant(false))
            InspectorSlider(title: "Volume", valueText: "100%", value: .constant(1), range: 0...1, step: 0.01)
            if let sourceName = recordingSession?.sourceName {
                SessionAssetRow(title: "Source", path: sourceName)
            }
        }
    }
}

private struct SessionAssetRow: View {
    var title: String
    var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InspectorRailButton: View {
    var tab: InspectorTab
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(isActive ? Color.brand : Color.secondary)
                .background(isActive ? Color.brand.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isActive ? Color.brand.opacity(0.24) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}

private struct InspectorFooterButton: View {
    var title: String
    var symbolName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundStyle(.secondary)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private enum InspectorTab: CaseIterable, Identifiable {
    case appearance
    case cursor
    case camera
    case audio

    var id: String { title }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .cursor: "Cursor"
        case .camera: "Camera"
        case .audio: "Audio"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: "Frame styling, background, crop, and composition."
        case .cursor: "Cursor visibility and motion effects."
        case .camera: "Facecam overlay settings."
        case .audio: "Master preview and MP4 export audio."
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: "slider.horizontal.3"
        case .cursor: "cursorarrow"
        case .camera: "camera"
        case .audio: "speaker.wave.2"
        }
    }
}

private struct InspectorGroup<Content: View>: View {
    var title: String
    var symbolName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.05))
        }
    }
}

private struct InspectorSlider: View {
    var title: String
    var valueText: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.78))
            }
            ElasticSlider(value: $value, range: range, step: step)
                .accessibilityLabel(title)
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.05))
        }
    }
}

private struct InspectorSwitch: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.05))
        }
    }
}

private struct BackgroundPalette: View {
    private let colors: [Color] = [.red, .yellow, .green, .white, .blue, .orange, .purple, .pink, .cyan, .black]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Background", systemImage: "paintpalette")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(colors.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors[index])
                        .frame(height: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.12))
                        }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.05))
        }
    }
}

private struct PositionGrid: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(index == 8 ? Color.brand.opacity(0.28) : Color.white.opacity(0.06))
                        .frame(height: 28)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectsStudioView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Projects")
                                .font(.system(size: 26, weight: .semibold))
                            Text("Local")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                        }
                        Text("Open a saved project or browse recordings from this device.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        model.refreshBackendState()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(height: 32)
                            .padding(.horizontal, 12)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 16) {
                    ProjectActionCard(title: "Open project", symbolName: "plus", description: "Load an Open Recorder editing session.") {
                        model.openProjectFile()
                    }
                    ProjectActionCard(title: "Recordings folder", symbolName: "folder", description: "Jump to saved captures and exported videos.") {
                        if let path = model.paths?.recordingsDir {
                            model.openPath(path)
                        }
                    }
                }

                Rectangle()
                    .fill(Color.studioBorder)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent projects")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if model.projects.isEmpty {
                        EmptyProjectsPanel()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.projects) { project in
                                ProjectListRow(project: project)
                                if project.id != model.projects.last?.id {
                                    Rectangle()
                                        .fill(Color.studioBorder)
                                        .frame(height: 1)
                                }
                            }
                        }
                        .background(Color.studioPanel.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.studioBorder)
                        }
                    }
                }
            }
            .frame(maxWidth: 1024, alignment: .leading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioMutedBackground)
    }
}

private struct ProjectActionCard: View {
    var title: String
    var symbolName: String
    var description: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(Color.brand)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button(action: action) {
                Label(title == "Open project" ? "Choose file" : "Browse recordings", systemImage: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(title == "Open project" ? Color.brand : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(title == "Open project" ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioPanel.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
    }
}

private struct ProjectListRow: View {
    @EnvironmentObject private var model: AppModel
    var project: ProjectSummary

    var body: some View {
        Button {
            if !project.missing {
                model.openProject(project)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Color.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.brand.opacity(0.22))
                    }
                    .foregroundStyle(Color.brand)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(project.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        if project.missing {
                            Text("Missing")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.red.opacity(0.35))
                                }
                        }
                    }
                    HStack(spacing: 12) {
                        Text(project.sourceName ?? URL(fileURLWithPath: project.recordingPath ?? project.path).lastPathComponent)
                            .lineLimit(1)
                        Label(formattedProjectDate(project.lastOpenedAt), systemImage: "clock")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(project.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(project.missing ? 0.55 : 1)
    }
}

private struct EmptyProjectsPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 30))
                .frame(width: 64, height: 64)
                .foregroundStyle(Color.brand)
                .background(Color.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            Text("No recent projects yet")
                .font(.system(size: 16, weight: .semibold))
            Text("Recent project shortcuts will appear here after you save or open one.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(Color.studioPanel.opacity(0.60), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}

private struct SettingsStudioView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                SettingsSection(title: "Service") {
                    SettingsRow(title: "Status", value: model.serviceHealth.map { "\($0.service) \($0.version)" } ?? "Unavailable")
                    SettingsRow(title: "Platform", value: model.serviceHealth?.platform ?? "macOS")
                    Button {
                        model.refreshBackendState()
                    } label: {
                        Label("Check Service", systemImage: "bolt.horizontal")
                            .frame(height: 34)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                SettingsSection(title: "Folders") {
                    FolderRow(title: "Recordings", path: model.paths?.recordingsDir)
                    FolderRow(title: "Screenshots", path: model.paths?.screenshotsDir)
                    FolderRow(title: "Projects", path: model.paths?.projectsDir)
                }

                SettingsSection(title: "Permissions") {
                    Button {
                        model.openPrivacySettings()
                    } label: {
                        Label("Open Screen Recording Privacy", systemImage: "lock.shield")
                            .frame(height: 34)
                            .padding(.horizontal, 12)
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioMutedBackground)
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(18)
        .background(Color.studioPanel.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
    }
}

private struct SettingsRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 13))
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var model: AppModel
    var title: String
    var path: String?

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(path ?? "Unknown")
                .lineLimit(1)
                .truncationMode(.middle)
            if let path {
                Button {
                    model.openPath(path)
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
    }
}

private func formattedProjectDate(_ value: String) -> String {
    let date: Date
    if let seconds = TimeInterval(value) {
        date = Date(timeIntervalSince1970: seconds)
    } else {
        let formatter = ISO8601DateFormatter()
        date = formatter.date(from: value) ?? Date()
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, h:mm a"
    return formatter.string(from: date)
}

private extension Color {
    static let brand = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let studioBackground = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let studioMutedBackground = Color(red: 0.055, green: 0.055, blue: 0.067)
    static let studioPanel = Color(red: 0.075, green: 0.075, blue: 0.088)
    static let studioCard = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let studioControl = Color(red: 0.12, green: 0.12, blue: 0.145)
    static let studioBorder = Color.white.opacity(0.10)
}
