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
    // Familiar, ready-to-use treatments found in social and video editors.
    // They deliberately use the existing renderer features so every preset is
    // equally reliable in the preview and exported movie.
    case social = "Social"
    case creator = "Creator"
    case cinema = "Cinema"
    case news = "News"
    case retro = "Retro"
    case shorts = "Shorts"
    case podcast = "Podcast"
    case tutorial = "Tutorial"
    case gaming = "Gaming"
    case documentary = "Documentary"

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
        case .social:
            // The high-contrast outlined treatment common in short-form video.
            CaptionStyle(fontSize: 46, fontFamily: "Helvetica-Bold", backgroundOpacity: 0, transition: .pop, transitionSpeed: 0.12, outlineWidth: 4, outlineHex: "#000000", letterSpacing: 0.5)
        case .creator:
            // A bright emphasis style that stays legible over screen captures.
            CaptionStyle(fontSize: 46, fontFamily: "Helvetica-Bold", textHex: "#FFE600", backgroundHex: "#000000", backgroundOpacity: 0.82, transition: .pop, transitionSpeed: 0.14, outlineWidth: 1.5, outlineHex: "#000000")
        case .cinema:
            CaptionStyle(fontSize: 30, fontFamily: "Helvetica", textHex: "#F7F1E3", backgroundHex: "#000000", backgroundOpacity: 0.78, transition: .fade, transitionSpeed: 0.28, letterSpacing: 0.4)
        case .news:
            CaptionStyle(fontSize: 34, fontFamily: "Helvetica-Bold", textHex: "#FFFFFF", backgroundHex: "#C8102E", backgroundOpacity: 0.94, transition: .slideUp, transitionSpeed: 0.20, letterSpacing: 0.3)
        case .retro:
            CaptionStyle(fontSize: 38, fontFamily: "Menlo-Bold", textHex: "#FFF4C2", backgroundHex: "#3A245B", backgroundOpacity: 0.88, transition: .cut, outlineWidth: 1, outlineHex: "#170D28", letterSpacing: 1)
        case .shorts:
            CaptionStyle(fontSize: 52, fontFamily: "Helvetica-Bold", textHex: "#FFFFFF", backgroundOpacity: 0, transition: .pop, transitionSpeed: 0.1, outlineWidth: 5, outlineHex: "#111111", letterSpacing: 0.8)
        case .podcast:
            CaptionStyle(fontSize: 34, fontFamily: "Avenir-Heavy", textHex: "#FFFFFF", backgroundHex: "#161616", backgroundOpacity: 0.9, transition: .fade, transitionSpeed: 0.2, letterSpacing: 0.25)
        case .tutorial:
            CaptionStyle(fontSize: 38, fontFamily: "SFProDisplay-Bold", textHex: "#102A43", backgroundHex: "#D9F99D", backgroundOpacity: 0.96, transition: .slideUp, transitionSpeed: 0.18, outlineWidth: 0.5, outlineHex: "#FFFFFF")
        case .gaming:
            CaptionStyle(fontSize: 48, fontFamily: "Helvetica-Bold", textHex: "#FF4FD8", backgroundHex: "#12051D", backgroundOpacity: 0.76, transition: .pop, transitionSpeed: 0.12, outlineWidth: 3, outlineHex: "#FFFFFF", letterSpacing: 1.2)
        case .documentary:
            CaptionStyle(fontSize: 28, fontFamily: "Georgia-Bold", textHex: "#F5E6C8", backgroundHex: "#101010", backgroundOpacity: 0.72, transition: .fade, transitionSpeed: 0.32, letterSpacing: 0.55)
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
