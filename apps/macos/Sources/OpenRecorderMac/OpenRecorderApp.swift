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
        .defaultSize(width: 780, height: 155)

        Window("Choose Source", id: "source-selector") {
            ContentView(role: .sourceSelector)
                .environmentObject(model)
        }
        .defaultSize(width: 660, height: 820)

        Window("Open Recorder Editor", id: "studio") {
            ContentView(role: .studio)
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Capture") {
                    model.captureFlow = .choice
                    model.requestWindow(.showHUD)
                }
                .keyboardShortcut("n", modifiers: [.command])

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
}
