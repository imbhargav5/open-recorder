import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class OpenRecorderAppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingFileURLs: [URL] = []
    private let windowActions = AppWindowActions()
    private let statusItemController = OpenRecorderStatusItemController()
    private let hotKeyController = GlobalRecordingHotKeyController()
    private let updateChecker = UpdateChecker.shared
    private var terminationTask: Task<Void, Never>?

    func attach(model: AppModel) {
        if self.model !== model {
            self.model = model
            statusItemController.attach(model: model, windowActions: windowActions)
            hotKeyController.attach(model: model)
            model.installNativeWindowCommandHandler { [weak self] command in
                self?.handleWindowCommand(command)
            }
        } else {
            self.model = model
        }
        pendingFileURLs.append(contentsOf: launchArgumentFileURLs())
        flushPendingFileURLs()
        handleWindowCommand(model.windowCommand)
    }

    var isCameraEnabled: Bool {
        guard let model else { return false }
        return model.includeCamera || model.cameraCaptureSession != nil
    }

    func installWindowActions(
        openWindow: @escaping (String) -> Void,
        openEditor: @escaping (EditorSession) -> Void,
        dismissWindow: @escaping (String) -> Void,
        shouldKeepCameraBubble: @escaping () -> Bool = { false }
    ) {
        windowActions.install(
            openWindow: openWindow,
            openEditor: openEditor,
            dismissWindow: dismissWindow,
            shouldKeepCameraBubble: shouldKeepCameraBubble
        )
        handleWindowCommand(model?.windowCommand)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        pendingFileURLs.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
        flushPendingFileURLs()
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        terminationTask = Task { [weak self, weak model] in
            let canTerminate = await model?.prepareForTermination() ?? true
            self?.terminationTask = nil
            if !canTerminate {
                sender.activate(ignoringOtherApps: true)
            }
            sender.reply(toApplicationShouldTerminate: canTerminate)
        }
        return .terminateLater
    }

    private func flushPendingFileURLs() {
        guard let model else { return }
        let urls = pendingFileURLs
        pendingFileURLs.removeAll()
        urls.forEach { model.openEditorFile(at: $0) }
    }

    private func handleWindowCommand(_ command: NativeWindowCommand?) {
        guard windowActions.isInstalled,
              let model,
              let command = model.consumeWindowCommand(command) else {
            return
        }

        windowActions.perform(command)
    }

    private func launchArgumentFileURLs() -> [URL] {
        CommandLine.arguments.dropFirst().compactMap { argument in
            let url = URL(fileURLWithPath: argument)
            guard Self.canOpenFile(at: url) else {
                return nil
            }
            return url
        }
    }

    private static func canOpenFile(at url: URL) -> Bool {
        url.pathExtension.lowercased() == "openrecorder"
            || EditorMediaKind.screenshot.supports(url)
            || EditorMediaKind.video.supports(url)
    }
}

@main
struct OpenRecorderApp: App {
    @NSApplicationDelegateAdaptor(OpenRecorderAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel(captureSetupPreferencesStore: .live)

    var body: some Scene {
        Window("Open Recorder", id: "hud") {
            ContentView(role: .hud)
                .environmentObject(model)
                .onAppear {
                    appDelegate.attach(model: model)
                }
                .background(AppWindowActionBridge(appDelegate: appDelegate))
                .task {
                    model.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: HUDWindowMetrics.defaultSize.width, height: HUDWindowMetrics.defaultSize.height)

        Window("Open Recorder Setup", id: "onboarding") {
            ContentView(role: .onboarding)
                .environmentObject(model)
                .background(AppWindowActionBridge(appDelegate: appDelegate))
                .frame(width: OnboardingWindowMetrics.width, height: OnboardingWindowMetrics.height)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: OnboardingWindowMetrics.width, height: OnboardingWindowMetrics.height)

        Window("Choose Source", id: "source-selector") {
            ContentView(role: .sourceSelector)
                .environmentObject(model)
                .background(AppWindowActionBridge(appDelegate: appDelegate))
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: SourceSelectorWindowMetrics.width, height: SourceSelectorWindowMetrics.compactHeight)

        Window("Choose Microphone", id: "microphone-selector") {
            ContentView(role: .microphoneSelector)
                .environmentObject(model)
                .background(AppWindowActionBridge(appDelegate: appDelegate))
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: CaptureDeviceSelectorWindowMetrics.width, height: CaptureDeviceSelectorWindowMetrics.height)

        Window("Choose Camera", id: "camera-selector") {
            ContentView(role: .cameraSelector)
                .environmentObject(model)
                .background(AppWindowActionBridge(appDelegate: appDelegate))
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: CaptureDeviceSelectorWindowMetrics.width, height: CaptureDeviceSelectorWindowMetrics.height)

        Window("Camera Bubble", id: "camera-bubble") {
            ContentView(role: .cameraBubble)
                .environmentObject(model)
                .background(AppWindowActionBridge(appDelegate: appDelegate))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Select Area", id: "area-selector") {
            ContentView(role: .areaSelector)
                .environmentObject(model)
                .background(AppWindowActionBridge(appDelegate: appDelegate))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 900, height: 600)

        Window("Open Recorder Editor", id: "studio") {
            ContentView(role: .studio)
                .environmentObject(model)
                .background(AppWindowActionBridge(appDelegate: appDelegate))
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)

        WindowGroup("Open Recorder Editor", id: "editor", for: EditorSession.self) { $session in
            ContentView(role: .studio, editorSession: session)
                .environmentObject(model)
                .background(AppWindowActionBridge(appDelegate: appDelegate))
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    beginCapture(.recording)
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!model.canStartNewCapture)

                Button("New Screenshot") {
                    beginCapture(.screenshot)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!model.canStartNewCapture)

                Button("Toggle Recording") {
                    model.toggleRecordingShortcut()
                }

                Button("Open Project...") {
                    model.openProjectFile()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Divider()

                Button("Show Projects") {
                    model.selectedSection = .projects
                    model.requestWindow(.showStudio)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Show Editor") {
                    model.selectedSection = .editor
                    model.requestWindow(.showStudio)
                }
                .keyboardShortcut("2", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560)
                .preferredColorScheme(.dark)
        }
    }

    private func beginCapture(_ mode: CaptureMode) {
        model.beginCapture(mode)
    }
}

private struct AppWindowActionBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    let appDelegate: OpenRecorderAppDelegate

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                appDelegate.installWindowActions(
                    openWindow: { id in openWindow(id: id) },
                    openEditor: { session in openWindow(id: "editor", value: session) },
                    dismissWindow: { id in dismissWindow(id: id) },
                    shouldKeepCameraBubble: { [weak appDelegate] in
                        appDelegate?.isCameraEnabled ?? false
                    }
                )
            }
    }
}

@MainActor
final class AppWindowActions {
    private(set) var isInstalled = false
    private var openWindow: (String) -> Void = { _ in }
    private var openEditor: (EditorSession) -> Void = { _ in }
    private var dismissWindow: (String) -> Void = { _ in }
    private var shouldKeepCameraBubble: () -> Bool = { false }
    private var hideApp: () -> Void = {
        NSApplication.shared.hide(nil)
    }
    private var unhideApp: () -> Void = {
        NSApplication.shared.unhide(nil)
    }
    private var activateApp: () -> Void = {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func install(
        openWindow: @escaping (String) -> Void,
        openEditor: @escaping (EditorSession) -> Void,
        dismissWindow: @escaping (String) -> Void,
        shouldKeepCameraBubble: @escaping () -> Bool = { false },
        activateApp: @escaping () -> Void = {
            NSApplication.shared.activate(ignoringOtherApps: true)
        },
        hideApp: @escaping () -> Void = {
            NSApplication.shared.hide(nil)
        },
        unhideApp: @escaping () -> Void = {
            NSApplication.shared.unhide(nil)
        }
    ) {
        self.openWindow = openWindow
        self.openEditor = openEditor
        self.dismissWindow = dismissWindow
        self.shouldKeepCameraBubble = shouldKeepCameraBubble
        self.activateApp = activateApp
        self.hideApp = hideApp
        self.unhideApp = unhideApp
        isInstalled = true
    }

    func open(_ id: String) {
        openWindow(id)
    }

    func dismiss(_ id: String) {
        dismissWindow(id)
    }

    func openEditorSession(_ session: EditorSession) {
        openEditor(session)
    }

    func perform(_ command: NativeWindowCommand) {
        switch command.action {
        case .showHUD:
            unhideApp()
            openWindow("hud")
            activateApp()
        case .hideHUD:
            dismissWindow("hud")
        case .showOnboarding:
            unhideApp()
            dismissWindow("hud")
            dismissWindow("source-selector")
            openWindow("onboarding")
            activateApp()
        case .finishOnboarding:
            unhideApp()
            dismissWindow("onboarding")
            openWindow("hud")
            activateApp()
        case .showRecordingSetup:
            unhideApp()
            openWindow("hud")
            openWindow("source-selector")
            activateApp()
        case .showScreenRecordingSetup:
            unhideApp()
            dismissWindow("source-selector")
            dismissWindow("area-selector")
            openWindow("hud")
            activateApp()
        case .hideRecordingSetup:
            dismissCaptureWindows()
        case .hideAppWindowsForCapture:
            hideAppWindowsForCapture()
        case .showSourceSelector:
            unhideApp()
            openWindow("source-selector")
        case .showMicrophoneSelector:
            unhideApp()
            openWindow("microphone-selector")
        case .showCameraSelector:
            unhideApp()
            openWindow("camera-selector")
        case .showCameraBubble:
            openWindow("camera-bubble")
        case .closeCameraBubble:
            dismissWindow("camera-bubble")
        case .showAreaSelector:
            unhideApp()
            openWindow("area-selector")
        case .showStudio:
            unhideApp()
            dismissCaptureWindows(alwaysDismissCameraBubble: true)
            if let editorSession = command.editorSession {
                openEditor(editorSession)
            } else {
                openWindow("studio")
            }
            activateApp()
        case .closeCaptureSetup:
            dismissWindow("source-selector")
            dismissWindow("area-selector")
        case .closeSourceSelector:
            dismissWindow("source-selector")
        case .closeMicrophoneSelector:
            dismissWindow("microphone-selector")
        case .closeCameraSelector:
            dismissWindow("camera-selector")
        case .closeAreaSelector:
            dismissWindow("area-selector")
        }
    }

    private func dismissCaptureWindows(alwaysDismissCameraBubble: Bool = false) {
        dismissWindow("hud")
        dismissWindow("source-selector")
        dismissWindow("area-selector")
        dismissWindow("microphone-selector")
        dismissWindow("camera-selector")
        if alwaysDismissCameraBubble || !shouldKeepCameraBubble() {
            dismissWindow("camera-bubble")
        }
    }

    private func hideAppWindowsForCapture() {
        dismissCaptureWindows()
        if !shouldKeepCameraBubble() {
            hideApp()
        }
    }
}

@MainActor
private final class OpenRecorderStatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var model: AppModel?
    private var windowActions: AppWindowActions?
    private var cancellables: Set<AnyCancellable> = []

    func attach(model: AppModel, windowActions: AppWindowActions) {
        self.model = model
        self.windowActions = windowActions

        if statusItem == nil {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.statusItem = statusItem
            statusItem.button?.target = self
            statusItem.button?.action = #selector(statusItemClicked)
            statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        cancellables.removeAll()
        model.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)

        updateStatusItem()
    }

    @objc private func statusItemClicked() {
        guard let model else { return }

        if isDirectStopState, NSApp.currentEvent?.type != .rightMouseUp {
            model.toggleRecordingShortcut()
            return
        }

        showMenu()
    }

    private var isDirectStopState: Bool {
        guard let model else { return false }
        return model.captureState.isDirectStopState(runtimeIsRecording: model.capture.isRecording)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if isDirectStopState {
            button.image = OpenRecorderMenuBarIcon.image
            button.contentTintColor = .systemRed
            button.toolTip = "Stop Recording (⌘R)"
            button.setAccessibilityLabel("Stop Recording")
        } else {
            button.image = OpenRecorderMenuBarIcon.image
            button.contentTintColor = nil
            button.toolTip = "Open Recorder"
            button.setAccessibilityLabel("Open Recorder")
        }
    }

    private func showMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        if isDirectStopState {
            menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "r"))
            menu.items.last?.keyEquivalentModifierMask = [.command]
            menu.items.last?.target = self
            menu.addItem(.separator())
        }

        let newRecording = NSMenuItem(title: "New Recording", action: #selector(newRecording), keyEquivalent: "")
        newRecording.target = self
        newRecording.isEnabled = model?.canStartNewCapture ?? false
        menu.addItem(newRecording)

        let newScreenshot = NSMenuItem(title: "New Screenshot", action: #selector(newScreenshot), keyEquivalent: "")
        newScreenshot.target = self
        newScreenshot.isEnabled = model?.canStartNewCapture ?? false
        menu.addItem(newScreenshot)

        menu.addItem(.separator())

        let hudTitle = model?.isHUDVisible == true ? "Hide Recorder" : "Show Recorder"
        let hudItem = NSMenuItem(title: hudTitle, action: #selector(toggleRecorderHUD), keyEquivalent: "")
        hudItem.target = self
        hudItem.isEnabled = model?.canShowCaptureUI ?? true
        menu.addItem(hudItem)

        if model?.lastEditorSession != nil {
            let editorItem = NSMenuItem(title: "Show Last Editor", action: #selector(showLastEditor), keyEquivalent: "")
            editorItem.target = self
            menu.addItem(editorItem)
        }

        menu.addItem(.separator())

        if UpdateChecker.shared.isEnabled {
            let checkForUpdatesItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            checkForUpdatesItem.target = self
            menu.addItem(checkForUpdatesItem)

            menu.addItem(.separator())
        }

        let quitItem = NSMenuItem(title: "Quit Open Recorder", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func stopRecording() {
        model?.toggleRecordingShortcut()
    }

    @objc private func newRecording() {
        beginCapture(.recording)
    }

    @objc private func newScreenshot() {
        beginCapture(.screenshot)
    }

    @objc private func toggleRecorderHUD() {
        guard let model, let windowActions else { return }
        guard model.canShowCaptureUI else {
            return
        }
        if model.isHUDVisible {
            model.hideHUD()
            windowActions.dismiss("hud")
        } else {
            model.showHUD()
            NSApp.unhide(nil)
            windowActions.open("hud")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func showLastEditor() {
        guard let model, let session = model.lastEditorSession, let windowActions else { return }
        model.showEditor(for: session)
        NSApp.unhide(nil)
        windowActions.openEditorSession(session)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func beginCapture(_ mode: CaptureMode) {
        guard let model, let windowActions else { return }
        guard model.canStartNewCapture else { return }
        model.beginCapture(mode)
        model.showHUD()
        NSApp.unhide(nil)
        windowActions.open("hud")
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class GlobalRecordingHotKeyController {
    private weak var model: AppModel?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var registeredCombinations: [UInt32: KeyCombination] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var cancellables: Set<AnyCancellable> = []

    func attach(model: AppModel) {
        if self.model === model {
            syncRegistration(
                captureState: model.captureState,
                runtimeIsRecording: model.capture.isRecording,
                shortcuts: model.shortcutPreferences
            )
            return
        }

        unregisterAll()
        cancellables.removeAll()
        self.model = model

        model.$captureState
            .sink { [weak self, weak model] state in
                guard let model else { return }
                self?.syncRegistration(
                    captureState: state,
                    runtimeIsRecording: model.capture.isRecording,
                    shortcuts: model.shortcutPreferences
                )
            }
            .store(in: &cancellables)

        model.capture.$isRecording
            .sink { [weak self, weak model] isRecording in
                guard let model else { return }
                self?.syncRegistration(
                    captureState: model.captureState,
                    runtimeIsRecording: isRecording,
                    shortcuts: model.shortcutPreferences
                )
            }
            .store(in: &cancellables)

        model.$shortcutPreferences
            .sink { [weak self, weak model] shortcuts in
                guard let model else { return }
                self?.syncRegistration(
                    captureState: model.captureState,
                    runtimeIsRecording: model.capture.isRecording,
                    shortcuts: shortcuts
                )
            }
            .store(in: &cancellables)

        syncRegistration(
            captureState: model.captureState,
            runtimeIsRecording: model.capture.isRecording,
            shortcuts: model.shortcutPreferences
        )
    }

    private func syncRegistration(
        captureState: CaptureState,
        runtimeIsRecording: Bool,
        shortcuts: ShortcutPreferences
    ) {
        guard installEventHandlerIfNeeded() else { return }

        let actionMap: [(UInt32, CaptureShortcutAction)] = [
            (1, .toggleRecording),
            (2, .deviceScreenshot),
            (3, .dragScreenshot),
            (4, .deviceScreenRecord),
            (5, .dragScreenRecord)
        ]

        for (id, action) in actionMap {
            let item = shortcuts.item(for: action)
            let isAllowedByCaptureState: Bool
            if action == .toggleRecording {
                isAllowedByCaptureState = captureState.shouldRegisterRecordingHotKey(runtimeIsRecording: runtimeIsRecording)
            } else {
                isAllowedByCaptureState = true
            }

            if item.isEnabled && isAllowedByCaptureState {
                registerIfNeeded(id: id, combination: item.keyCombination)
            } else {
                unregister(id: id)
            }
        }
    }

    private func registerIfNeeded(id: UInt32, combination: KeyCombination) {
        if let existing = registeredCombinations[id], existing == combination, hotKeyRefs[id] != nil {
            return
        }

        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("ORhk"), id: id)
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref {
            hotKeyRefs[id] = ref
            registeredCombinations[id] = combination
        }
    }

    private func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        registeredCombinations.removeValue(forKey: id)
    }

    private func installEventHandlerIfNeeded() -> Bool {
        guard eventHandlerRef == nil else { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }

            let controller = Unmanaged<GlobalRecordingHotKeyController>
                .fromOpaque(userData)
                .takeUnretainedValue()
            let targetID = hotKeyID.id
            Task { @MainActor in
                controller.handleHotKey(id: targetID)
            }
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
        }

        return status == noErr
    }

    private func handleHotKey(id: UInt32) {
        guard let model else { return }
        switch id {
        case 1:
            model.toggleRecordingShortcut()
        case 2:
            model.triggerDeviceScreenshot()
        case 3:
            model.triggerDragScreenshot()
        case 4:
            model.triggerDeviceScreenRecord()
        case 5:
            model.triggerDragScreenRecord()
        default:
            break
        }
    }

    private func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredCombinations.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}

private enum OpenRecorderMenuBarIcon {
    static var image: NSImage {
        let image = resourceURL
            .flatMap(NSImage.init(contentsOf:)) ??
            NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Open Recorder") ??
            NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private static var resourceURL: URL? {
        OpenRecorderResources.url(forResource: "OpenRecorderMenuBarIcon", withExtension: "png")
    }
}
