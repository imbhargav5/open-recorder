import XCTest
@testable import OpenRecorderMac

@MainActor
final class AppModelStateTests: XCTestCase {
    func testBeginRecordingMovesToSetupAndRequestsSelector() {
        let model = AppModel()

        model.beginCapture(.recording)

        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertEqual(model.hudState, .selectingSource(.recording))
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testBeginScreenshotMovesToSetupAndRequestsSelector() {
        let model = AppModel()

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.captureMode, .screenshot)
        XCTAssertEqual(model.captureFlow, .screenshotSetup)
        XCTAssertEqual(model.hudState, .selectingSource(.screenshot))
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testNewCaptureIsDisabledDuringRecordingSetup() {
        let model = AppModel()

        model.beginCapture(.recording)

        XCTAssertFalse(model.canStartNewCapture)

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertEqual(model.hudState, .selectingSource(.recording))
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testNewCaptureIsDisabledDuringScreenshotSetup() {
        let model = AppModel()

        model.beginCapture(.screenshot)

        XCTAssertFalse(model.canStartNewCapture)

        model.beginCapture(.recording)

        XCTAssertEqual(model.captureMode, .screenshot)
        XCTAssertEqual(model.captureFlow, .screenshotSetup)
        XCTAssertEqual(model.hudState, .selectingSource(.screenshot))
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testNewCaptureIsDisabledOnlyWhileRecording() {
        let model = AppModel()

        XCTAssertTrue(model.canStartNewCapture)

        model.capture.setRecordingForTesting(true)

        XCTAssertFalse(model.canStartNewCapture)
    }

    func testNewCaptureIsDisabledDuringRecordingTransitions() {
        let model = AppModel()

        model.recordingPhase = .starting
        XCTAssertFalse(model.canStartNewCapture)

        model.recordingPhase = .stopping
        XCTAssertFalse(model.canStartNewCapture)

        model.recordingPhase = .idle
        XCTAssertTrue(model.canStartNewCapture)
    }

    func testActiveHUDStatesDisableNewCaptures() {
        let source = CaptureSource(
            id: "display:1",
            kind: .display,
            name: "Display 1",
            subtitle: "Built-in",
            displayIndex: 1,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
        let occupiedStates: [HUDState] = [
            .ready(.recording, source),
            .areaSelecting(.screenshot),
            .startingRecording(source),
            .recording(source),
            .stoppingRecording(source),
            .capturingScreenshot(source)
        ]

        for state in occupiedStates {
            let model = AppModel()

            model.hudState = state

            XCTAssertFalse(model.canStartNewCapture, "\(state) should occupy the capture slot")
        }
    }

    func testShowEditorCarriesIndependentEditorSession() {
        let model = AppModel()
        let url = URL(fileURLWithPath: "/tmp/example-recording.mp4")
        let session = EditorSession(kind: .video, url: url, title: "Example Recording")
        model.beginCapture(.recording)

        model.showEditor(for: session)

        XCTAssertEqual(model.selectedSection, .editor)
        XCTAssertEqual(model.lastEditorSession, session)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertTrue(model.canStartNewCapture)
        XCTAssertEqual(model.windowCommand?.action, .showStudio)
        XCTAssertEqual(model.windowCommand?.editorSession, session)
    }

    func testSelectingSourceMovesHUDToReadyState() {
        let model = AppModel()
        let source = CaptureSource(
            id: "display:1",
            kind: .display,
            name: "Display 1",
            subtitle: "Built-in",
            displayIndex: 1,
            displayID: nil,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )

        model.beginCapture(.recording)
        model.selectSource(source)

        XCTAssertEqual(model.hudState, .ready(.recording, source))
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertFalse(model.canStartNewCapture)
    }

    func testScreenshotEditorReleasesCaptureSlot() {
        let model = AppModel()
        let url = URL(fileURLWithPath: "/tmp/example-screenshot.png")
        let session = EditorSession(kind: .screenshot, url: url)

        model.beginCapture(.screenshot)
        model.showEditor(for: session)

        XCTAssertEqual(model.hudState, .choosingMode)
        XCTAssertEqual(model.captureFlow, .choice)
        XCTAssertTrue(model.canStartNewCapture)
    }

    func testEditorSessionCanCarryRecordingSessionMetadata() {
        let url = URL(fileURLWithPath: "/tmp/example-recording.mp4")
        let recordingSession = RecordingSession(
            screenVideoPath: url.path,
            facecamVideoPath: "/tmp/example-recording.facecam.mov",
            facecamOffsetMs: 120,
            facecamSettings: defaultFacecamSettings(enabled: true),
            sourceName: "Display",
            showCursorOverlay: true,
            cursorTelemetryPath: "/tmp/example-recording.cursor.json"
        )

        let session = EditorSession(kind: .video, url: url, recordingSession: recordingSession)

        XCTAssertEqual(session.recordingSession, recordingSession)
        XCTAssertEqual(session.recordingSession?.facecamOffsetMs, 120)
        XCTAssertEqual(session.recordingSession?.cursorTelemetryPath, "/tmp/example-recording.cursor.json")
    }

    func testAreaSelectionUsesInteractiveAreaSource() {
        let model = AppModel()

        model.selectInteractiveAreaSource()

        XCTAssertEqual(model.selectedSource?.kind, .area)
        XCTAssertEqual(model.selectedSource?.id, "area:interactive")
        XCTAssertEqual(model.statusMessage, "Selected area")
    }

    func testWindowCommandIsConsumedOnce() {
        let model = AppModel()
        model.requestWindow(.showStudio)

        let firstCommand = model.consumeWindowCommand(model.windowCommand)
        let secondCommand = model.consumeWindowCommand(model.windowCommand)

        XCTAssertEqual(firstCommand?.action, .showStudio)
        XCTAssertNil(secondCommand)
    }
}
