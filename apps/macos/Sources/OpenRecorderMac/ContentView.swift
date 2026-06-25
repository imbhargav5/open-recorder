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
            case .areaSelector:
                AreaSelectionWindowView()
                    .background(WindowConfigurator(role: .areaSelector, isPresented: model.isAreaSelectionActive))
            case .studio:
                StudioWindowView(editorSession: editorSession)
                    .background(WindowConfigurator(role: .studio))
            }
        }
        .overlay(WindowCommandBridge(shell: model.appShell).allowsHitTesting(false))
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            model.openEditorFile(at: url)
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
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsStudioView(driver: model.appShell.settings)
    }
}
