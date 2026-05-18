import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class VideoEditorStateMachineTests: XCTestCase {
    func testSessionAppliesInitialVideoStateAndTimelineSnapshot() {
        let videoURL = URL(fileURLWithPath: "/tmp/example.mp4")
        let projectPath = "/tmp/example.openrecorder"
        let timeline = TimelineEditSnapshot(zoomRegions: [
            TimelineZoomRegion(span: TimelineSpan(start: 1, end: 2))
        ])
        let initialVideo = ProjectVideoEditorState(
            background: .solid(SerializableColor(hex: "#112233")),
            padding: 36,
            borderRadius: 10,
            shadow: 0.2,
            backgroundBlur: 1,
            inset: 12,
            insetColor: SerializableColor(hex: "#445566"),
            insetOpacity: 0.8,
            insetBalance: .centered,
            cropSelection: .fullFrame,
            cursorOverlay: CursorOverlaySettings(isVisible: false, loops: true, size: 1.4, smoothing: 0.7),
            facecamSettings: defaultFacecamSettings(enabled: true)
        )
        let context = VideoEditorSessionContext(
            videoURL: videoURL,
            projectPath: projectPath,
            editorTitle: "Example",
            recordingSession: makeRecordingSession(hasCamera: true, showCursor: true),
            initialTimelineEdits: timeline,
            initialVideoState: initialVideo,
            editorSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            defaultShowCursor: true
        )
        var state = VideoEditorState()

        let effects = state.applying(.sessionChanged(context))

        XCTAssertEqual(state.video, initialVideo)
        XCTAssertEqual(state.previewAspectPreset, .auto)
        XCTAssertEqual(state.appliedTimelineIdentity, context.identity)
        XCTAssertEqual(state.appliedVideoStateIdentity, context.identity)
        XCTAssertEqual(effects, [
            .applyTimelineSnapshot(timeline),
            .markAutosaved(ProjectAutosaveSnapshot(
                projectPath: projectPath,
                title: "Example",
                recordingPath: videoURL.path,
                screenshotPath: nil,
                sourceName: "Display 1",
                editorState: ProjectEditorState(timelineEdits: timeline, video: initialVideo)
            ))
        ])

        XCTAssertTrue(state.applying(.sessionChanged(context)).isEmpty)
    }

    func testSessionDefaultsCursorAndFacecamFromRecordingContext() {
        let context = VideoEditorSessionContext(
            videoURL: URL(fileURLWithPath: "/tmp/defaults.mp4"),
            projectPath: "/tmp/defaults.openrecorder",
            editorTitle: nil,
            recordingSession: makeRecordingSession(hasCamera: true, showCursor: false),
            initialTimelineEdits: nil,
            initialVideoState: nil,
            editorSessionID: nil,
            defaultShowCursor: true
        )
        var state = VideoEditorState()

        _ = state.applying(.sessionChanged(context))

        XCTAssertFalse(state.video.cursorOverlay.isVisible)
        XCTAssertTrue(state.hasRecordedCamera)
        XCTAssertEqual(state.video.facecamSettings, defaultFacecamSettings(enabled: true).clamped)
    }

    func testDurableSessionIdentityDoesNotReapplyWhenTransientSessionIDDrops() {
        let videoURL = URL(fileURLWithPath: "/tmp/transient.mp4")
        let firstContext = VideoEditorSessionContext(
            videoURL: videoURL,
            projectPath: nil,
            editorTitle: "Transient",
            recordingSession: nil,
            initialTimelineEdits: nil,
            initialVideoState: nil,
            editorSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000003"),
            defaultShowCursor: true
        )
        let secondContext = VideoEditorSessionContext(
            videoURL: videoURL,
            projectPath: nil,
            editorTitle: "Transient",
            recordingSession: nil,
            initialTimelineEdits: nil,
            initialVideoState: nil,
            editorSessionID: nil,
            defaultShowCursor: true
        )
        var state = VideoEditorState()

        _ = state.applying(.sessionChanged(firstContext))
        state.video.padding = 28
        state.video.cropSelection = VideoCropSelection(
            normalizedRect: CGRect(x: 0, y: 0, width: 0.8, height: 1),
            sizing: .preset(.p1080)
        )

        XCTAssertTrue(state.applying(.sessionChanged(secondContext)).isEmpty)
        XCTAssertEqual(state.video.padding, 28)
        XCTAssertEqual(state.video.cropSelection.normalizedRect.width, 0.8)
    }

    func testCropSheetLifecycleUpdatesCropSelection() {
        let videoURL = URL(fileURLWithPath: "/tmp/crop.mp4")
        let selection = VideoCropSelection(
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.7),
            sizing: .preset(.p1080)
        )
        var state = VideoEditorState()

        XCTAssertEqual(state.applying(.cropRequested(videoURL)), [.pausePlayback])
        XCTAssertEqual(state.activeSheet, .crop(videoURL))
        XCTAssertEqual(state.presentedSheet, .crop(videoURL))

        XCTAssertTrue(state.applying(.cropConfirmed(selection)).isEmpty)
        XCTAssertEqual(state.video.cropSelection, selection)
        XCTAssertNil(state.activeSheet)
        XCTAssertNil(state.presentedSheet)
    }

    func testExportSheetDismissalClearsOnlyWhenNotBusy() {
        var state = VideoEditorState()

        XCTAssertTrue(state.applying(.exportRequested).isEmpty)
        XCTAssertEqual(state.activeSheet, .export)

        XCTAssertTrue(state.applying(.sheetDismissed(exportIsBusy: true)).isEmpty)
        XCTAssertEqual(state.activeSheet, .export)

        XCTAssertEqual(state.applying(.sheetDismissed(exportIsBusy: false)), [.clearVideoExportDialogState])
        XCTAssertNil(state.activeSheet)
        XCTAssertNil(state.presentedSheet)
    }

    func testExportConfirmationBuildsStyledExportEffect() {
        var state = VideoEditorState()
        state.video.padding = 40
        state.video.cropSelection = VideoCropSelection(
            normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            sizing: .preset(.p720)
        )
        state.previewAspectPreset = .wide
        let recordingURL = URL(fileURLWithPath: "/tmp/export.mp4")
        let telemetryURL = URL(fileURLWithPath: "/tmp/export.cursor.json")
        let edits = TimelineEditSnapshot(clipSplitTimes: [1.25])
        let snapshot = ProjectAutosaveSnapshot(
            projectPath: "/tmp/export.openrecorder",
            title: "Export",
            recordingPath: recordingURL.path,
            screenshotPath: nil,
            sourceName: nil,
            editorState: ProjectEditorState(timelineEdits: edits, video: state.video)
        )
        let requestedOptions = VideoExportOptions.default.withCropSelection(state.video.cropSelection)

        let effects = state.applying(.exportConfirmed(
            recordingURL: recordingURL,
            options: requestedOptions,
            edits: edits,
            snapshot: snapshot,
            cursorTelemetryURL: telemetryURL
        ))

        guard case .startVideoExport(let effectURL, let options, let effectEdits, let effectSnapshot) = effects.first else {
            return XCTFail("Expected export effect.")
        }
        XCTAssertEqual(effectURL, recordingURL)
        XCTAssertEqual(effectEdits, edits)
        XCTAssertEqual(effectSnapshot, snapshot)
        XCTAssertEqual(options.aspectPreset, .wide)
        XCTAssertEqual(options.resolution, .p720)
        XCTAssertEqual(options.cropSelection, state.video.cropSelection)
        XCTAssertEqual(options.cursorTelemetryURL, telemetryURL)
        XCTAssertNotEqual(options.styling, .none)
    }

    func testAutosaveEventsEmitScheduleAndFlushEffects() {
        var state = VideoEditorState()
        let snapshot = ProjectAutosaveSnapshot(
            projectPath: "/tmp/autosave.openrecorder",
            title: "Autosave",
            recordingPath: "/tmp/autosave.mp4",
            screenshotPath: nil,
            sourceName: nil,
            editorState: ProjectEditorState(video: .default)
        )

        XCTAssertEqual(state.applying(.autosaveSnapshotChanged(snapshot)), [.scheduleAutosave(snapshot)])
        XCTAssertEqual(state.applying(.disappeared(snapshot)), [.flushAutosave(snapshot)])
    }
}

final class ScreenshotEditorPresentationStateMachineTests: XCTestCase {
    func testSessionAppliesInitialScreenshotStateAndMarksAutosaved() {
        let screenshotURL = URL(fileURLWithPath: "/tmp/screenshot.png")
        let initialState = ScreenshotEditorState(
            background: .solid(SerializableColor(hex: "#AA5500")),
            padding: 72,
            backgroundRoundness: 30,
            backgroundShadow: 0.1,
            imageRoundness: 12,
            imageShadow: 0.3
        )
        let context = ScreenshotEditorSessionContext(
            screenshotURL: screenshotURL,
            projectPath: "/tmp/screenshot.openrecorder",
            editorTitle: "Screenshot",
            initialScreenshotState: initialState,
            editorSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        var state = ScreenshotEditorPresentationState()

        let effects = state.applying(.sessionChanged(context))

        XCTAssertEqual(state.appliedScreenshotStateIdentity, context.identity)
        XCTAssertEqual(effects, [
            .applyScreenshotState(initialState),
            .markAutosaved(ProjectAutosaveSnapshot(
                projectPath: "/tmp/screenshot.openrecorder",
                title: "Screenshot",
                recordingPath: nil,
                screenshotPath: screenshotURL.path,
                sourceName: nil,
                editorState: ProjectEditorState(screenshot: initialState)
            ))
        ])
        XCTAssertTrue(state.applying(.sessionChanged(context)).isEmpty)
    }

    func testScreenshotIdentityDoesNotReapplyWhenTransientSessionIDDrops() {
        let screenshotURL = URL(fileURLWithPath: "/tmp/transient-shot.png")
        let firstContext = ScreenshotEditorSessionContext(
            screenshotURL: screenshotURL,
            projectPath: nil,
            editorTitle: "Shot",
            initialScreenshotState: nil,
            editorSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")
        )
        let secondContext = ScreenshotEditorSessionContext(
            screenshotURL: screenshotURL,
            projectPath: nil,
            editorTitle: "Shot",
            initialScreenshotState: nil,
            editorSessionID: nil
        )
        var state = ScreenshotEditorPresentationState()

        _ = state.applying(.sessionChanged(firstContext))

        XCTAssertTrue(state.applying(.sessionChanged(secondContext)).isEmpty)
    }

    func testExportDialogPresentationIsPredictable() {
        var state = ScreenshotEditorPresentationState()

        XCTAssertTrue(state.applying(.exportRequested).isEmpty)
        XCTAssertTrue(state.isExportDialogPresented)

        XCTAssertTrue(state.applying(.exportDialogDismissed).isEmpty)
        XCTAssertFalse(state.isExportDialogPresented)
    }

    func testScreenshotAutosaveAndStatusEffects() {
        var state = ScreenshotEditorPresentationState()
        let snapshot = ProjectAutosaveSnapshot(
            projectPath: "/tmp/shot.openrecorder",
            title: "Shot",
            recordingPath: nil,
            screenshotPath: "/tmp/shot.png",
            sourceName: nil,
            editorState: ProjectEditorState(screenshot: .default)
        )
        let exportURL = URL(fileURLWithPath: "/tmp/exported-shot.png")

        XCTAssertEqual(state.applying(.autosaveSnapshotChanged(snapshot)), [.scheduleAutosave(snapshot)])
        XCTAssertEqual(state.applying(.disappeared(snapshot)), [.flushAutosave(snapshot)])
        XCTAssertEqual(state.applying(.saveFailed("No image")), [.setStatusMessage("No image")])
        XCTAssertEqual(state.applying(.saveSucceeded(exportURL)), [.setStatusMessage("Exported exported-shot.png")])
        XCTAssertEqual(state.applying(.copyFailed("No image")), [.setStatusMessage("No image")])
        XCTAssertEqual(state.applying(.copySucceeded), [.setStatusMessage("Screenshot PNG copied")])
    }
}

private func makeRecordingSession(hasCamera: Bool, showCursor: Bool) -> RecordingSession {
    RecordingSession(
        screenVideoPath: "/tmp/example.mp4",
        facecamVideoPath: hasCamera ? "/tmp/example.facecam.mov" : nil,
        facecamOffsetMs: nil,
        facecamSettings: hasCamera ? defaultFacecamSettings(enabled: true) : nil,
        sourceName: "Display 1",
        showCursorOverlay: showCursor,
        cursorTelemetryPath: nil
    )
}
