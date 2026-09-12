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
    var isVisible = true
    /// Font height relative to the short canvas edge, expressed at 1080 pixels.
    var fontSize: Double = 36
    var textHex = "#FFFFFF"
    var backgroundHex = "#000000"
    var backgroundOpacity: Double = 0.65
    var position: Position = .bottom
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
