import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class OpenRecorderAppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingProjectURLs: [URL] = []
    private let windowActions = AppWindowActions()
    private let statusItemController = OpenRecorderStatusItemController()
    private let hotKeyController = GlobalRecordingHotKeyController()
    private var windowCommandCancellable: AnyCancellable?

    func attach(model: AppModel) {
        if self.model !== model {
            self.model = model
            statusItemController.attach(model: model, windowActions: windowActions)
            hotKeyController.attach(model: model)
            windowCommandCancellable = model.$windowCommand
                .receive(on: RunLoop.main)
                .sink { [weak self] command in
                    Task { @MainActor in
                        self?.handleWindowCommand(command)
                    }
                }
        } else {
            self.model = model
        }
        pendingProjectURLs.append(contentsOf: launchArgumentProjectURLs())
        flushPendingProjectURLs()
        handleWindowCommand(model.windowCommand)
    }

    func installWindowActions(
        openWindow: @escaping (String) -> Void,
        openEditor: @escaping (EditorSession) -> Void,
        dismissWindow: @escaping (String) -> Void
    ) {
        windowActions.install(openWindow: openWindow, openEditor: openEditor, dismissWindow: dismissWindow)
        handleWindowCommand(model?.windowCommand)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        pendingProjectURLs.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
        flushPendingProjectURLs()
        sender.reply(toOpenOrPrint: .success)
    }

    private func flushPendingProjectURLs() {
        guard let model else { return }
        let urls = pendingProjectURLs
        pendingProjectURLs.removeAll()
        urls.forEach { model.openProjectFile(at: $0) }
    }

    private func handleWindowCommand(_ command: NativeWindowCommand?) {
        guard windowActions.isInstalled,
              let model,
              let command = model.consumeWindowCommand(command) else {
            return
        }

        windowActions.perform(command)
    }

    private func launchArgumentProjectURLs() -> [URL] {
        CommandLine.arguments.dropFirst().compactMap { argument in
            guard argument.hasSuffix(".openrecorder") else {
                return nil
            }
            return URL(fileURLWithPath: argument)
        }
    }
}

@main
struct OpenRecorderApp: App {
    @NSApplicationDelegateAdaptor(OpenRecorderAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

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
        .windowResizability(.contentSize)
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
                .keyboardShortcut("r", modifiers: [.command])

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
                    dismissWindow: { id in dismissWindow(id: id) }
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
    private var activateApp: () -> Void = {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func install(
        openWindow: @escaping (String) -> Void,
        openEditor: @escaping (EditorSession) -> Void,
        dismissWindow: @escaping (String) -> Void,
        activateApp: @escaping () -> Void = {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    ) {
        self.openWindow = openWindow
        self.openEditor = openEditor
        self.dismissWindow = dismissWindow
        self.activateApp = activateApp
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
            openWindow("hud")
        case .hideHUD:
            dismissWindow("hud")
        case .showOnboarding:
            dismissWindow("hud")
            dismissWindow("source-selector")
            openWindow("onboarding")
            activateApp()
        case .finishOnboarding:
            dismissWindow("onboarding")
            openWindow("hud")
            activateApp()
        case .showRecordingSetup:
            openWindow("hud")
            openWindow("source-selector")
            activateApp()
        case .hideRecordingSetup:
            dismissWindow("hud")
            dismissWindow("source-selector")
        case .showSourceSelector:
            openWindow("source-selector")
        case .showMicrophoneSelector:
            openWindow("microphone-selector")
        case .showCameraSelector:
            openWindow("camera-selector")
        case .showAreaSelector:
            openWindow("area-selector")
        case .showStudio:
            if let editorSession = command.editorSession {
                openEditor(editorSession)
            } else {
                openWindow("studio")
            }
            activateApp()
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
        switch model.recordingPhase {
        case .countingDown, .starting, .recording:
            return true
        case .idle, .stopping, .interrupted:
            return model.capture.isRecording
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if isDirectStopState {
            let image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop Recording")
            image?.isTemplate = true
            button.image = image
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
        menu.addItem(hudItem)

        if model?.lastEditorSession != nil {
            let editorItem = NSMenuItem(title: "Show Last Editor", action: #selector(showLastEditor), keyEquivalent: "")
            editorItem.target = self
            menu.addItem(editorItem)
        }

        menu.addItem(.separator())

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
        if model.isHUDVisible {
            model.hideHUD()
            windowActions.dismiss("hud")
        } else {
            model.showHUD()
            windowActions.open("hud")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func showLastEditor() {
        guard let model, let session = model.lastEditorSession, let windowActions else { return }
        model.showEditor(for: session)
        windowActions.openEditorSession(session)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func beginCapture(_ mode: CaptureMode) {
        guard let model, let windowActions else { return }
        guard model.canStartNewCapture else { return }
        model.beginCapture(mode)
        model.showHUD()
        windowActions.open("source-selector")
        windowActions.open("hud")
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class GlobalRecordingHotKeyController {
    private weak var model: AppModel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func attach(model: AppModel) {
        self.model = model
        registerIfNeeded()
    }

    private func registerIfNeeded() {
        guard hotKeyRef == nil, eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<GlobalRecordingHotKeyController>
                .fromOpaque(userData)
                .takeUnretainedValue()
            Task { @MainActor in
                controller.model?.toggleRecordingShortcut()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: fourCharCode("ORcd"), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
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
        let image = Bundle.module
            .url(forResource: "OpenRecorderMenuBarIcon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }
}
