import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppWindowRole {
    case hud
    case onboarding
    case sourceSelector
    case microphoneSelector
    case cameraSelector
    case cameraBubble
    case areaSelector
    case studio
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var measuredHUDSize: CGSize = HUDWindowMetrics.defaultSize
    var role: AppWindowRole = .studio
    var editorSession: EditorSession?

    var body: some View {
        Group {
            switch role {
            case .hud:
                hudWindowContent
            case .onboarding:
                OnboardingView(driver: model.appShell.onboarding)
                    .frame(width: OnboardingWindowMetrics.width, height: OnboardingWindowMetrics.height)
                    .background(WindowConfigurator(role: .onboarding))
            case .sourceSelector:
                SourceSelectorWindowView()
                    .frame(width: SourceSelectorWindowMetrics.width)
                    .background(WindowConfigurator(role: .sourceSelector))
            case .microphoneSelector:
                MicrophoneSelectorWindowView()
                    .frame(width: CaptureDeviceSelectorWindowMetrics.width, height: CaptureDeviceSelectorWindowMetrics.height)
                    .background(WindowConfigurator(role: .microphoneSelector))
            case .cameraSelector:
                CameraSelectorWindowView()
                    .frame(width: CaptureDeviceSelectorWindowMetrics.width, height: CaptureDeviceSelectorWindowMetrics.height)
                    .background(WindowConfigurator(role: .cameraSelector))
            case .cameraBubble:
                CameraBubbleWindowView()
                    .background(WindowConfigurator(role: .cameraBubble))
            case .areaSelector:
                AreaSelectionWindowView()
                    .background(WindowConfigurator(role: .areaSelector, isPresented: model.isAreaSelectionActive))
            case .studio:
                StudioWindowView(editorSession: editorSession)
                    .background(WindowConfigurator(role: .studio))
            }
        }
        .overlay(WindowCommandBridge(shell: model.appShell, isCameraEnabled: { model.includeCamera }).allowsHitTesting(false))
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            model.openEditorFile(at: url)
        }
    }

    @ViewBuilder
    private var hudWindowContent: some View {
        HUDOverlayWindowView()
            .environment(\.layoutDirection, .leftToRight)
            .flipsForRightToLeftLayoutDirection(false)
            .background(WindowConfigurator(role: .hud))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsStudioView(
            driver: model.appShell.settings,
            serviceHealth: model.serviceHealth,
            paths: model.paths
        )
    }
}
