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

enum CaptureSourceType: String, CaseIterable, Identifiable {
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

struct ProjectSummary: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var path: String
    var recordingPath: String?
    var sourceName: String?
    var createdAt: String
    var updatedAt: String
    var lastOpenedAt: String
    var missing: Bool
}

struct ProjectDocument: Codable {
    var schemaVersion: Int
    var title: String
    var recordingPath: String?
    var sourceName: String?
    var createdAt: String
    var updatedAt: String
    var editorState: ProjectEditorState?
}

struct ProjectEditorState: Codable, Equatable {
    var timelineEdits: TimelineEditSnapshot
    var video: ProjectVideoEditorState?

    static let empty = ProjectEditorState(timelineEdits: .empty, video: nil)

    init(timelineEdits: TimelineEditSnapshot = .empty, video: ProjectVideoEditorState? = nil) {
        self.timelineEdits = timelineEdits
        self.video = video
    }

    private enum CodingKeys: String, CodingKey {
        case timelineEdits
        case video
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timelineEdits = try container.decodeIfPresent(TimelineEditSnapshot.self, forKey: .timelineEdits) ?? .empty
        video = try container.decodeIfPresent(ProjectVideoEditorState.self, forKey: .video)
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

    init(
        kind: EditorMediaKind,
        url: URL,
        title: String? = nil,
        id: UUID = UUID(),
        projectPath: String? = nil,
        recordingSession: RecordingSession? = nil,
        timelineEditSnapshot: TimelineEditSnapshot? = nil,
        videoEditorState: ProjectVideoEditorState? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = url.path
        self.projectPath = projectPath
        self.title = title ?? kind.displayTitle(for: url)
        self.recordingSession = recordingSession
        self.timelineEditSnapshot = timelineEditSnapshot
        self.videoEditorState = videoEditorState
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

enum CursorStyle: String, CaseIterable, Codable, Hashable, Identifiable {
    case arrow
    case macOSBlackArrow
    case outlineArrow
    case handPointer
    case iBeam
    case dotPointer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: "Arrow"
        case .macOSBlackArrow: "macOS Black"
        case .outlineArrow: "Outline"
        case .handPointer: "Hand"
        case .iBeam: "I-Beam"
        case .dotPointer: "Dot"
        }
    }

    var defaultVariant: CursorVariant {
        .standard
    }

    var supportedVariants: [CursorVariant] {
        CursorVariant.allCases
    }

    func resolvedVariant(_ variant: CursorVariant) -> CursorVariant {
        supportedVariants.contains(variant) ? variant : defaultVariant
    }
}

enum CursorVariant: String, CaseIterable, Codable, Hashable, Identifiable {
    case standard
    case slim
    case soft
    case bold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .slim: "Slim"
        case .soft: "Soft"
        case .bold: "Bold"
        }
    }

    static func resolve(_ rawValue: String?) -> CursorVariant? {
        guard let rawValue else { return nil }
        if let variant = CursorVariant(rawValue: rawValue) {
            return variant
        }

        switch rawValue {
        case "light":
            return .standard
        case "dark":
            return .slim
        case "accent":
            return .soft
        case "highContrast":
            return .bold
        default:
            return nil
        }
    }
}

struct CursorOverlaySettings: Codable, Hashable {
    var isVisible: Bool
    var loops: Bool
    var size: Double
    var smoothing: Double
    var style: CursorStyle
    var variant: CursorVariant

    static let `default` = CursorOverlaySettings(
        isVisible: true,
        loops: false,
        size: 1,
        smoothing: 0.4,
        style: .arrow,
        variant: .standard
    )

    static let hidden = CursorOverlaySettings(
        isVisible: false,
        loops: false,
        size: 1,
        smoothing: 0.4,
        style: .arrow,
        variant: .standard
    )

    init(
        isVisible: Bool,
        loops: Bool,
        size: Double,
        smoothing: Double,
        style: CursorStyle = .arrow,
        variant: CursorVariant = .standard
    ) {
        self.isVisible = isVisible
        self.loops = loops
        self.size = max(1, min(size, 8))
        self.smoothing = max(0, min(smoothing, 2))
        self.style = style
        self.variant = style.resolvedVariant(variant)
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible
        case loops
        case size
        case smoothing
        case style
        case variant
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStyle = try container.decodeIfPresent(String.self, forKey: .style)
            .flatMap(CursorStyle.init(rawValue:)) ?? defaults.style
        let decodedVariant = CursorVariant.resolve(try container.decodeIfPresent(String.self, forKey: .variant))
            ?? decodedStyle.defaultVariant

        self.init(
            isVisible: try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? defaults.isVisible,
            loops: try container.decodeIfPresent(Bool.self, forKey: .loops) ?? defaults.loops,
            size: try container.decodeIfPresent(Double.self, forKey: .size) ?? defaults.size,
            smoothing: try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? defaults.smoothing,
            style: decodedStyle,
            variant: decodedVariant
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(loops, forKey: .loops)
        try container.encode(size, forKey: .size)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(style.rawValue, forKey: .style)
        try container.encode(variant.rawValue, forKey: .variant)
    }

    var clamped: CursorOverlaySettings {
        CursorOverlaySettings(
            isVisible: isVisible,
            loops: loops,
            size: size,
            smoothing: smoothing,
            style: style,
            variant: variant
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

enum HUDPresentationState: Hashable {
    case visible
    case hidden

    var isVisible: Bool {
        self == .visible
    }
}

enum HUDPhase: Hashable {
    case idle
    case choosingMode
    case choosingSourceType(CaptureMode)
    case screenSelecting(CaptureMode)
    case selectingSource(CaptureMode)
    case ready(CaptureMode, CaptureSource)
    case areaSelecting(CaptureMode)
    case countingDownRecording(CaptureSource)
    case startingRecording(CaptureSource)
    case recording(CaptureSource)
    case stoppingRecording(CaptureSource)
    case capturingScreenshot(CaptureSource)
}

struct HUDState: Hashable {
    var phase: HUDPhase
    var presentation: HUDPresentationState

    init(phase: HUDPhase = .choosingMode, presentation: HUDPresentationState = .visible) {
        self.phase = phase
        self.presentation = presentation
    }

    static var idle: HUDState {
        HUDState(phase: .idle)
    }

    static var choosingMode: HUDState {
        HUDState(phase: .choosingMode)
    }

    static func choosingSourceType(_ mode: CaptureMode) -> HUDState {
        HUDState(phase: .choosingSourceType(mode))
    }

    static func screenSelecting(_ mode: CaptureMode) -> HUDState {
        HUDState(phase: .screenSelecting(mode))
    }

    static func selectingSource(_ mode: CaptureMode) -> HUDState {
        HUDState(phase: .selectingSource(mode))
    }

    static func ready(_ mode: CaptureMode, _ source: CaptureSource) -> HUDState {
        HUDState(phase: .ready(mode, source))
    }

    static func areaSelecting(_ mode: CaptureMode) -> HUDState {
        HUDState(phase: .areaSelecting(mode))
    }

    static func countingDownRecording(_ source: CaptureSource) -> HUDState {
        HUDState(phase: .countingDownRecording(source))
    }

    static func startingRecording(_ source: CaptureSource) -> HUDState {
        HUDState(phase: .startingRecording(source))
    }

    static func recording(_ source: CaptureSource) -> HUDState {
        HUDState(phase: .recording(source))
    }

    static func stoppingRecording(_ source: CaptureSource) -> HUDState {
        HUDState(phase: .stoppingRecording(source))
    }

    static func capturingScreenshot(_ source: CaptureSource) -> HUDState {
        HUDState(phase: .capturingScreenshot(source))
    }

    func withPhase(_ phase: HUDPhase) -> HUDState {
        HUDState(phase: phase, presentation: presentation)
    }

    func withPresentation(_ presentation: HUDPresentationState) -> HUDState {
        HUDState(phase: phase, presentation: presentation)
    }

    var mode: CaptureMode? {
        switch phase {
        case .idle, .choosingMode:
            nil
        case .selectingSource(let mode),
             .choosingSourceType(let mode),
             .screenSelecting(let mode),
             .areaSelecting(let mode):
            mode
        case .ready(let mode, _):
            mode
        case .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording:
            .recording
        case .capturingScreenshot:
            .screenshot
        }
    }

    var source: CaptureSource? {
        switch phase {
        case .ready(_, let source),
             .countingDownRecording(let source),
             .startingRecording(let source),
             .recording(let source),
             .stoppingRecording(let source),
             .capturingScreenshot(let source):
            source
        case .idle,
             .choosingMode,
             .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .areaSelecting:
            nil
        }
    }

    var isCaptureOccupied: Bool {
        switch phase {
        case .idle, .choosingMode:
            false
        case .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .ready,
             .areaSelecting,
             .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording,
             .capturingScreenshot:
            true
        }
    }

    var captureFlow: CaptureFlow {
        switch phase {
        case .idle, .choosingMode:
            .choice
        case .choosingSourceType(let mode),
             .screenSelecting(let mode),
             .selectingSource(let mode),
             .ready(let mode, _),
             .areaSelecting(let mode):
            mode == .screenshot ? .screenshotSetup : .recordingSetup
        case .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording:
            .recording
        case .capturingScreenshot:
            .screenshotSetup
        }
    }
}

enum NativeWindowCommandAction: Equatable {
    case showHUD
    case hideHUD
    case showOnboarding
    case finishOnboarding
    case showRecordingSetup
    case hideRecordingSetup
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

func timestampedFileName(prefix: String, extension fileExtension: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    return "\(prefix)-\(formatter.string(from: Date())).\(fileExtension)"
}
