import Foundation

struct RecordingPreferences: Equatable {
    var createsZoomsAutomatically: Bool
    var autoZoomAnimationPreset: TimelineZoomAnimationPreset
    var shortcuts: ShortcutPreferences = .defaultPreferences

    init(
        createsZoomsAutomatically: Bool = true,
        autoZoomAnimationPreset: TimelineZoomAnimationPreset = .balanced,
        shortcuts: ShortcutPreferences = .defaultPreferences
    ) {
        self.createsZoomsAutomatically = createsZoomsAutomatically
        self.autoZoomAnimationPreset = autoZoomAnimationPreset
        self.shortcuts = shortcuts
    }
}

@MainActor
struct RecordingPreferencesStore {
    private static let createsZoomsAutomaticallyKey = "recording.createZoomsAutomatically"
    private static let autoZoomAnimationPresetKey = "recording.autoZoomAnimationPreset"
    private static let shortcutsKey = "recording.shortcuts"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RecordingPreferences {
        let shortcuts: ShortcutPreferences
        if let data = defaults.data(forKey: Self.shortcutsKey),
           let decoded = try? JSONDecoder().decode(ShortcutPreferences.self, from: data) {
            shortcuts = decoded
        } else {
            shortcuts = .defaultPreferences
        }

        return RecordingPreferences(
            createsZoomsAutomatically: defaults.object(forKey: Self.createsZoomsAutomaticallyKey) as? Bool ?? true,
            autoZoomAnimationPreset: TimelineZoomAnimationPreset.storedValue(
                defaults.string(forKey: Self.autoZoomAnimationPresetKey)
            ),
            shortcuts: shortcuts
        )
    }

    func setCreatesZoomsAutomatically(_ value: Bool) {
        defaults.set(value, forKey: Self.createsZoomsAutomaticallyKey)
    }

    func setAutoZoomAnimationPreset(_ preset: TimelineZoomAnimationPreset) {
        defaults.set(preset.rawValue, forKey: Self.autoZoomAnimationPresetKey)
    }

    func setShortcuts(_ shortcuts: ShortcutPreferences) {
        if let data = try? JSONEncoder().encode(shortcuts) {
            defaults.set(data, forKey: Self.shortcutsKey)
        }
    }
}
