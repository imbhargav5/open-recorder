import Foundation

struct ScreenshotAppearancePreferences: Codable, Equatable {
    var canvasAspect: VideoPreviewAspectPreset
    var background: BackgroundStyle
    var padding: Double
    var backgroundRoundness: Double
    var backgroundShadow: Double
    var imageRoundness: Double
    var imageShadow: Double

    static let `default` = ScreenshotAppearancePreferences(state: .default)

    init(state: ScreenshotEditorState) {
        canvasAspect = state.canvasAspect
        background = state.background
        padding = state.padding
        backgroundRoundness = state.backgroundRoundness
        backgroundShadow = state.backgroundShadow
        imageRoundness = state.imageRoundness
        imageShadow = state.imageShadow
    }

    func applying(to state: ScreenshotEditorState) -> ScreenshotEditorState {
        var next = state
        next.canvasAspect = canvasAspect
        next.background = background
        next.padding = padding
        next.backgroundRoundness = backgroundRoundness
        next.backgroundShadow = backgroundShadow
        next.imageRoundness = imageRoundness
        next.imageShadow = imageShadow
        return next
    }
}

struct VideoAppearancePreferences: Codable, Equatable {
    var canvasAspect: VideoPreviewAspectPreset
    var background: BackgroundStyle
    var padding: Double
    var borderRadius: Double
    var shadow: Double
    var backgroundBlur: Double
    var inset: Double
    var insetColor: SerializableColor
    var insetOpacity: Double
    var insetBalance: VideoInsetBalance

    static let `default` = VideoAppearancePreferences(state: .default)

    init(state: ProjectVideoEditorState) {
        canvasAspect = state.canvasAspect
        background = state.background
        padding = state.padding
        borderRadius = state.borderRadius
        shadow = state.shadow
        backgroundBlur = state.backgroundBlur
        inset = state.inset
        insetColor = state.insetColor
        insetOpacity = state.insetOpacity
        insetBalance = state.insetBalance
    }

    func applying(to state: ProjectVideoEditorState) -> ProjectVideoEditorState {
        var next = state
        next.canvasAspect = canvasAspect
        next.background = background
        next.padding = padding
        next.borderRadius = borderRadius
        next.shadow = shadow
        next.backgroundBlur = backgroundBlur
        next.inset = inset
        next.insetColor = insetColor
        next.insetOpacity = insetOpacity
        next.insetBalance = insetBalance.clamped
        return next
    }
}

@MainActor
struct EditorAppearancePreferencesStore {
    static let screenshotDefaultsKey = "editor.appearance.screenshot.v1"
    static let videoDefaultsKey = "editor.appearance.video.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var live: EditorAppearancePreferencesStore {
        EditorAppearancePreferencesStore(defaults: .standard)
    }

    static func ephemeral() -> EditorAppearancePreferencesStore {
        let suiteName = "OpenRecorder.EditorAppearance.\(UUID().uuidString)"
        return EditorAppearancePreferencesStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    func loadScreenshot() -> ScreenshotAppearancePreferences {
        guard let data = defaults.data(forKey: Self.screenshotDefaultsKey),
              var preferences = try? JSONDecoder().decode(ScreenshotAppearancePreferences.self, from: data) else {
            return .default
        }
        if Self.repairMissingCustomBackground(&preferences.background, fallback: ScreenshotAppearancePreferences.default.background) {
            saveScreenshot(preferences)
        }
        return preferences
    }

    func saveScreenshot(_ preferences: ScreenshotAppearancePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.screenshotDefaultsKey)
    }

    func loadVideo() -> VideoAppearancePreferences {
        guard let data = defaults.data(forKey: Self.videoDefaultsKey),
              var preferences = try? JSONDecoder().decode(VideoAppearancePreferences.self, from: data) else {
            return .default
        }
        if Self.repairMissingCustomBackground(&preferences.background, fallback: VideoAppearancePreferences.default.background) {
            saveVideo(preferences)
        }
        return preferences
    }

    func saveVideo(_ preferences: VideoAppearancePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.videoDefaultsKey)
    }

    private static func repairMissingCustomBackground(
        _ background: inout BackgroundStyle,
        fallback: BackgroundStyle
    ) -> Bool {
        guard case .wallpaper(let preset) = background,
              let customURL = preset.customURL,
              !FileManager.default.isReadableFile(atPath: customURL.path) else {
            return false
        }
        background = fallback
        return true
    }
}
