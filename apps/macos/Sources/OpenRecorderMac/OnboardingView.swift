import AppKit
import SwiftUI

enum OnboardingWindowMetrics {
    static let width: CGFloat = 680
    static let height: CGFloat = 560
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

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
                    model.requestOnboardingScreenRecordingPermission()
                }

                OnboardingPermissionRow(
                    title: "Accessibility Permission",
                    description: "Open Recorder uses Accessibility to capture cursor movement and shortcut keystrokes while you are recording.",
                    buttonTitle: accessibilityButtonTitle,
                    buttonState: accessibilityButtonState
                ) {
                    model.requestOnboardingAccessibilityPermission()
                }
            }
            .padding(.top, 42)

            Text(model.onboardingStatusMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 500, height: 38)
                .padding(.top, 20)

            StudioButton(hitTarget: .rounded(8)) {
                model.completeOnboarding()
            } label: {
                Label("Continue", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 180, height: 40)
                    .foregroundStyle(model.canContinueOnboarding ? Color.white : Color.white.opacity(0.22))
                    .background(
                        model.canContinueOnboarding ? Color.brand : Color.white.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(model.canContinueOnboarding ? Color.brand.opacity(0.45) : Color.white.opacity(0.06))
                    }
            }
            .disabled(!model.canContinueOnboarding)

            Spacer(minLength: 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioBackground)
        .onAppear {
            model.refreshOnboardingPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshOnboardingPermissionStates()
        }
    }

    private var screenRecordingButtonTitle: String {
        switch model.screenRecordingPermissionState {
        case .granted:
            "Screen Recording enabled"
        case .requestAvailable:
            "Allow Screen Recording"
        case .requestAlreadyShown:
            "Open Screen Recording Settings"
        }
    }

    private var screenRecordingButtonState: OnboardingPermissionButtonState {
        switch model.screenRecordingPermissionState {
        case .granted:
            .enabled
        case .requestAvailable:
            .action
        case .requestAlreadyShown:
            .settings
        }
    }

    private var accessibilityButtonTitle: String {
        switch model.accessibilityPermissionState {
        case .granted:
            "Accessibility access enabled"
        case .requestAvailable:
            "Allow Accessibility Access"
        case .requestAlreadyShown:
            "Open Accessibility Settings"
        }
    }

    private var accessibilityButtonState: OnboardingPermissionButtonState {
        switch model.accessibilityPermissionState {
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
        ZStack {
            Circle()
                .stroke(Color.brand.opacity(0.28), lineWidth: 8)
                .frame(width: 58, height: 58)
            Circle()
                .stroke(Color.brand, lineWidth: 6)
                .frame(width: 46, height: 46)
            Circle()
                .fill(Color.studioBackground)
                .frame(width: 30, height: 30)
        }
        .accessibilityHidden(true)
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
            Color.brand.opacity(0.98)
        case .enabled:
            Color(red: 0.35, green: 1.0, blue: 0.58)
        }
    }

    private var backgroundColor: Color {
        switch buttonState {
        case .action, .settings:
            Color.white.opacity(0.075)
        case .enabled:
            Color(red: 0.07, green: 0.20, blue: 0.13)
        }
    }

    private var borderColor: Color {
        switch buttonState {
        case .action, .settings:
            Color.white.opacity(0.12)
        case .enabled:
            Color(red: 0.18, green: 0.50, blue: 0.30)
        }
    }
}
