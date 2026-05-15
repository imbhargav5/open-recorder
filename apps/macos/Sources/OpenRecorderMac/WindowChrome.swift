import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum NativeWindowRole {
    case hud
    case onboarding
    case sourceSelector
    case microphoneSelector
    case cameraSelector
    case areaSelector
    case studio
}

enum HUDWindowChrome {
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary
    ]
    static let level: NSWindow.Level = .screenSaver
    static let activeSpaceSyncDelay: TimeInterval = 0.18
}

struct WindowConfigurator: NSViewRepresentable {
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

final class WindowConfigurationView: NSView {
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
    private weak var configuredWindow: NSWindow?
    private weak var hudSpaceSyncWindow: NSWindow?
    private var activeSpaceObserver: NSObjectProtocol?
    private var pendingActiveSpaceSync: DispatchWorkItem?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopSyncingHUDToActiveSpace()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else {
            configuredWindow = nil
            stopSyncingHUDToActiveSpace()
            return
        }
        if role == .areaSelector {
            guard isPresented else {
                window.close()
                return
            }
            configuredRole = role
            configuredWindow = window
            stopSyncingHUDToActiveSpace()
            configureAreaSelector(window)
            return
        }
        guard configuredRole != role || configuredWindow !== window else { return }
        configuredRole = role
        configuredWindow = window

        if role != .hud {
            stopSyncingHUDToActiveSpace()
        }

        switch role {
        case .hud:
            configureHUD(window)
        case .onboarding:
            configureOnboarding(window)
        case .sourceSelector:
            configureSourceSelector(window)
        case .microphoneSelector:
            configureMicrophoneSelector(window)
        case .cameraSelector:
            configureCameraSelector(window)
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
        window.level = HUDWindowChrome.level
        window.collectionBehavior = HUDWindowChrome.collectionBehavior
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { button in
            window.standardWindowButton(button)?.isHidden = true
        }
        positionBottomCenter(window, contentSize: size)
        startSyncingHUDToActiveSpace(for: window)
        window.orderFrontRegardless()
    }

    private func configureOnboarding(_ window: NSWindow) {
        let size = NSSize(width: OnboardingWindowMetrics.width, height: OnboardingWindowMetrics.height)
        window.title = "Open Recorder Setup"
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1)
        window.hasShadow = true
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.titled, .closable, .fullSizeContentView])
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.makeKeyAndOrderFront(nil)
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

    private func configureMicrophoneSelector(_ window: NSWindow) {
        window.title = "Choose Microphone"
        window.setContentSize(NSSize(width: CaptureDeviceSelectorWindowMetrics.width, height: CaptureDeviceSelectorWindowMetrics.height))
        window.minSize = NSSize(width: CaptureDeviceSelectorWindowMetrics.minWidth, height: CaptureDeviceSelectorWindowMetrics.minHeight)
        window.maxSize = NSSize(width: CaptureDeviceSelectorWindowMetrics.width, height: 520)
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

    private func configureCameraSelector(_ window: NSWindow) {
        window.title = "Choose Camera"
        window.setContentSize(NSSize(width: CaptureDeviceSelectorWindowMetrics.width, height: CaptureDeviceSelectorWindowMetrics.height))
        window.minSize = NSSize(width: CaptureDeviceSelectorWindowMetrics.minWidth, height: CaptureDeviceSelectorWindowMetrics.minHeight)
        window.maxSize = NSSize(width: CaptureDeviceSelectorWindowMetrics.width, height: 520)
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

    private func startSyncingHUDToActiveSpace(for window: NSWindow) {
        guard activeSpaceObserver == nil || hudSpaceSyncWindow !== window else {
            return
        }

        stopSyncingHUDToActiveSpace()
        hudSpaceSyncWindow = window
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, let window else { return }
                self.syncHUDToActiveSpace(window)
                self.scheduleHUDActiveSpaceSync(for: window)
            }
        }
    }

    private func stopSyncingHUDToActiveSpace() {
        pendingActiveSpaceSync?.cancel()
        pendingActiveSpaceSync = nil
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
        activeSpaceObserver = nil
        hudSpaceSyncWindow = nil
    }

    private func scheduleHUDActiveSpaceSync(for window: NSWindow) {
        pendingActiveSpaceSync?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window else { return }
                self.syncHUDToActiveSpace(window)
            }
        }
        pendingActiveSpaceSync = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + HUDWindowChrome.activeSpaceSyncDelay,
            execute: workItem
        )
    }

    private func syncHUDToActiveSpace(_ window: NSWindow) {
        guard role == .hud, window.isVisible else { return }
        let size = HUDWindowMetrics.clampedSize(
            for: preferredSize ?? window.contentRect(forFrameRect: window.frame).size,
            screen: window.screen ?? NSScreen.main
        )
        window.collectionBehavior = HUDWindowChrome.collectionBehavior
        window.level = HUDWindowChrome.level
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size
        positionBottomCenter(window, contentSize: size)
        window.orderFrontRegardless()
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

struct SourceSelectorCardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = SourceSelectorWindowMetrics.compactHeight - (SourceSelectorWindowMetrics.outerPadding * 2)

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SourceSelectorWindowSizer: NSViewRepresentable {
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

final class SourceSelectorWindowSizingView: NSView {
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

struct WindowCommandBridge: View {
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
        case .hideHUD:
            dismissWindow(id: "hud")
        case .showOnboarding:
            dismissWindow(id: "hud")
            dismissWindow(id: "source-selector")
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        case .finishOnboarding:
            dismissWindow(id: "onboarding")
            openWindow(id: "hud")
            NSApp.activate(ignoringOtherApps: true)
        case .showRecordingSetup:
            openWindow(id: "hud")
            openWindow(id: "source-selector")
            NSApp.activate(ignoringOtherApps: true)
        case .hideRecordingSetup:
            dismissWindow(id: "hud")
            dismissWindow(id: "source-selector")
        case .showSourceSelector:
            openWindow(id: "source-selector")
        case .showMicrophoneSelector:
            openWindow(id: "microphone-selector")
        case .showCameraSelector:
            openWindow(id: "camera-selector")
        case .showAreaSelector:
            openWindow(id: "area-selector")
        case .showStudio:
            if let editorSession = command.editorSession {
                openWindow(id: "editor", value: editorSession)
            } else {
                openWindow(id: "studio")
            }
            NSApp.activate(ignoringOtherApps: true)
        case .closeCaptureSetup:
            dismissWindow(id: "source-selector")
            dismissWindow(id: "area-selector")
        case .closeSourceSelector:
            dismissWindow(id: "source-selector")
        case .closeMicrophoneSelector:
            dismissWindow(id: "microphone-selector")
        case .closeCameraSelector:
            dismissWindow(id: "camera-selector")
        case .closeAreaSelector:
            dismissWindow(id: "area-selector")
        }
    }
}

struct HUDOverlayWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.clear

            switch model.hudState.phase {
            case .idle, .choosingMode:
                CaptureChoiceHUD()
            case .choosingSourceType(let mode), .screenSelecting(let mode):
                SourceTypeChoiceHUD(mode: mode)
            default:
                CaptureHUD(sourceTab: .constant(model.captureMode == .screenshot ? .screens : .screens))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
    }
}
