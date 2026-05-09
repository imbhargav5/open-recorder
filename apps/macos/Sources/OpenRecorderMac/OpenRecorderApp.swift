import AppKit
import SwiftUI

@MainActor
final class OpenRecorderAppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingProjectURLs: [URL] = []

    func attach(model: AppModel) {
        self.model = model
        pendingProjectURLs.append(contentsOf: launchArgumentProjectURLs())
        flushPendingProjectURLs()
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
        MenuBarExtra {
            MenuBarControls()
                .environmentObject(model)
        } label: {
            Image(nsImage: OpenRecorderMenuBarIcon.image)
                .resizable()
                .renderingMode(.original)
                .frame(width: 18, height: 18)
                .accessibilityLabel("Open Recorder")
        }

        Window("Open Recorder", id: "hud") {
            ContentView(role: .hud)
                .environmentObject(model)
                .onAppear {
                    appDelegate.attach(model: model)
                }
                .task {
                    model.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: HUDWindowMetrics.defaultSize.width, height: HUDWindowMetrics.defaultSize.height)

        Window("Choose Source", id: "source-selector") {
            ContentView(role: .sourceSelector)
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: SourceSelectorWindowMetrics.width, height: SourceSelectorWindowMetrics.compactHeight)

        Window("Choose Microphone", id: "microphone-selector") {
            ContentView(role: .microphoneSelector)
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: CaptureDeviceSelectorWindowMetrics.width, height: CaptureDeviceSelectorWindowMetrics.height)

        Window("Choose Camera", id: "camera-selector") {
            ContentView(role: .cameraSelector)
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: CaptureDeviceSelectorWindowMetrics.width, height: CaptureDeviceSelectorWindowMetrics.height)

        Window("Select Area", id: "area-selector") {
            ContentView(role: .areaSelector)
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 900, height: 600)

        Window("Open Recorder Editor", id: "studio") {
            ContentView(role: .studio)
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)

        WindowGroup("Open Recorder Editor", id: "editor", for: EditorSession.self) { $session in
            ContentView(role: .studio, editorSession: session)
                .environmentObject(model)
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

private struct MenuBarControls: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.capture.isRecording {
            Button("Stop Recording") {
                model.stopRecording()
            }
        } else {
            Button("New Recording") {
                beginCapture(.recording)
            }
            .disabled(!model.canStartNewCapture)
        }

        Button("New Screenshot") {
            beginCapture(.screenshot)
        }
        .disabled(!model.canStartNewCapture)

        Divider()

        Button(model.isHUDVisible ? "Hide Recorder" : "Show Recorder") {
            toggleRecorderHUD()
        }

        if let lastEditorSession = model.lastEditorSession {
            Button("Show Last Editor") {
                model.showEditor(for: lastEditorSession)
                openWindow(id: "editor", value: lastEditorSession)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Divider()

        Button("Quit Open Recorder") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func beginCapture(_ mode: CaptureMode) {
        guard model.canStartNewCapture else { return }
        model.beginCapture(mode)
        model.showHUD()
        openWindow(id: "source-selector")
        openWindow(id: "hud")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleRecorderHUD() {
        if model.isHUDVisible {
            model.hideHUD()
            dismissWindow(id: "hud")
        } else {
            model.showHUD()
            openWindow(id: "hud")
            NSApp.activate(ignoringOtherApps: true)
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
