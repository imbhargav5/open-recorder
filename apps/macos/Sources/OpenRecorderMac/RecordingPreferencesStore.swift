import Foundation

struct RecordingPreferences: Equatable {
    var createsZoomsAutomatically: Bool
    var autoZoomAnimationPreset: TimelineZoomAnimationPreset
    var shortcuts: ShortcutPreferences = .defaultPreferences
    /// Play a synthesised click sound on every mouse button press during recording.
    var mouseClickSoundsEnabled: Bool
    /// Play a soft tap sound on every key-down event during recording.
    var keyboardSoundsEnabled: Bool

    init(
        createsZoomsAutomatically: Bool = true,
        autoZoomAnimationPreset: TimelineZoomAnimationPreset = .balanced,
        shortcuts: ShortcutPreferences = .defaultPreferences,
        mouseClickSoundsEnabled: Bool = false,
        keyboardSoundsEnabled: Bool = false
    ) {
        self.createsZoomsAutomatically = createsZoomsAutomatically
        self.autoZoomAnimationPreset = autoZoomAnimationPreset
        self.shortcuts = shortcuts
        self.mouseClickSoundsEnabled = mouseClickSoundsEnabled
        self.keyboardSoundsEnabled = keyboardSoundsEnabled
    }
}

@MainActor
struct RecordingPreferencesStore {
    private static let createsZoomsAutomaticallyKey = "recording.createZoomsAutomatically"
    private static let autoZoomAnimationPresetKey = "recording.autoZoomAnimationPreset"
    private static let shortcutsKey = "recording.shortcuts"
    private static let mouseClickSoundsKey = "recording.mouseClickSoundsEnabled"
    private static let keyboardSoundsKey = "recording.keyboardSoundsEnabled"

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
            shortcuts: shortcuts,
            mouseClickSoundsEnabled: defaults.object(forKey: Self.mouseClickSoundsKey) as? Bool ?? false,
            keyboardSoundsEnabled: defaults.object(forKey: Self.keyboardSoundsKey) as? Bool ?? false
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

    func setMouseClickSoundsEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.mouseClickSoundsKey)
    }

    func setKeyboardSoundsEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.keyboardSoundsKey)
    }
}

