import Foundation

struct RecordingPreferences: Equatable {
    var createsZoomsAutomatically: Bool
    var autoZoomAnimationPreset: TimelineZoomAnimationPreset
}

@MainActor
struct RecordingPreferencesStore {
    private static let createsZoomsAutomaticallyKey = "recording.createZoomsAutomatically"
    private static let autoZoomAnimationPresetKey = "recording.autoZoomAnimationPreset"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RecordingPreferences {
        RecordingPreferences(
            createsZoomsAutomatically: defaults.object(forKey: Self.createsZoomsAutomaticallyKey) as? Bool ?? true,
            autoZoomAnimationPreset: TimelineZoomAnimationPreset.storedValue(
                defaults.string(forKey: Self.autoZoomAnimationPresetKey)
            )
        )
    }

    func setCreatesZoomsAutomatically(_ value: Bool) {
        defaults.set(value, forKey: Self.createsZoomsAutomaticallyKey)
    }

    func setAutoZoomAnimationPreset(_ preset: TimelineZoomAnimationPreset) {
        defaults.set(preset.rawValue, forKey: Self.autoZoomAnimationPresetKey)
    }
}
