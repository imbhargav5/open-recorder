import Foundation

struct RecordingSessionBuilder {
    static func build(
        screenVideoURL: URL,
        facecamURL: URL?,
        sourceName: String?,
        showCursor: Bool,
        cursorTelemetryURL: URL?,
        screenStartedAt: Date?,
        facecamStartedAt: Date?
    ) -> RecordingSession {
        let offsetMs: Int?
        if facecamURL != nil, let screenStartedAt, let facecamStartedAt {
            offsetMs = Int(facecamStartedAt.timeIntervalSince(screenStartedAt) * 1000)
        } else {
            offsetMs = nil
        }

        return RecordingSession(
            screenVideoPath: screenVideoURL.path,
            facecamVideoPath: facecamURL?.path,
            facecamOffsetMs: offsetMs,
            facecamSettings: defaultFacecamSettings(enabled: facecamURL != nil),
            sourceName: sourceName,
            showCursorOverlay: showCursor,
            cursorTelemetryPath: cursorTelemetryURL?.path
        )
    }
}
