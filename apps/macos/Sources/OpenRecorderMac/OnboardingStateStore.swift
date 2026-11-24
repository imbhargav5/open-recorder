import Foundation

struct OnboardingStateStore {
    var isCompleted: @MainActor () -> Bool
    var setCompleted: @MainActor (Bool) -> Void
    /// The setup step to resume at, saved before a relaunch or when the window closes mid-setup.
    var savedStep: @MainActor () -> OnboardingStep? = { nil }
    var setSavedStep: @MainActor (OnboardingStep?) -> Void = { _ in }

    @MainActor
    static let live = OnboardingStateStore(
        isCompleted: {
            UserDefaults.standard.bool(forKey: completedDefaultsKey)
        },
        setCompleted: { value in
            UserDefaults.standard.set(value, forKey: completedDefaultsKey)
        },
        savedStep: {
            UserDefaults.standard.string(forKey: stepDefaultsKey).flatMap(OnboardingStep.init(rawValue:))
        },
        setSavedStep: { step in
            if let step {
                UserDefaults.standard.set(step.rawValue, forKey: stepDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: stepDefaultsKey)
            }
        }
    )

    private static let completedDefaultsKey = "onboarding.completed.v1"
    private static let stepDefaultsKey = "onboarding.step.v1"
}
