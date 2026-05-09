import AVFoundation
import AppKit
import SwiftUI

enum AppWindowRole {
    case hud
    case sourceSelector
    case studio
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    var role: AppWindowRole = .studio

    var body: some View {
        Group {
            switch role {
            case .hud:
                HUDOverlayWindowView()
                    .frame(width: hudSize.width, height: hudSize.height)
                    .background(WindowConfigurator(role: .hud, preferredSize: hudSize))
            case .sourceSelector:
                SourceSelectorWindowView()
                    .frame(minWidth: 520, idealWidth: 660, maxWidth: .infinity, minHeight: 620, idealHeight: 820, maxHeight: .infinity)
                    .background(WindowConfigurator(role: .sourceSelector))
            case .studio:
                StudioWindowView()
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

    private var hudSize: CGSize {
        if model.captureFlow == .choice {
            return CGSize(width: 780, height: 155)
        }

        if model.statusMessage.localizedCaseInsensitiveContains("permission") {
            return CGSize(width: model.captureMode == .recording ? 940 : 900, height: 155)
        }

        return CGSize(width: model.captureMode == .recording ? 780 : 860, height: 155)
    }
}

struct SettingsView: View {
    var body: some View {
        SettingsStudioView()
    }
}

private enum NativeWindowRole {
    case hud
    case sourceSelector
    case studio
}

private struct WindowConfigurator: NSViewRepresentable {
    var role: NativeWindowRole
    var preferredSize: CGSize?

    func makeNSView(context: Context) -> WindowConfigurationView {
        let view = WindowConfigurationView()
        view.role = role
        view.preferredSize = preferredSize
        return view
    }

    func updateNSView(_ nsView: WindowConfigurationView, context: Context) {
        nsView.role = role
        nsView.preferredSize = preferredSize
        nsView.configureWindow()
    }
}

private final class WindowConfigurationView: NSView {
    var role: NativeWindowRole = .studio {
        didSet {
            configuredRole = nil
        }
    }
    var preferredSize: CGSize? {
        didSet {
            if preferredSize != oldValue {
                configuredRole = nil
            }
        }
    }

    private var configuredRole: NativeWindowRole?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window, configuredRole != role else { return }
        configuredRole = role

        switch role {
        case .hud:
            configureHUD(window)
        case .sourceSelector:
            configureSourceSelector(window)
        case .studio:
            configureStudio(window)
        }
    }

    private func configureHUD(_ window: NSWindow) {
        let size = preferredSize ?? CGSize(width: 780, height: 155)
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
        window.setContentSize(NSSize(width: 660, height: 820))
        window.minSize = NSSize(width: 520, height: 620)
        window.maxSize = NSSize(width: 1400, height: 1200)
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
        case .showStudio:
            openWindow(id: "studio")
        case .closeSourceSelector:
            dismissWindow(id: "source-selector")
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

    private var visibleTabs: [SourceSelectorTab] {
        model.captureMode == .recording ? SourceSelectorTab.allCases : [.screens, .windows]
    }

    var body: some View {
        ZStack {
            Color.studioBackground
                .ignoresSafeArea()

            SourceSelectorCard(
                sourceTab: $sourceTab,
                visibleTabs: visibleTabs,
                onCancel: {
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
                }
            )
            .padding(16)
        }
        .onAppear {
            if model.captureMode == .screenshot, sourceTab == .area {
                sourceTab = .screens
            }
            model.reloadSources()
        }
        .onChange(of: model.captureMode) { _, newMode in
            if newMode == .screenshot && sourceTab == .area {
                sourceTab = .screens
            }
        }
    }
}

private struct StudioWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StudioShell()
            .onAppear {
                if model.selectedSection == .capture {
                    model.selectedSection = .editor
                }
            }
    }
}

private struct StudioShell: View {
    @EnvironmentObject private var model: AppModel
    @State private var sidebarExpanded = true

    var body: some View {
        HStack(spacing: 0) {
            StudioSidebar(isExpanded: sidebarExpanded)

            VStack(spacing: 0) {
                StudioTitleBar(sidebarExpanded: $sidebarExpanded)
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
            EditorStudioView()
        case .projects:
            ProjectsStudioView()
        case .editor:
            EditorStudioView()
        case .settings:
            SettingsStudioView()
        }
    }
}

private struct StudioSidebar: View {
    @EnvironmentObject private var model: AppModel
    var isExpanded: Bool

    private let items: [AppSection] = [.editor, .projects]

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
                    Image(systemName: "video.fill")
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
                        Text("Studio")
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
        case .editor: "video"
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

                if model.selectedSection == .editor {
                    Button {
                        model.exportCurrentRecording()
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
                    .disabled(model.currentVideoURL == nil)
                    .opacity(model.currentVideoURL == nil ? 0.55 : 1)
                }
            }
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
                if model.selectedSection == .editor {
                    Text("MP4")
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
            model.currentVideoURL?.lastPathComponent ?? "Open Recorder Editor"
        }
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
        model.captureMode == .recording ? SourceSelectorTab.allCases : [.screens, .windows]
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
                    SourceSelectorCard(sourceTab: $sourceTab, visibleTabs: visibleTabs)
                        .frame(maxWidth: 860)
                    CaptureHUD(sourceTab: $sourceTab)
                        .padding(.bottom, 12)
                }
                .padding(16)
                .background(Color.studioMutedBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.captureMode) { _, newMode in
            if newMode == .screenshot && sourceTab == .area {
                sourceTab = .screens
            }
        }
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
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 26, y: 18)
    }

    private var selectorDescription: String {
        if model.captureMode == .screenshot {
            "Pick a screen or a single app window for this screenshot."
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
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(sources) { source in
                SourceTile(
                    source: source,
                    isSelected: model.selectedSource?.id == source.id,
                    isCompact: sourceTab == .windows
                ) {
                    model.selectedSource = source
                }
            }
        }
    }
}

private struct SourceTile: View {
    var source: CaptureSource
    var isSelected: Bool
    var isCompact: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                ZStack {
                    if let thumbnail = source.thumbnailData,
                       let image = NSImage(data: thumbnail) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.055))
                        Image(systemName: source.kind == .window ? "macwindow" : source.kind == .area ? "rectangle.dashed" : "display")
                            .font(.system(size: isCompact ? 18 : 24, weight: .medium))
                            .foregroundStyle(.secondary)
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
                .aspectRatio(source.kind == .window ? 1.6 : 16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

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
            .padding(isCompact ? 6 : 8)
            .background(Color.studioCard.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.brand : Color.studioBorder, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
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
            Text(sourceTab == .area ? "Draw a recording area" : "No sources available")
                .font(.system(size: 15, weight: .semibold))
            Text(sourceTab == .area ? "Select the part of the screen you want to record." : "Try a different tab or make sure the source is visible.")
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
        HStack(spacing: 8) {
            sharedLeadingControls

            FlowLabel(
                tone: model.capture.isRecording ? .red : .blue,
                label: model.capture.isRecording ? "Recording" : "Ready",
                value: model.capture.isRecording ? "Live" : "Video"
            )

            sourcePicker
                .layoutPriority(2)

            permissionControls

            HUDDivider()

            HUDControlGroup {
                HUDToggle(symbolName: model.includeMicrophone ? "mic.fill" : "mic.slash.fill", isActive: model.includeMicrophone, title: "Microphone") {
                    model.includeMicrophone.toggle()
                }
                HUDToggle(symbolName: "cursorarrow", isActive: model.showCursor, title: "Cursor") {
                    model.showCursor.toggle()
                }
                HUDToggle(symbolName: "hand.tap", isActive: model.showClicks, title: "Clicks") {
                    model.showClicks.toggle()
                }
            }

            HUDPrimaryButton(
                title: model.capture.isRecording ? "Stop" : "Record",
                symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                isDestructive: model.capture.isRecording
            ) {
                model.capture.isRecording ? model.stopRecording() : model.startRecording()
            }
        }
    }

    private var screenshotControls: some View {
        HStack(spacing: 8) {
            sharedLeadingControls

            FlowLabel(
                tone: model.statusMessage.localizedCaseInsensitiveContains("permission") ? .red : .blue,
                label: "Screenshot",
                value: model.selectedSource == nil ? "Source" : "Ready"
            )

            sourcePicker
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

    private var sharedLeadingControls: some View {
        HStack(spacing: 8) {
            DragHandle()

            Button {
                if !model.capture.isRecording {
                    model.captureFlow = .choice
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

            HUDDivider()
        }
    }

    private var sourcePicker: some View {
        Button {
            model.requestWindow(.showSourceSelector)
            openWindow(id: "source-selector")
        } label: {
            SourceChip(source: model.selectedSource)
        }
        .buttonStyle(.plain)
        .help("Choose Source")
    }

    @ViewBuilder
    private var permissionControls: some View {
        if model.statusMessage.localizedCaseInsensitiveContains("permission") {
            HUDPermissionGroup {
                model.openPrivacySettings()
            }
        } else if let captureStatusMessage {
            CaptureStatusChip(message: captureStatusMessage, isError: false)
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

private struct SourceChip: View {
    var source: CaptureSource?

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
                .frame(maxWidth: 154, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(width: 208, alignment: .leading)
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

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isError ? Color.red.opacity(0.95) : Color.white.opacity(0.76))
            .frame(maxWidth: 130, alignment: .leading)
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
                VideoPreviewPanel()
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
                cursorSmoothing: $cursorSmoothing
            )
            .frame(width: 320)
        }
        .padding(16)
        .background(Color.studioMutedBackground)
    }
}

private struct VideoPreviewPanel: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var playback = VideoPlaybackController()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if model.currentVideoURL != nil {
                    PlaybackPreview(playback: playback)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
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
            syncPlaybackURL(model.currentVideoURL)
        }
        .onChange(of: model.currentVideoURL) { _, newURL in
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
            InspectorSwitch(title: "Facecam", isOn: .constant(false))
            InspectorSlider(title: "Facecam Size", valueText: "24%", value: .constant(24), range: 12...40, step: 1)
            InspectorSlider(title: "Border Width", valueText: "4px", value: .constant(4), range: 0...16, step: 1)
            PositionGrid()
        case .audio:
            InspectorSwitch(title: "Mute Preview", isOn: .constant(false))
            InspectorSlider(title: "Volume", valueText: "100%", value: .constant(1), range: 0...1, step: 0.01)
        }
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
