import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum NativeWindowRole {
    case hud
    case onboarding
    case sourceSelector
    case microphoneSelector
    case cameraSelector
    case cameraBubble
    case studio
}

enum CaptureOverlayWindowChrome {
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllApplications,
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]
    static let level: NSWindow.Level = .screenSaver
}

enum HUDWindowChrome {
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let collectionBehavior = CaptureOverlayWindowChrome.collectionBehavior
    static let level = CaptureOverlayWindowChrome.level
    static let activeSpaceSyncDelay: TimeInterval = 0.18

    @MainActor
    static func apply(to window: NSWindow) {
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
        }

        window.level = level
        window.collectionBehavior = collectionBehavior
        window.hidesOnDeactivate = false
    }

    @MainActor
    static func prepareForActiveSpace(_ window: NSWindow) {
        window.orderOut(nil)
        apply(to: window)
    }
}

final class HUDOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDPanelController {
    private var panel: HUDOverlayPanel?
    private weak var model: AppModel?
    private var isPresented = false
    private var activeSpaceObserver: NSObjectProtocol?
    private var pendingActiveSpaceSync: DispatchWorkItem?

    init() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncToActiveSpace()
                self?.scheduleActiveSpaceSync()
            }
        }
    }

    func attach(model: AppModel) {
        guard self.model !== model || panel == nil else {
            if model.isHUDVisible {
                show()
            }
            return
        }

        panel?.close()
        self.model = model
        panel = makePanel(model: model)
        if model.isHUDVisible {
            show()
        }
    }

    func show() {
        guard let panel else { return }
        isPresented = true
        HUDWindowChrome.apply(to: panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        isPresented = false
        pendingActiveSpaceSync?.cancel()
        pendingActiveSpaceSync = nil
        panel?.orderOut(nil)
    }

    private func makePanel(model: AppModel) -> HUDOverlayPanel {
        let size = HUDWindowMetrics.defaultSize
        let panel = HUDOverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: HUDWindowChrome.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = "Open Recorder"
        panel.identifier = NSUserInterfaceItemIdentifier("hud")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        HUDWindowChrome.apply(to: panel)
        let hostingView = NSHostingView(
            rootView: HUDOverlayWindowView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        )
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setContentSize(size)
        positionBottomCenter(panel, contentSize: size)
        return panel
    }

    private func syncToActiveSpace() {
        guard isPresented, let panel else { return }
        HUDWindowChrome.prepareForActiveSpace(panel)
        if let screen = panel.screen ?? NSScreen.main {
            let origin = HUDWindowMetrics.clampedOrigin(
                for: panel.frame.size,
                currentOrigin: panel.frame.origin,
                visibleFrame: screen.visibleFrame
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
    }

    private func scheduleActiveSpaceSync() {
        pendingActiveSpaceSync?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.syncToActiveSpace()
            }
        }
        pendingActiveSpaceSync = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + HUDWindowChrome.activeSpaceSyncDelay,
            execute: workItem
        )
    }

    private func positionBottomCenter(_ panel: NSPanel, contentSize: CGSize) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let origin = HUDWindowMetrics.bottomCenterOrigin(
            for: contentSize,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrame(NSRect(origin: origin, size: contentSize), display: false)
    }
}

struct HUDHostWindowHider: NSViewRepresentable {
    func makeNSView(context: Context) -> HUDHostWindowHidingView {
        HUDHostWindowHidingView()
    }

    func updateNSView(_ nsView: HUDHostWindowHidingView, context: Context) {
        nsView.hideHostWindow()
    }
}

final class HUDHostWindowHidingView: NSView {
    private var hasScheduledHide = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideHostWindow()
    }

    func hideHostWindow() {
        guard let window, !hasScheduledHide else { return }
        hasScheduledHide = true
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak window] in
            window?.isExcludedFromWindowsMenu = true
            window?.orderOut(nil)
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
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

final class WindowConfigurationView: NSView {
    override var isFlipped: Bool { true }

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
        case .cameraBubble:
            configureCameraBubble(window)
        case .studio:
            configureStudio(window)
        }
    }

    private func configureCameraBubble(_ window: NSWindow) {
        window.title = "Camera Preview"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.fullSizeContentView, .resizable])
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { button in
            window.standardWindowButton(button)?.isHidden = true
        }
        if window.frame.origin.y < 50 || window.frame.origin == .zero {
            if let screen = window.screen ?? NSScreen.main {
                let visibleFrame = screen.visibleFrame
                let windowSize = window.frame.size
                let origin = CGPoint(
                    x: visibleFrame.maxX - windowSize.width - 32,
                    y: visibleFrame.maxY - windowSize.height - 32
                )
                window.setFrameOrigin(origin)
            }
        }
        window.orderFrontRegardless()
    }

    private func configureHUD(_ window: NSWindow) {
        let size = HUDWindowMetrics.defaultSize
        window.title = "Open Recorder"
        window.setContentSize(size)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        HUDWindowChrome.prepareForActiveSpace(window)
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { button in
            window.standardWindowButton(button)?.isHidden = true
        }
        if window.frame.origin.y < 30 || window.frame.origin == .zero {
            positionBottomCenter(window, contentSize: size)
        }
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
        let size = NSSize(width: SourceSelectorWindowMetrics.width, height: SourceSelectorWindowMetrics.height)
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.070, alpha: 1)
        window.hasShadow = true
        // Keep the selector above the HUD so the HUD cannot intercept its scroll and
        // click events while capture setup is open.
        window.level = NSWindow.Level(rawValue: HUDWindowChrome.level.rawValue + 1)
        // .managed ensures macOS routes focus to this window in a production app bundle.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Do NOT include .fullSizeContentView: with a transparent titlebar the content
        // would extend into the titlebar area, creating an invisible hit-testing dead zone
        // over the header (refresh/cancel buttons). Without it, content starts below the
        // titlebar frame, leaving the buttons fully interactive.
        window.styleMask = [.titled, .closable]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.titled, .closable, .fullSizeContentView])
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
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
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.titled, .closable, .fullSizeContentView])
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
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
        let origin = HUDWindowMetrics.bottomCenterOrigin(for: contentSize, visibleFrame: visibleFrame)
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

    func syncHUDToActiveSpace(_ window: NSWindow) {
        guard role == .hud else { return }
        HUDWindowChrome.prepareForActiveSpace(window)
        if let screen = window.screen ?? NSScreen.main {
            let clamped = HUDWindowMetrics.clampedOrigin(
                for: window.frame.size,
                currentOrigin: window.frame.origin,
                visibleFrame: screen.visibleFrame
            )
            window.setFrameOrigin(clamped)
        }
        window.orderFrontRegardless()
    }
}

enum SourceSelectorWindowMetrics {
    static let width: CGFloat = 660
    static let height: CGFloat = 490
    static let minWidth: CGFloat = 660
    static let compactHeight: CGFloat = 490
    static let minHeight: CGFloat = 490
    static let maxHeight: CGFloat = 490
    static let outerPadding: CGFloat = 16
}

struct SourceSelectorCardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = SourceSelectorWindowMetrics.height

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
    override var isFlipped: Bool { true }

    var preferredContentSize: CGSize = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPreferredContentSize()
    }

    func applyPreferredContentSize() {
        guard let window else { return }

        DispatchQueue.main.async { [weak window] in
            guard let window else { return }

            let targetContentSize = NSSize(
                width: SourceSelectorWindowMetrics.width,
                height: SourceSelectorWindowMetrics.height
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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    var shell: AppShellDriver
    var isCameraEnabled: () -> Bool = { false }

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                handle(shell.state.windowCommand)
            }
            .onChange(of: shell.state.windowCommand?.id) { _, _ in
                handle(shell.state.windowCommand)
            }
    }

    private func handle(_ command: NativeWindowCommand?) {
        if command?.action == .showStudio {
            facecamLog.notice("WindowCommandBridge.handle(.showStudio) incomingID=\(String(describing: command?.id), privacy: .public) currentID=\(String(describing: self.shell.state.windowCommand?.id), privacy: .public)")
        }
        guard let command, shell.state.windowCommand?.id == command.id else { return }
        shell.send(.windowCommandConsumed(command.id))

        switch command.action {
        case .showHUD:
            NSApp.unhide(nil)
            openWindow(id: "hud")
            NSApp.activate(ignoringOtherApps: true)
        case .hideHUD:
            dismissWindow(id: "hud")
        case .showOnboarding:
            NSApp.unhide(nil)
            dismissWindow(id: "hud")
            dismissWindow(id: "source-selector")
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        case .finishOnboarding:
            NSApp.unhide(nil)
            dismissWindow(id: "onboarding")
            openWindow(id: "hud")
            NSApp.activate(ignoringOtherApps: true)
        case .showRecordingSetup:
            NSApp.unhide(nil)
            openWindow(id: "hud")
            openWindow(id: "source-selector")
            NSApp.activate(ignoringOtherApps: true)
        case .showScreenRecordingSetup:
            NSApp.unhide(nil)
            dismissWindow(id: "source-selector")
            openWindow(id: "hud")
            NSApp.activate(ignoringOtherApps: true)
        case .hideRecordingSetup:
            dismissCaptureWindows()
        case .hideAppWindowsForCapture:
            hideAppWindowsForCapture()
        case .showSourceSelector:
            NSApp.unhide(nil)
            openWindow(id: "source-selector")
        case .showMicrophoneSelector:
            NSApp.unhide(nil)
            openWindow(id: "microphone-selector")
        case .showCameraSelector:
            NSApp.unhide(nil)
            openWindow(id: "camera-selector")
        case .showCameraBubble:
            openWindow(id: "camera-bubble")
        case .closeCameraBubble:
            dismissWindow(id: "camera-bubble")
        case .showStudio:
            facecamLog.notice("WindowCommandBridge.handle(.showStudio) hasSession=\(command.editorSession != nil, privacy: .public)")
            NSApp.unhide(nil)
            dismissWindow(id: "hud")
            dismissCaptureWindows(alwaysDismissCameraBubble: true)
            if let editorSession = command.editorSession {
                openWindow(id: "editor", value: editorSession)
            } else {
                openWindow(id: "studio")
            }
            NSApp.activate(ignoringOtherApps: true)
        case .closeCaptureSetup:
            dismissWindow(id: "source-selector")
        case .closeSourceSelector:
            dismissWindow(id: "source-selector")
        case .closeMicrophoneSelector:
            dismissWindow(id: "microphone-selector")
        case .closeCameraSelector:
            dismissWindow(id: "camera-selector")
        }
    }

    private func dismissCaptureWindows(alwaysDismissCameraBubble: Bool = false) {
        // Deliberately does NOT dismiss "hud" — see callers. .hideRecordingSetup fires
        // the moment the recording countdown starts (recordingCountdownStarted), well
        // before recording actually begins; dismissing the HUD here hid it for the
        // entire countdown + recording, with no way back short of the ⌘R global hotkey.
        // Callers that genuinely need the HUD gone (e.g. .showStudio, once recording is
        // fully over) dismiss it explicitly themselves.
        dismissWindow(id: "source-selector")
        dismissWindow(id: "microphone-selector")
        dismissWindow(id: "camera-selector")
        if alwaysDismissCameraBubble || !isCameraEnabled() {
            dismissWindow(id: "camera-bubble")
        }
    }

    private func hideAppWindowsForCapture() {
        // NativeScreenRecorder already excludes this app's own process from the
        // ScreenCaptureKit filter (excludingApplications:), so the app's windows never
        // appear in the recorded output regardless of on-screen visibility — no need to
        // hide anything at the OS level (NSApp.hide) for that. dismissCaptureWindows()
        // leaves "hud" alone, which matters here: this fires on both
        // .recordingStarting and .recordingStarted, so it must not take down the
        // recording HUD (Stop button, timer) the user needs for the rest of the
        // recording.
        dismissCaptureWindows()
    }
}

struct HUDOverlayWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        CaptureHUD(options: model.captureOptions)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(width: HUDWindowMetrics.defaultSize.width, height: HUDWindowMetrics.defaultSize.height)
    }
}
