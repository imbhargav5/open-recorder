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

struct ProjectSummary: Codable, Identifiable, Hashable {
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
}

enum EditorMediaKind: String, Codable, Hashable {
    case video
    case screenshot

    var badge: String {
        switch self {
        case .video: "MP4"
        case .screenshot: "PNG"
        }
    }
}

struct EditorSession: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: EditorMediaKind
    var path: String
    var title: String
    var recordingSession: RecordingSession?

    init(
        kind: EditorMediaKind,
        url: URL,
        title: String? = nil,
        id: UUID = UUID(),
        recordingSession: RecordingSession? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = url.path
        self.title = title ?? url.lastPathComponent
        self.recordingSession = recordingSession
    }

    var url: URL {
        URL(fileURLWithPath: path)
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
}

struct RecordingSession: Codable, Hashable {
    var screenVideoPath: String
    var facecamVideoPath: String?
    var facecamOffsetMs: Int?
    var facecamSettings: FacecamSettings?
    var sourceName: String?
    var showCursorOverlay: Bool
    var cursorTelemetryPath: String?
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

enum HUDState: Hashable {
    case idle
    case choosingMode
    case selectingSource(CaptureMode)
    case ready(CaptureMode, CaptureSource)
    case areaSelecting(CaptureMode)
    case startingRecording(CaptureSource)
    case recording(CaptureSource)
    case stoppingRecording(CaptureSource)
    case capturingScreenshot(CaptureSource)

    var mode: CaptureMode? {
        switch self {
        case .idle, .choosingMode:
            nil
        case .selectingSource(let mode),
             .areaSelecting(let mode):
            mode
        case .ready(let mode, _):
            mode
        case .startingRecording,
             .recording,
             .stoppingRecording:
            .recording
        case .capturingScreenshot:
            .screenshot
        }
    }

    var source: CaptureSource? {
        switch self {
        case .ready(_, let source),
             .startingRecording(let source),
             .recording(let source),
             .stoppingRecording(let source),
             .capturingScreenshot(let source):
            source
        case .idle,
             .choosingMode,
             .selectingSource,
             .areaSelecting:
            nil
        }
    }

    var isCaptureOccupied: Bool {
        switch self {
        case .idle, .choosingMode:
            false
        case .selectingSource,
             .ready,
             .areaSelecting,
             .startingRecording,
             .recording,
             .stoppingRecording,
             .capturingScreenshot:
            true
        }
    }

    var captureFlow: CaptureFlow {
        switch self {
        case .idle, .choosingMode:
            .choice
        case .selectingSource(let mode),
             .ready(let mode, _),
             .areaSelecting(let mode):
            mode == .screenshot ? .screenshotSetup : .recordingSetup
        case .startingRecording,
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
    case showSourceSelector
    case showAreaSelector
    case showStudio
    case closeSourceSelector
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
