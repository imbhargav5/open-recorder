import AppKit
import Carbon
import XCTest
@testable import OpenRecorderMac

@MainActor
final class QuickCaptureTests: XCTestCase {
    private func source(_ id: UInt32, kind: CaptureSourceKind = .display, owner: String? = nil) -> CaptureSource {
        CaptureSource(id: "\(kind.rawValue):\(id)", kind: kind, name: "Target \(id)", subtitle: "",
                      displayIndex: nil, displayID: kind == .display ? id : nil,
                      windowID: kind == .window ? id : nil, area: nil, thumbnailData: nil, ownerBundleID: owner)
    }

    private func permission() -> ScreenRecordingPermission {
        ScreenRecordingPermission(client: .init(preflight: { true }, request: { true }, hasRequestedPrompt: { false }, setRequestedPrompt: { _ in }))
    }

    func testCurrentDisplayUsesPointerAndNeverPicksAnArbitrarySecondDisplay() {
        let screens = [source(1), source(2)]
        XCTAssertEqual(QuickCaptureTargetContext(displayID: 2, orderedWindowIDs: []).target(in: screens, kind: .display)?.displayID, 2)
        XCTAssertNil(QuickCaptureTargetContext(displayID: 3, orderedWindowIDs: []).target(in: screens, kind: .display))
        XCTAssertEqual(QuickCaptureTargetContext(displayID: nil, orderedWindowIDs: []).target(in: [source(1)], kind: .display)?.displayID, 1)
    }

    func testCurrentWindowUsesFrontToBackOrderAndCannotCaptureAnotherApp() {
        let context = QuickCaptureTargetContext(ownerBundleID: "test.app", orderedWindowIDs: [9, 3, 2])
        let sources = [source(2, kind: .window, owner: "test.app"), source(3, kind: .window, owner: "test.app"), source(9, kind: .window, owner: "other.app")]
        XCTAssertEqual(context.target(in: sources, kind: .window)?.windowID, 3)
        XCTAssertNil(context.target(in: [sources[2]], kind: .window))
    }

    func testRecordingTargetShortcutsPrepareSetupAndNeverStartOrStopRecording() {
        var starts = 0
        var stops = 0
        let model = AppModel(screenRecordingPermission: permission(),
                             quickCaptureTargetContext: { .init(displayID: 2, ownerBundleID: "test.app", orderedWindowIDs: [3]) },
                             startRecordingCapture: { _, _, _ in starts += 1; return Date() },
                             stopRecording: { stops += 1; return URL(fileURLWithPath: "/tmp/unused.mp4") })
        model.capture.setSourcesForTesting([source(2), source(3, kind: .window, owner: "test.app")])
        model.triggerDeviceScreenRecord()
        XCTAssertEqual(model.selectedSource?.displayID, 2)
        XCTAssertTrue(model.isHUDVisible)
        model.triggerWindowScreenRecord()
        XCTAssertEqual(model.selectedSource?.windowID, 3)
        model.capture.setRecordingForTesting(true)
        model.triggerDeviceScreenRecord()
        model.triggerWindowScreenRecord()
        model.triggerDragScreenRecord()
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
    }

    func testToggleFromSourceFreeLaunchShowsSetupAndIsRegisteredGlobally() {
        let model = AppModel()
        XCTAssertNil(model.selectedSource)
        model.toggleRecordingShortcut()
        XCTAssertTrue(model.isHUDVisible)
        XCTAssertTrue(GlobalRecordingHotKeyRegistrationPolicy.shouldRegister(action: .toggleRecording,
            item: ShortcutPreferences.defaultPreferences.item(for: .toggleRecording), captureState: .choosingMode,
            runtimeIsRecording: false, shortcutRecorderIsActive: false))
    }

    func testRegistrationFailureIsVisibleAndCanBeRetriedWithoutChangingPreferences() throws {
        let name = "QuickCaptureRegistration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(recordingPreferences: RecordingPreferencesStore(defaults: defaults))
        let controller = GlobalRecordingHotKeyController()
        defer { controller.detach() }
        var attempts = 0
        controller.registerHotKey = { _, _ in attempts += 1; return (OSStatus(eventHotKeyExistsErr), nil) }
        controller.attach(model: model)
        XCTAssertEqual(model.appShell.settings.state.shortcutRegistrationStates[.deviceScreenshot], .unavailable)
        let before = attempts
        model.appShell.settings.send(.shortcutRegistrationRetryRequested)
        XCTAssertGreaterThan(attempts, before)
        XCTAssertTrue(model.shortcutPreferences.item(for: .deviceScreenshot).isEnabled)
        model.setShortcutRecorderActive(true)
        XCTAssertEqual(model.appShell.settings.state.shortcutRegistrationStates[.deviceScreenshot], .suspended)
        model.setShortcutRecorderActive(false)
        XCTAssertEqual(model.appShell.settings.state.shortcutRegistrationStates[.deviceScreenshot], .unavailable)
    }

    func testScreenshotCopyAndSaveSkipEditorAndKeepEditableRecovery() async throws {
        for behavior in [ScreenshotAfterCapture.copy, .save] {
            let name = "QuickCaptureTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let preferences = RecordingPreferencesStore(defaults: defaults)
            preferences.setScreenshotAfterCapture(behavior)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            var copied: URL?
            let model = AppModel(screenRecordingPermission: permission(), recordingPreferences: preferences,
                captureUIHideDelayNanoseconds: 0,
                screenshotCapture: { _, output in try Data("fixture".utf8).write(to: output) },
                copyCapturedScreenshot: { copied = $0 },
                quickCaptureTargetContext: { .init(displayID: 2, orderedWindowIDs: []) },
                rememberScreenshot: { _ in },
                registerCapturedMedia: { _, _ in throw CocoaError(.fileReadUnknown) })
            model.paths = AppPaths(recordingsDir: folder.path, screenshotsDir: folder.path, projectsDir: folder.path, supportDir: folder.path)
            model.capture.setSourcesForTesting([source(2)])
            model.triggerDeviceScreenshot()
            for _ in 0..<100 where !model.hasQuickScreenshot { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(model.hasQuickScreenshot)
            XCTAssertTrue(model.isHUDVisible)
            XCTAssertEqual(model.statusMessage, behavior == .copy ? "Screenshot copied" : "Screenshot saved")
            XCTAssertNotEqual(model.windowCommand?.action, .showStudio)
            XCTAssertEqual(copied != nil, behavior == .copy)
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(model.currentScreenshotURL).path))
            model.editLastQuickScreenshot()
            XCTAssertEqual(model.windowCommand?.action, .showStudio)
        }
    }

    func testCapturePreferencesSurviveRestartAndMissingKeysPreserveExistingBehavior() throws {
        let name = "QuickCapturePreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RecordingPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.load().screenshotAfterCapture, .edit)
        XCTAssertFalse(store.load().adjustsAreaBeforeCapture)
        store.setScreenshotAfterCapture(.copy)
        store.setAdjustsAreaBeforeCapture(true)
        let reloaded = RecordingPreferencesStore(defaults: defaults).load()
        XCTAssertEqual(reloaded.screenshotAfterCapture, .copy)
        XCTAssertTrue(reloaded.adjustsAreaBeforeCapture)
    }

    func testMenuHintsReflectCustomShortcutAndHideDisabledShortcut() throws {
        let name = "QuickCaptureMenu.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(recordingPreferences: RecordingPreferencesStore(defaults: defaults))
        var preferences = model.shortcutPreferences
        var item = preferences.item(for: .windowScreenshot)
        item.keyCombination = KeyCombination(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .option])
        preferences.setItem(item)
        item = preferences.item(for: .deviceScreenshot)
        item.isEnabled = false
        preferences.setItem(item)
        model.updateShortcutPreferences(preferences)
        let controller = OpenRecorderStatusItemController(model: model, windowActions: AppWindowActions())
        let menu = controller.makeMenu(updateChecksEnabled: false)
        XCTAssertEqual(menu.items.first { $0.representedObject as? String == CaptureShortcutAction.windowScreenshot.rawValue }?.title,
                       "Screenshot current window   ⌃⌥K")
        XCTAssertEqual(menu.items.first { $0.representedObject as? String == CaptureShortcutAction.deviceScreenshot.rawValue }?.title,
                       "Screenshot current display")
    }

    func testAreaAdjustmentKeepsDimensionsAndCornersInsideDisplay() {
        let rect = CGRect(x: 20, y: 30, width: 100, height: 80)
        let size = CGSize(width: 200, height: 160)
        XCTAssertEqual(AreaSelectionGeometry.moved(rect, translation: CGSize(width: 300, height: -50), bounds: size), CGRect(x: 100, y: 0, width: 100, height: 80))
        let expanded = AreaSelectionGeometry.resized(rect, corner: .bottomRight, translation: CGSize(width: 200, height: 200), bounds: size)
        XCTAssertEqual(expanded, CGRect(x: 20, y: 30, width: 180, height: 130))
        let collapsed = AreaSelectionGeometry.resized(rect, corner: .topLeft, translation: CGSize(width: 200, height: 200), bounds: size)
        XCTAssertEqual(collapsed.size, CGSize(width: 8, height: 8))
        XCTAssertEqual(collapsed.maxX, rect.maxX)
        XCTAssertEqual(collapsed.maxY, rect.maxY)
    }
}
