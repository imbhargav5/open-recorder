import AppKit
import Combine
import SwiftUI

enum OnboardingWindowMetrics {
    static let width: CGFloat = 680
    static let height: CGFloat = 560
}

struct OnboardingView: View {
    var driver: OnboardingDriver
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

            Text("Screen Recording is required. Accessibility is an optional enhancement for shortcuts and cursor details.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .multilineTextAlignment(.center)

            VStack(spacing: 26) {
                OnboardingPermissionRow(
                    title: "Screen Recording Permission",
                    description: "Open Recorder needs to capture video of your screen. You might need to restart the app after granting it.",
                    requirement: .required,
                    buttonTitle: screenRecordingButtonTitle,
                    buttonState: screenRecordingButtonState
                ) {
                    driver.send(.screenPermissionButtonTapped)
                }

                OnboardingPermissionRow(
                    title: "Accessibility Permission",
                    description: "Optional: lets Open Recorder capture shortcut keystrokes and additional cursor details while recording.",
                    requirement: .optional,
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

            StudioButton(hitTarget: .rounded(Theme.radiusMd)) {
                driver.send(.continueRequested)
            } label: {
                Label("Continue", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 180, height: 40)
                    .foregroundStyle(driver.state.canContinue ? Color.white : Theme.fgSubtle)
                    .background(
                        driver.state.canContinue ? Theme.accent : Theme.surfaceControl,
                        in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                            .stroke(driver.state.canContinue ? Theme.accent.opacity(0.45) : Theme.border)
                    }
            }
            .disabled(!driver.state.canContinue)

            Spacer(minLength: 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .onAppear {
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

private enum OnboardingPermissionRequirement {
    case required
    case optional

    var title: String {
        switch self {
        case .required: "Required"
        case .optional: "Optional"
        }
    }
}

private struct OnboardingPermissionRow: View {
    var title: String
    var description: String
    var requirement: OnboardingPermissionRequirement
    var buttonTitle: String
    var buttonState: OnboardingPermissionButtonState
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 34) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.90))
                    Text(requirement.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Theme.borderSubtle, lineWidth: 1)
                        }
                }

                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.fgSubtle)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 240, alignment: .leading)

            if buttonState == .enabled {
                permissionStatusLabel
            } else {
                StudioButton(hitTarget: .rounded(Theme.radiusMd), action: action) {
                    permissionActionLabel
                }
            }
        }
        .frame(width: 516, alignment: .leading)
    }

    private var permissionActionLabel: some View {
        Text(buttonTitle)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: 242, height: 36)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private var permissionStatusLabel: some View {
        Label(buttonTitle, systemImage: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: 242, height: 36)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .accessibilityLabel("\(buttonTitle), \(requirement.title)")
    }

    private var foregroundColor: Color {
        switch buttonState {
        case .action, .settings:
            Theme.accent
        case .enabled:
            Color.white.opacity(0.94)
        }
    }

    private var backgroundColor: Color {
        switch buttonState {
        case .action, .settings:
            Theme.surfaceControl
        case .enabled:
            Theme.accent.opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch buttonState {
        case .action, .settings:
            Theme.border
        case .enabled:
            Theme.accent.opacity(0.42)
        }
    }
}
