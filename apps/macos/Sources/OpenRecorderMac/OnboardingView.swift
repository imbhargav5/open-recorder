import AppKit
import Combine
import SwiftUI

enum OnboardingWindowMetrics {
    static let width: CGFloat = 680
    static let height: CGFloat = 560
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var driver = OnboardingDriver(
        screenRecordingPermissionState: .requestAvailable,
        accessibilityPermissionState: .requestAvailable
    )
    private let permissionRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 86)

            OnboardingMark()
                .padding(.bottom, 18)

            Text("Welcome to Open Recorder")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            Text("Before you can start recording, Open Recorder needs a couple of macOS permissions.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .multilineTextAlignment(.center)

            VStack(spacing: 26) {
                OnboardingPermissionRow(
                    title: "Screen Recording Permission",
                    description: "Open Recorder needs to capture video of your screen. You might need to restart the app after granting it.",
                    buttonTitle: screenRecordingButtonTitle,
                    buttonState: screenRecordingButtonState
                ) {
                    driver.send(.screenPermissionButtonTapped)
                }

                OnboardingPermissionRow(
                    title: "Accessibility Permission",
                    description: "Open Recorder uses Accessibility to capture cursor movement and shortcut keystrokes while you are recording.",
                    buttonTitle: accessibilityButtonTitle,
                    buttonState: accessibilityButtonState
                ) {
                    driver.send(.accessibilityPermissionButtonTapped)
                }
            }
            .padding(.top, 42)

            Text(driver.state.statusMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 500, height: 38)
                .padding(.top, 20)

            StudioButton(hitTarget: .rounded(8)) {
                driver.send(.continueRequested)
            } label: {
                Label("Continue", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 180, height: 40)
                    .foregroundStyle(driver.state.canContinue ? Color.white : Color.white.opacity(0.34))
                    .background(
                        driver.state.canContinue ? Color.brand : Color.studioControl,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(driver.state.canContinue ? Color.brand.opacity(0.45) : Color.studioBorder)
                    }
            }
            .disabled(!driver.state.canContinue)

            Spacer(minLength: 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioBackground)
        .onAppear {
            driver.configure(
                currentPermissions: {
                    model.refreshOnboardingPermissionStates()
                    return (model.screenRecordingPermissionState, model.accessibilityPermissionState)
                },
                requestScreenPermission: {
                    model.requestOnboardingScreenRecordingPermission()
                },
                requestAccessibilityPermission: {
                    model.requestOnboardingAccessibilityPermission()
                },
                openScreenRecordingSettings: {
                    model.openPrivacySettings()
                },
                openAccessibilitySettings: {
                    model.openAccessibilitySettings()
                },
                completeOnboarding: {
                    model.completeOnboarding()
                }
            )
            driver.send(.appeared)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            driver.send(.appBecameActive)
        }
        .onReceive(permissionRefreshTimer) { _ in
            driver.send(.timerTicked)
        }
    }

    private var screenRecordingButtonTitle: String {
        switch driver.state.screenRecordingPermissionState {
        case .granted:
            "Screen Recording enabled"
        case .requestAvailable:
            "Allow Screen Recording"
        case .requestAlreadyShown:
            "Open Screen Recording Settings"
        }
    }

    private var screenRecordingButtonState: OnboardingPermissionButtonState {
        switch driver.state.screenRecordingPermissionState {
        case .granted:
            .enabled
        case .requestAvailable:
            .action
        case .requestAlreadyShown:
            .settings
        }
    }

    private var accessibilityButtonTitle: String {
        switch driver.state.accessibilityPermissionState {
        case .granted:
            "Accessibility access enabled"
        case .requestAvailable:
            "Allow Accessibility Access"
        case .requestAlreadyShown:
            "Open Accessibility Settings"
        }
    }

    private var accessibilityButtonState: OnboardingPermissionButtonState {
        switch driver.state.accessibilityPermissionState {
        case .granted:
            .enabled
        case .requestAvailable:
            .action
        case .requestAlreadyShown:
            .settings
        }
    }
}

private struct OnboardingMark: View {
    var body: some View {
        Image(nsImage: OpenRecorderAppIcon.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 72, height: 72)
            .shadow(color: Color.black.opacity(0.30), radius: 18, y: 10)
            .accessibilityHidden(true)
    }
}

private enum OpenRecorderAppIcon {
    @MainActor
    static var image: NSImage {
        if let bundledIcon = Bundle.main
            .url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:)) {
            return bundledIcon
        }

        return NSApplication.shared.applicationIconImage
    }
}

private enum OnboardingPermissionButtonState {
    case action
    case settings
    case enabled
}

private struct OnboardingPermissionRow: View {
    var title: String
    var description: String
    var buttonTitle: String
    var buttonState: OnboardingPermissionButtonState
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 34) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.90))

                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 240, alignment: .leading)

            StudioButton(hitTarget: .rounded(6), action: action) {
                HStack(spacing: 9) {
                    if buttonState == .enabled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(buttonTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(width: 242, height: 36)
                .foregroundStyle(foregroundColor)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(borderColor, lineWidth: 1)
                }
            }
        }
        .frame(width: 516, alignment: .leading)
    }

    private var foregroundColor: Color {
        switch buttonState {
        case .action, .settings:
            Color.brand
        case .enabled:
            Color.white.opacity(0.94)
        }
    }

    private var backgroundColor: Color {
        switch buttonState {
        case .action, .settings:
            Color.studioControl
        case .enabled:
            Color.brand.opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch buttonState {
        case .action, .settings:
            Color.studioBorder
        case .enabled:
            Color.brand.opacity(0.42)
        }
    }
}
