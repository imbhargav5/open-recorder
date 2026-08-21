import Foundation

struct RecordingSessionBuilder {
    static func build(
        screenVideoURL: URL,
        facecamURL: URL?,
        facecamSettings: FacecamSettings? = nil,
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

        let initialSettings = (facecamSettings ?? defaultFacecamSettings(enabled: facecamURL != nil)).clamped

        return RecordingSession(
            screenVideoPath: screenVideoURL.path,
            facecamVideoPath: facecamURL?.path,
            facecamOffsetMs: offsetMs,
            facecamSettings: initialSettings,
            sourceName: sourceName,
            showCursorOverlay: showCursor,
            cursorTelemetryPath: cursorTelemetryURL?.path
        )
    }
}
