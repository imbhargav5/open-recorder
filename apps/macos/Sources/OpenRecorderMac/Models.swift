import Foundation

struct CaptureArea: Codable, Hashable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var displayID: UInt32? = nil
}

enum RecordingPhase: String, Codable, CaseIterable, Identifiable {
    case idle
    case countingDown
    case starting
    case recording
    case stopping
    case interrupted

    var id: String { rawValue }
}

struct CaptureDeviceInfo: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var isDefault: Bool
}

struct RecordingCaptureOptions: Codable, Hashable {
    var includeMicrophone: Bool
    var microphoneDeviceID: String?
    var includeSystemAudio: Bool
    var includeCamera: Bool
    var cameraDeviceID: String?
    var showCursor: Bool
    var showClicks: Bool
}

enum CaptureSourceKind: String, Codable, CaseIterable, Identifiable {
    case display
    case window
    case area

    var id: String { rawValue }

    var label: String {
        switch self {
        case .display: "Display"
        case .window: "Window"
        case .area: "Area"
        }
    }
}

enum CaptureSourceType: String, CaseIterable, Identifiable, Hashable {
    case screen
    case window
    case area

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen: "Screen"
        case .window: "Window"
        case .area: "Area"
        }
    }

    var symbolName: String {
        switch self {
        case .screen: "display"
        case .window: "macwindow"
        case .area: "rectangle.dashed"
        }
    }

    var sourceKind: CaptureSourceKind {
        switch self {
        case .screen: .display
        case .window: .window
        case .area: .area
        }
    }
}

struct CaptureSource: Identifiable, Codable, Hashable {
    var id: String
    var kind: CaptureSourceKind
    var name: String
    var subtitle: String
    var displayIndex: Int?
    var displayID: UInt32?
    var windowID: UInt32?
    var area: CaptureArea?
    var thumbnailData: Data?
    var ownerBundleID: String? = nil
    var ownerName: String? = nil
}

struct AppPaths: Codable, Equatable {
    var recordingsDir: String
    var screenshotsDir: String
    var projectsDir: String
    var supportDir: String
}

struct PreparedFile: Codable {
    var path: String
}

struct ForgetProjectResult: Codable {
    var removed: Bool
}

struct ProjectSummary: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var path: String
    var recordingPath: String?
    var screenshotPath: String? = nil
    var sourceName: String?
    var createdAt: String
    var updatedAt: String
    var lastOpenedAt: String
    var missing: Bool

    var mediaKind: EditorMediaKind {
        screenshotPath == nil ? .video : .screenshot
    }

    var mediaPath: String? {
        screenshotPath ?? recordingPath
    }
}

struct ProjectDocument: Codable {
    var schemaVersion: Int
    var title: String
    var recordingPath: String?
    var screenshotPath: String?
    var sourceName: String?
    var createdAt: String
    var updatedAt: String
    var editorState: ProjectEditorState?
    var recordingSession: RecordingSession?

    var mediaKind: EditorMediaKind? {
        if screenshotPath != nil {
            return .screenshot
        }
        if recordingPath != nil {
            return .video
        }
        return nil
    }
}

struct ProjectEditorState: Codable, Equatable {
    var timelineEdits: TimelineEditSnapshot
    var video: ProjectVideoEditorState?
    var screenshot: ScreenshotEditorState?

    static let empty = ProjectEditorState(timelineEdits: .empty, video: nil, screenshot: nil)

    init(
        timelineEdits: TimelineEditSnapshot = .empty,
        video: ProjectVideoEditorState? = nil,
        screenshot: ScreenshotEditorState? = nil
    ) {
        self.timelineEdits = timelineEdits
        self.video = video
        self.screenshot = screenshot
    }

    private enum CodingKeys: String, CodingKey {
        case timelineEdits
        case video
        case screenshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timelineEdits = try container.decodeIfPresent(TimelineEditSnapshot.self, forKey: .timelineEdits) ?? .empty
        video = try container.decodeIfPresent(ProjectVideoEditorState.self, forKey: .video)
        screenshot = try container.decodeIfPresent(ScreenshotEditorState.self, forKey: .screenshot)
    }
}

struct ProjectVideoEditorState: Codable, Equatable, Hashable {
    var background: BackgroundStyle
    var padding: Double
    var borderRadius: Double
    var shadow: Double
    var backgroundBlur: Double
    var inset: Double
    var insetColor: SerializableColor
    var insetOpacity: Double
    var insetBalance: VideoInsetBalance
    var cropSelection: VideoCropSelection
    var cursorOverlay: CursorOverlaySettings
    var facecamSettings: FacecamSettings?

    static let `default` = ProjectVideoEditorState()

    init(
        background: BackgroundStyle = BackgroundPresets.default,
        padding: Double = 18,
        borderRadius: Double = 12,
        shadow: Double = 0.35,
        backgroundBlur: Double = 0,
        inset: Double = 0,
        insetColor: SerializableColor = SerializableColor(hex: "#276FAA"),
        insetOpacity: Double = 1,
        insetBalance: VideoInsetBalance = .centered,
        cropSelection: VideoCropSelection = .fullFrame,
        cursorOverlay: CursorOverlaySettings = .default,
        facecamSettings: FacecamSettings? = nil
    ) {
        self.background = background
        self.padding = padding
        self.borderRadius = borderRadius
        self.shadow = shadow
        self.backgroundBlur = backgroundBlur
        self.inset = inset
        self.insetColor = insetColor
        self.insetOpacity = insetOpacity
        self.insetBalance = insetBalance.clamped
        self.cropSelection = cropSelection
        self.cursorOverlay = cursorOverlay.clamped
        self.facecamSettings = facecamSettings
    }

    private enum CodingKeys: String, CodingKey {
        case background
        case padding
        case borderRadius
        case shadow
        case backgroundBlur
        case inset
        case insetColor
        case insetOpacity
        case insetBalance
        case cropSelection
        case cursorOverlay
        case facecamSettings
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = try container.decodeIfPresent(BackgroundStyle.self, forKey: .background) ?? defaults.background
        padding = try container.decodeIfPresent(Double.self, forKey: .padding) ?? defaults.padding
        borderRadius = try container.decodeIfPresent(Double.self, forKey: .borderRadius) ?? defaults.borderRadius
        shadow = try container.decodeIfPresent(Double.self, forKey: .shadow) ?? defaults.shadow
        backgroundBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? defaults.backgroundBlur
        inset = try container.decodeIfPresent(Double.self, forKey: .inset) ?? defaults.inset
        insetColor = try container.decodeIfPresent(SerializableColor.self, forKey: .insetColor) ?? defaults.insetColor
        insetOpacity = try container.decodeIfPresent(Double.self, forKey: .insetOpacity) ?? defaults.insetOpacity
        insetBalance = (try container.decodeIfPresent(VideoInsetBalance.self, forKey: .insetBalance) ?? defaults.insetBalance).clamped
        cropSelection = try container.decodeIfPresent(VideoCropSelection.self, forKey: .cropSelection) ?? defaults.cropSelection
        cursorOverlay = (try container.decodeIfPresent(CursorOverlaySettings.self, forKey: .cursorOverlay) ?? defaults.cursorOverlay).clamped
        facecamSettings = try container.decodeIfPresent(FacecamSettings.self, forKey: .facecamSettings)
    }
}

enum EditorMediaKind: String, Codable, Hashable {
    case video
    case screenshot

    var titleIconSystemName: String {
        switch self {
        case .video: "video.fill"
        case .screenshot: "photo.fill"
        }
    }

    private var filenameExtensions: Set<String> {
        switch self {
        case .video: ["mov", "mp4", "m4v"]
        case .screenshot: ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"]
        }
    }

    func displayTitle(for url: URL) -> String {
        let title = url.deletingPathExtension().lastPathComponent
        return title.isEmpty ? url.lastPathComponent : title
    }

    func displayTitle(for title: String, fallbackURL: URL? = nil) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmedTitle.isEmpty ? fallbackURL.map(displayTitle(for:)) : trimmedTitle
        guard let candidate, !candidate.isEmpty else {
            return "Open Recorder Editor"
        }

        let candidateURL = URL(fileURLWithPath: candidate)
        guard filenameExtensions.contains(candidateURL.pathExtension.lowercased()) else {
            return candidate
        }

        let titleWithoutExtension = candidateURL.deletingPathExtension().lastPathComponent
        return titleWithoutExtension.isEmpty ? candidate : titleWithoutExtension
    }

    func supports(_ url: URL) -> Bool {
        filenameExtensions.contains(url.pathExtension.lowercased())
    }
}

struct EditorSession: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: EditorMediaKind
    var path: String
    var projectPath: String?
    var title: String
    var recordingSession: RecordingSession?
    var timelineEditSnapshot: TimelineEditSnapshot?
    var videoEditorState: ProjectVideoEditorState?
    var screenshotEditorState: ScreenshotEditorState?

    init(
        kind: EditorMediaKind,
        url: URL,
        title: String? = nil,
        id: UUID = UUID(),
        projectPath: String? = nil,
        recordingSession: RecordingSession? = nil,
        timelineEditSnapshot: TimelineEditSnapshot? = nil,
        videoEditorState: ProjectVideoEditorState? = nil,
        screenshotEditorState: ScreenshotEditorState? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = url.path
        self.projectPath = projectPath
        self.title = title ?? kind.displayTitle(for: url)
        self.recordingSession = recordingSession
        self.timelineEditSnapshot = timelineEditSnapshot
        self.videoEditorState = videoEditorState
        self.screenshotEditorState = screenshotEditorState
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var displayTitle: String {
        kind.displayTitle(for: title, fallbackURL: url)
    }
}

enum FacecamAnchor: String, CaseIterable, Identifiable, Codable, Hashable {
    case topLeft = "top-left"
    case top = "top"
    case topRight = "top-right"
    case left
    case center
    case right
    case bottomLeft = "bottom-left"
    case bottom
    case bottomRight = "bottom-right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .top: "Top"
        case .topRight: "Top right"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom right"
        }
    }

    static func resolve(_ rawValue: String) -> FacecamAnchor {
        FacecamAnchor(rawValue: rawValue) ?? .bottomRight
    }
}

struct FacecamSettings: Codable, Hashable {
    var enabled: Bool
    var shape: String
    var size: Double
    var cornerRadius: Double
    var borderWidth: Double
    var borderColor: String
    var margin: Double
    var anchor: String

    var clamped: FacecamSettings {
        FacecamSettings(
            enabled: enabled,
            shape: normalizedShape,
            size: max(12, min(size, 40)),
            cornerRadius: max(0, min(cornerRadius, 100)),
            borderWidth: max(0, min(borderWidth, 16)),
            borderColor: normalizedBorderColor,
            margin: max(0, min(margin, 12)),
            anchor: FacecamAnchor.resolve(anchor).rawValue
        )
    }

    var resolvedAnchor: FacecamAnchor {
        FacecamAnchor.resolve(anchor)
    }

    var normalizedShape: String {
        let value = shape.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? "circle" : value
    }

    var isCircle: Bool {
        normalizedShape == "circle"
    }

    private var normalizedBorderColor: String {
        let value = borderColor.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "#FFFFFF" : value
    }
}

struct RecordingSession: Codable, Hashable {
    var screenVideoPath: String
    var facecamVideoPath: String?
    var facecamOffsetMs: Int?
    var facecamSettings: FacecamSettings?
    var sourceName: String?
    var showCursorOverlay: Bool
    var cursorTelemetryPath: String?

    var hasRecordedCamera: Bool {
        guard let facecamVideoPath else { return false }
        return !facecamVideoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

typealias CursorStyleID = String

enum CursorStyleCategory: String, CaseIterable, Hashable, Identifiable {
    case system
    case touch
    case emphasis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .touch: "Touch"
        case .emphasis: "Emphasis"
        }
    }
}

enum CursorHotspotRule: Hashable {
    case topLeft
    case center
    case proportional(x: Double, y: Double)
}

enum CursorRenderKind: Hashable {
    case arrow(fill: SerializableColor, stroke: SerializableColor, shadow: SerializableColor)
    case hand(fill: SerializableColor, stroke: SerializableColor, shadow: SerializableColor)
    case iBeam(fill: SerializableColor, stroke: SerializableColor, shadow: SerializableColor)
    case dot(fill: SerializableColor, stroke: SerializableColor, shadow: SerializableColor, fillsShape: Bool)
    case ring(stroke: SerializableColor, shadow: SerializableColor)
    case spotlight(fill: SerializableColor, stroke: SerializableColor, shadow: SerializableColor)
    case rasterAsset(name: String, hotspot: CursorHotspotRule)
}

struct CursorStyleDefinition: Identifiable, Hashable {
    var id: CursorStyleID
    var title: String
    var category: CursorStyleCategory
    var renderKind: CursorRenderKind
    var hotspot: CursorHotspotRule
    var defaultScale: Double
    var supportsRecordedTypeOverride: Bool
}

enum CursorStyleRegistry {
    static let defaultStyleID: CursorStyleID = "system.white"

    static let styles: [CursorStyleDefinition] = [
        CursorStyleDefinition(
            id: "system.white",
            title: "System White",
            category: .system,
            renderKind: .arrow(
                fill: SerializableColor(hex: "#FFFFFF"),
                stroke: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.62),
                shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.16)
            ),
            hotspot: .topLeft,
            defaultScale: 1,
            supportsRecordedTypeOverride: true
        ),
        CursorStyleDefinition(
            id: "system.black",
            title: "System Black",
            category: .system,
            renderKind: .arrow(
                fill: SerializableColor(hex: "#1F2023"),
                stroke: SerializableColor(red: 1, green: 1, blue: 1, alpha: 0.68),
                shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.14)
            ),
            hotspot: .topLeft,
            defaultScale: 1,
            supportsRecordedTypeOverride: true
        ),
        CursorStyleDefinition(
            id: "system.hand",
            title: "Hand",
            category: .system,
            renderKind: .hand(
                fill: SerializableColor(hex: "#FFFFFF"),
                stroke: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.62),
                shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.16)
            ),
            hotspot: .proportional(x: 0.54, y: 0.02),
            defaultScale: 1,
            supportsRecordedTypeOverride: false
        ),
        CursorStyleDefinition(
            id: "system.ibeam",
            title: "I-Beam",
            category: .system,
            renderKind: .iBeam(
                fill: SerializableColor(hex: "#FFFFFF"),
                stroke: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.56),
                shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.12)
            ),
            hotspot: .center,
            defaultScale: 1,
            supportsRecordedTypeOverride: false
        ),
        CursorStyleDefinition(
            id: "touch.dot",
            title: "Touch Dot",
            category: .touch,
            renderKind: .dot(
                fill: SerializableColor(hex: "#FFFFFF"),
                stroke: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.54),
                shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.14),
                fillsShape: true
            ),
            hotspot: .center,
            defaultScale: 1.08,
            supportsRecordedTypeOverride: false
        ),
        CursorStyleDefinition(
            id: "highlight.ring",
            title: "Highlight Ring",
            category: .emphasis,
            renderKind: .ring(
                stroke: SerializableColor(hex: "#FFFFFF", alpha: 0.92),
                shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.34)
            ),
            hotspot: .center,
            defaultScale: 1.55,
            supportsRecordedTypeOverride: false
        ),
        CursorStyleDefinition(
            id: "spotlight",
            title: "Spotlight",
            category: .emphasis,
            renderKind: .spotlight(
                fill: SerializableColor(hex: "#FFFFFF", alpha: 0.20),
                stroke: SerializableColor(hex: "#FFFFFF", alpha: 0.84),
                shadow: SerializableColor(red: 0, green: 0, blue: 0, alpha: 0.38)
            ),
            hotspot: .center,
            defaultScale: 1.85,
            supportsRecordedTypeOverride: false
        )
    ]

    static func definition(for id: CursorStyleID) -> CursorStyleDefinition? {
        styles.first { $0.id == id }
    }

    static func resolvedStyleID(_ id: CursorStyleID?) -> CursorStyleID {
        guard let id, definition(for: id) != nil else {
            return defaultStyleID
        }
        return id
    }

    static func definitions(in category: CursorStyleCategory) -> [CursorStyleDefinition] {
        styles.filter { $0.category == category }
    }
}

enum CursorClickEffect: String, CaseIterable, Codable, Hashable, Identifiable {
    case none
    case subtleRing
    case ripple

    var id: String { rawValue }
}

enum CursorIdleBehavior: String, CaseIterable, Codable, Hashable, Identifiable {
    case alwaysVisible
    case fadeWhenIdle

    var id: String { rawValue }
}

enum CursorMotionEffect: String, CaseIterable, Codable, Hashable, Identifiable {
    case none
    case subtleLean

    var id: String { rawValue }
}

struct CursorOverlaySettings: Codable, Hashable {
    var isVisible: Bool
    var loops: Bool
    var size: Double
    var smoothing: Double
    var styleID: CursorStyleID
    var clickEffect: CursorClickEffect
    var idleBehavior: CursorIdleBehavior
    var motionEffect: CursorMotionEffect

    static let `default` = CursorOverlaySettings(
        isVisible: true,
        loops: false,
        size: 1,
        smoothing: 0.4
    )

    static let hidden = CursorOverlaySettings(
        isVisible: false,
        loops: false,
        size: 1,
        smoothing: 0.4
    )

    init(
        isVisible: Bool,
        loops: Bool,
        size: Double,
        smoothing: Double,
        styleID: CursorStyleID = CursorStyleRegistry.defaultStyleID,
        clickEffect: CursorClickEffect = .subtleRing,
        idleBehavior: CursorIdleBehavior = .alwaysVisible,
        motionEffect: CursorMotionEffect = .none
    ) {
        self.isVisible = isVisible
        self.loops = loops
        self.size = max(1, min(size, 8))
        self.smoothing = max(0, min(smoothing, 2))
        self.styleID = CursorStyleRegistry.resolvedStyleID(styleID)
        self.clickEffect = clickEffect
        self.idleBehavior = idleBehavior
        self.motionEffect = motionEffect
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible
        case loops
        case size
        case smoothing
        case styleID
        case style
        case variant
        case clickEffect
        case idleBehavior
        case motionEffect
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStyleID = CursorStyleRegistry.resolvedStyleID(
            try container.decodeIfPresent(String.self, forKey: .styleID)
        )

        self.init(
            isVisible: try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? defaults.isVisible,
            loops: try container.decodeIfPresent(Bool.self, forKey: .loops) ?? defaults.loops,
            size: try container.decodeIfPresent(Double.self, forKey: .size) ?? defaults.size,
            smoothing: try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? defaults.smoothing,
            styleID: decodedStyleID,
            clickEffect: (try? container.decodeIfPresent(CursorClickEffect.self, forKey: .clickEffect)) ?? defaults.clickEffect,
            idleBehavior: (try? container.decodeIfPresent(CursorIdleBehavior.self, forKey: .idleBehavior)) ?? defaults.idleBehavior,
            motionEffect: (try? container.decodeIfPresent(CursorMotionEffect.self, forKey: .motionEffect)) ?? defaults.motionEffect
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(loops, forKey: .loops)
        try container.encode(size, forKey: .size)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(styleID, forKey: .styleID)
        try container.encode(clickEffect, forKey: .clickEffect)
        try container.encode(idleBehavior, forKey: .idleBehavior)
        try container.encode(motionEffect, forKey: .motionEffect)
    }

    var clamped: CursorOverlaySettings {
        CursorOverlaySettings(
            isVisible: isVisible,
            loops: loops,
            size: size,
            smoothing: smoothing,
            styleID: styleID,
            clickEffect: clickEffect,
            idleBehavior: idleBehavior,
            motionEffect: motionEffect
        )
    }
}

func defaultFacecamSettings(enabled: Bool) -> FacecamSettings {
    FacecamSettings(
        enabled: enabled,
        shape: "circle",
        size: 22,
        cornerRadius: 24,
        borderWidth: 4,
        borderColor: "#FFFFFF",
        margin: 4,
        anchor: "bottom-right"
    )
}

enum AppSection: String, CaseIterable, Identifiable {
    case capture
    case projects
    case editor
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "Capture"
        case .projects: "Projects"
        case .editor: "Editor"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .capture: "record.circle"
        case .projects: "folder"
        case .editor: "slider.horizontal.3"
        case .settings: "gearshape"
        }
    }
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case recording
    case screenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: "Recording"
        case .screenshot: "Screenshot"
        }
    }
}

enum CaptureFlow: String, CaseIterable, Identifiable {
    case choice
    case screenshotSetup
    case recordingSetup
    case recording

    var id: String { rawValue }
}

enum NativeWindowCommandAction: Equatable {
    case showHUD
    case hideHUD
    case showOnboarding
    case finishOnboarding
    case showRecordingSetup
    case showScreenRecordingSetup
    case hideRecordingSetup
    case hideAppWindowsForCapture
    case showSourceSelector
    case showMicrophoneSelector
    case showCameraSelector
    case showAreaSelector
    case showStudio
    case closeCaptureSetup
    case closeSourceSelector
    case closeMicrophoneSelector
    case closeCameraSelector
    case closeAreaSelector
}

struct NativeWindowCommand: Identifiable {
    var id = UUID()
    var action: NativeWindowCommandAction
    var editorSession: EditorSession?
}

struct HealthPayload: Codable {
    var service: String
    var version: String
    var platform: String
}

func timestampedFileName(prefix: String, extension fileExtension: String, date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    return "\(prefix)-\(formatter.string(from: date)).\(fileExtension)"
}
