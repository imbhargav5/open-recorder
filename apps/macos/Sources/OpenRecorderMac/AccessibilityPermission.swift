import ApplicationServices
import Foundation

enum AccessibilityPermissionState: Equatable {
    case granted
    case requestAvailable
    case requestAlreadyShown
}

enum AccessibilityPermissionRequestOutcome: Equatable {
    case granted
    case promptShownWithoutGrant
    case promptAlreadyShown
}

struct AccessibilityPermissionClient {
    var isTrusted: () -> Bool
    var request: () -> Bool
    var hasRequestedPrompt: () -> Bool
    var setRequestedPrompt: (Bool) -> Void

    @MainActor
    static let live = AccessibilityPermissionClient(
        isTrusted: {
            AXIsProcessTrusted()
        },
        request: {
            let options = [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        },
        hasRequestedPrompt: {
            UserDefaults.standard.bool(forKey: promptRequestedDefaultsKey)
        },
        setRequestedPrompt: { value in
            UserDefaults.standard.set(value, forKey: promptRequestedDefaultsKey)
        }
    )

    private static let promptRequestedDefaultsKey = "accessibilityPermissionPromptRequested"
}

@MainActor
final class AccessibilityPermission {
    private enum SessionPromptState {
        case notRequested
        case requested
    }

    private let client: AccessibilityPermissionClient
    private var sessionPromptState: SessionPromptState = .notRequested

    init(client: AccessibilityPermissionClient = .live) {
        self.client = client
    }

    func currentState() -> AccessibilityPermissionState {
        if client.isTrusted() {
            clearPromptState()
            return .granted
        }

        if sessionPromptState == .requested || client.hasRequestedPrompt() {
            return .requestAlreadyShown
        }

        return .requestAvailable
    }

    func requestGrant(allowRepeatedRequest: Bool = false) -> AccessibilityPermissionRequestOutcome {
        let state = currentState()
        switch state {
        case .granted:
            return .granted
        case .requestAlreadyShown:
            guard allowRepeatedRequest else {
                return .promptAlreadyShown
            }
            fallthrough
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
