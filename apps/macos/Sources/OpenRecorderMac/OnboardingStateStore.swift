import Foundation

struct OnboardingStateStore {
    var isCompleted: @MainActor () -> Bool
    var setCompleted: @MainActor (Bool) -> Void

    @MainActor
    static let live = OnboardingStateStore(
        isCompleted: {
            UserDefaults.standard.bool(forKey: completedDefaultsKey)
        },
        setCompleted: { value in
            UserDefaults.standard.set(value, forKey: completedDefaultsKey)
        }
    )

    private static let completedDefaultsKey = "onboarding.completed.v1"
}
