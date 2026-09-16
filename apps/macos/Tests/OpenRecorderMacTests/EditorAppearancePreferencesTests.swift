import CoreGraphics
import Foundation
import XCTest
@testable import OpenRecorderMac

@MainActor
final class EditorAppearancePreferencesTests: XCTestCase {
    func testScreenshotAndVideoPreferencesRoundTripIndependently() {
        let store = makeStore()
        var screenshotState = ScreenshotEditorState.default
        screenshotState.canvasAspect = .square
        screenshotState.background = .solid(SerializableColor(hex: "#112233"))
        screenshotState.padding = 72
        screenshotState.backgroundRoundness = 18
        screenshotState.backgroundShadow = 0.2
        screenshotState.imageRoundness = 24
        screenshotState.imageShadow = 0.8
        let screenshotPreferences = ScreenshotAppearancePreferences(state: screenshotState)

        store.saveScreenshot(screenshotPreferences)

        XCTAssertEqual(store.loadScreenshot(), screenshotPreferences)
        XCTAssertEqual(store.loadVideo(), .default)

        var videoState = ProjectVideoEditorState.default
        videoState.canvasAspect = .vertical
        videoState.background = .transparent
        videoState.padding = 31
        videoState.borderRadius = 22
        videoState.shadow = 0.7
        videoState.backgroundBlur = 12
        videoState.inset = 9
        videoState.insetColor = SerializableColor(hex: "#ABCDEF")
        videoState.insetOpacity = 0.6
        videoState.insetBalance = VideoInsetBalance(left: 0.2, top: 0.8)
        let videoPreferences = VideoAppearancePreferences(state: videoState)

        store.saveVideo(videoPreferences)

        XCTAssertEqual(store.loadScreenshot(), screenshotPreferences)
        XCTAssertEqual(store.loadVideo(), videoPreferences)
    }

    func testCorruptPreferencesFallBackToEditorDefaults() {
        let suiteName = "OpenRecorder.EditorAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(Data("not-json".utf8), forKey: EditorAppearancePreferencesStore.screenshotDefaultsKey)
        defaults.set(Data([0x00, 0xFF]), forKey: EditorAppearancePreferencesStore.videoDefaultsKey)
        let store = EditorAppearancePreferencesStore(defaults: defaults)

        XCTAssertEqual(store.loadScreenshot(), .default)
        XCTAssertEqual(store.loadVideo(), .default)
    }

    func testMissingCustomBackgroundFallsBackWithoutResettingOtherScreenshotPreferences() throws {
        let store = makeStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-appearance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backgroundURL = directory.appendingPathComponent("background.jpg")
        XCTAssertTrue(FileManager.default.createFile(atPath: backgroundURL.path, contents: Data("image".utf8)))
        let background = BackgroundStyle.wallpaper(WallpaperPreset(
            id: "custom",
            label: "Custom",
            fullAssetName: "",
            thumbAssetName: "",
            customURL: backgroundURL
        ))
        var state = ScreenshotEditorState.default
        state.background = background
        state.padding = 88
        let preferences = ScreenshotAppearancePreferences(state: state)
        store.saveScreenshot(preferences)

        XCTAssertEqual(store.loadScreenshot(), preferences)
        try FileManager.default.removeItem(at: backgroundURL)

        let repaired = store.loadScreenshot()
        XCTAssertEqual(repaired.background, ScreenshotAppearancePreferences.default.background)
        XCTAssertEqual(repaired.padding, 88)
        XCTAssertEqual(store.loadScreenshot(), repaired)
    }

    func testMissingCustomBackgroundFallsBackWithoutResettingOtherVideoPreferences() throws {
        let store = makeStore()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-background-\(UUID().uuidString).mp4")
        let background = BackgroundStyle.wallpaper(WallpaperPreset(
            id: "custom-video",
            label: "Custom Video",
            fullAssetName: "",
            thumbAssetName: "",
            customURL: missingURL,
            isVideo: true
        ))
        var state = ProjectVideoEditorState.default
        state.background = background
        state.padding = 42
        state.backgroundBlur = 16
        store.saveVideo(VideoAppearancePreferences(state: state))

        let repaired = store.loadVideo()
        XCTAssertEqual(repaired.background, VideoAppearancePreferences.default.background)
        XCTAssertEqual(repaired.padding, 42)
        XCTAssertEqual(repaired.backgroundBlur, 16)
        XCTAssertEqual(store.loadVideo(), repaired)
    }

    func testAppearanceProjectionPreservesProjectSpecificState() {
        var screenshotSource = ScreenshotEditorState.default
        screenshotSource.padding = 90
        screenshotSource.scene.pose.tiltX = 20
        var screenshotTarget = ScreenshotEditorState.default
        screenshotTarget.scene.pose.tiltY = -15
        let projectedScreenshot = ScreenshotAppearancePreferences(state: screenshotSource).applying(to: screenshotTarget)
        XCTAssertEqual(projectedScreenshot.padding, 90)
        XCTAssertEqual(projectedScreenshot.scene, screenshotTarget.scene)

        var videoSource = ProjectVideoEditorState.default
        videoSource.padding = 37
        videoSource.scene.pose.rotation = 12
        videoSource.cropSelection = VideoCropSelection(
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
            sizing: .custom(width: 1000, height: 700)
        )
        videoSource.cursorOverlay = .hidden
        videoSource.facecamSettings = defaultFacecamSettings(enabled: true)

        var videoTarget = ProjectVideoEditorState.default
        videoTarget.scene.pose.tiltX = 8
        videoTarget.cropSelection = VideoCropSelection(
            normalizedRect: CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.8),
            sizing: .preset(.source)
        )
        videoTarget.cursorOverlay.size = 2
        videoTarget.facecamSettings = nil
        let projectedVideo = VideoAppearancePreferences(state: videoSource).applying(to: videoTarget)

        XCTAssertEqual(projectedVideo.padding, 37)
        XCTAssertEqual(projectedVideo.scene, videoTarget.scene)
        XCTAssertEqual(projectedVideo.cropSelection, videoTarget.cropSelection)
        XCTAssertEqual(projectedVideo.cursorOverlay, videoTarget.cursorOverlay)
        XCTAssertEqual(projectedVideo.facecamSettings, videoTarget.facecamSettings)
    }

    func testScreenshotDriverPersistsOnlyUserDrivenAppearanceChangesAndAppearanceUndoRedo() {
        let driver = ScreenshotEditorDriver()
        var saved: [ScreenshotAppearancePreferences] = []
        driver.configureAppearancePersistence { saved.append($0) }
        var loaded = ScreenshotEditorState.default
        loaded.padding = 70

        driver.send(.sessionChanged(ScreenshotEditorSessionContext(
            screenshotURL: URL(fileURLWithPath: "/tmp/input.png"),
            projectPath: "/tmp/input.openrecorder",
            editorTitle: "Input",
            initialScreenshotState: loaded,
            editorSessionID: UUID()
        )))
        XCTAssertTrue(saved.isEmpty)

        var scene = loaded.scene
        scene.pose.tiltX = 14
        driver.update(\.scene, to: scene)
        XCTAssertTrue(saved.isEmpty)

        driver.update(\.padding, to: 92)
        XCTAssertEqual(saved.map(\.padding), [92])

        driver.undo()
        driver.redo()
        XCTAssertEqual(saved.map(\.padding), [92, 70, 92])
    }

    func testVideoDriverPersistsOnlyUserDrivenAppearanceChangesAndAppearanceUndoRedo() {
        let driver = VideoEditorDriver()
        var saved: [VideoAppearancePreferences] = []
        driver.configureAppearancePersistence { saved.append($0) }
        var loaded = ProjectVideoEditorState.default
        loaded.padding = 26

        driver.send(.sessionChanged(VideoEditorSessionContext(
            videoURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            projectPath: "/tmp/input.openrecorder",
            editorTitle: "Input",
            recordingSession: nil,
            initialTimelineEdits: .empty,
            initialVideoState: loaded,
            editorSessionID: UUID(),
            defaultShowCursor: true
        )))
        XCTAssertTrue(saved.isEmpty)

        var scene = loaded.scene
        scene.pose.rotation = 9
        driver.binding(\.scene).wrappedValue = scene
        XCTAssertTrue(saved.isEmpty)

        driver.binding(\.padding).wrappedValue = 54
        XCTAssertEqual(saved.map(\.padding), [54])

        driver.undo()
        driver.redo()
        XCTAssertEqual(saved.map(\.padding), [54, 26, 54])
    }

    func testAppModelConnectsEachEditorToItsOwnAppearanceStore() {
        let store = makeStore()
        let model = AppModel(editorAppearancePreferencesStore: store)
        let workspace = model.appShell.workspace(for: nil)

        workspace.screenshot.update(\.padding, to: 101)
        workspace.video.binding(\.padding).wrappedValue = 47

        XCTAssertEqual(store.loadScreenshot().padding, 101)
        XCTAssertEqual(store.loadVideo().padding, 47)
    }

    private func makeStore() -> EditorAppearancePreferencesStore {
        let suiteName = "OpenRecorder.EditorAppearanceTests.\(UUID().uuidString)"
        return EditorAppearancePreferencesStore(defaults: UserDefaults(suiteName: suiteName)!)
    }
}
