import CoreGraphics
import Foundation

enum ScreenRecordingPermissionState: Equatable {
    case granted
    case requestAvailable
    case requestAlreadyShown
}

enum ScreenRecordingPermissionRequestOutcome: Equatable {
    case granted
    case promptShownWithoutGrant
    case promptAlreadyShown
}

struct ScreenRecordingPermissionClient {
    var preflight: () -> Bool
    var request: () -> Bool
    var hasRequestedPrompt: () -> Bool
    var setRequestedPrompt: (Bool) -> Void

    @MainActor
    static let live = ScreenRecordingPermissionClient(
        preflight: {
            CGPreflightScreenCaptureAccess()
        },
        request: {
            CGRequestScreenCaptureAccess()
        },
        hasRequestedPrompt: {
            UserDefaults.standard.bool(forKey: promptRequestedDefaultsKey)
        },
        setRequestedPrompt: { value in
            UserDefaults.standard.set(value, forKey: promptRequestedDefaultsKey)
        }
    )

    private static let promptRequestedDefaultsKey = "screenRecordingPermissionPromptRequested"
}

@MainActor
final class ScreenRecordingPermission {
    private enum SessionPromptState {
        case notRequested
        case requested
    }

    private let client: ScreenRecordingPermissionClient
    private var sessionPromptState: SessionPromptState = .notRequested

    init(client: ScreenRecordingPermissionClient = .live) {
        self.client = client
    }

    func currentState() -> ScreenRecordingPermissionState {
        if client.preflight() {
            clearPromptState()
            return .granted
        }

        if sessionPromptState == .requested || client.hasRequestedPrompt() {
            return .requestAlreadyShown
        }

        return .requestAvailable
    }

    func requestGrant() -> ScreenRecordingPermissionRequestOutcome {
        switch currentState() {
        case .granted:
            return .granted
        case .requestAlreadyShown:
            return .promptAlreadyShown
        case .requestAvailable:
            sessionPromptState = .requested
            client.setRequestedPrompt(true)

            if client.request() {
                clearPromptState()
                return .granted
            }

            return .promptShownWithoutGrant
        }
    }

    private func clearPromptState() {
        sessionPromptState = .notRequested
        client.setRequestedPrompt(false)
    }
}
