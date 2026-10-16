import Foundation

struct CaptionSegment: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var start: Double
    var end: Double
    var text: String

    func contains(_ time: Double) -> Bool { start <= time && time < end }
    var isValid: Bool { start.isFinite && end.isFinite && start >= 0 && end > start && text.count <= 2000 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct CaptionStyle: Codable, Equatable, Hashable, Sendable {
    enum Position: String, Codable, CaseIterable, Sendable { case top, bottom }
    enum TransitionKind: String, Codable, CaseIterable, Identifiable, Sendable {
        case cut, fade, slideUp, pop
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cut: "Cut"
            case .fade: "Fade"
            case .slideUp: "Slide Up"
            case .pop: "Pop"
            }
        }
    }
    var isVisible = true
    /// Font height relative to the short canvas edge, expressed at 1080 pixels.
    var fontSize: Double = 36
    var fontFamily: String = "Helvetica-Bold"
    var textHex = "#FFFFFF"
    var backgroundHex = "#000000"
    var backgroundOpacity: Double = 0.65
    var position: Position = .bottom
    var transition: TransitionKind = .fade
    var transitionSpeed: Double = 0.25
    var outlineWidth: Double = 0
    var outlineHex: String = "#000000"
    var letterSpacing: Double = 0
}

enum CaptionStylePreset: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case minimal = "Minimal"
    case bold = "Bold"
    case outline = "Outline"
    case neon = "Neon"

    var id: String { rawValue }

    var style: CaptionStyle {
        switch self {
        case .standard:
            CaptionStyle()
        case .minimal:
            CaptionStyle(fontSize: 28, fontFamily: "Helvetica", backgroundOpacity: 0, transition: .fade, transitionSpeed: 0.2)
        case .bold:
            CaptionStyle(fontSize: 48, fontFamily: "Helvetica-Bold", backgroundHex: "#1A1A2E", backgroundOpacity: 0.85, transition: .pop, transitionSpeed: 0.15)
        case .outline:
            CaptionStyle(fontSize: 42, fontFamily: "Helvetica-Bold", backgroundOpacity: 0, outlineWidth: 3, outlineHex: "#000000")
        case .neon:
            CaptionStyle(fontSize: 40, fontFamily: "Helvetica-Bold", textHex: "#00FF88", backgroundHex: "#000000", backgroundOpacity: 0.75, transition: .slideUp, transitionSpeed: 0.18, letterSpacing: 2)
        }
    }
}

struct CaptionTrack: Codable, Equatable, Hashable, Sendable {
    var segments: [CaptionSegment] = []
    var style = CaptionStyle()
    var language = "auto"
    var model = ""
    var isEdited = false

    func active(at time: Double) -> CaptionSegment? {
        guard style.isVisible else { return nil }
        return segments.first { $0.isValid && $0.contains(time) }
    }
}

enum CaptionFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let value): value } }
}
