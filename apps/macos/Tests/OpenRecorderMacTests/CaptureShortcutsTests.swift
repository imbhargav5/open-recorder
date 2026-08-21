import Carbon
import XCTest
@testable import OpenRecorderMac

@MainActor
final class CaptureShortcutsTests: XCTestCase {
    func testDefaultShortcutsMapMatchesStandardConventions() {
        let defaults = ShortcutPreferences.defaultPreferences

        let screenshot = defaults.item(for: .deviceScreenshot)
        XCTAssertTrue(screenshot.isEnabled)
        XCTAssertEqual(screenshot.keyCombination.displayString, "⌥⇧3")
        XCTAssertEqual(screenshot.keyCombination.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertTrue(screenshot.keyCombination.modifiers.contains(.option))
        XCTAssertTrue(screenshot.keyCombination.modifiers.contains(.shift))

        let dragScreenshot = defaults.item(for: .dragScreenshot)
        XCTAssertTrue(dragScreenshot.isEnabled)
        XCTAssertEqual(dragScreenshot.keyCombination.displayString, "⌥⇧4")

        let screenRecord = defaults.item(for: .deviceScreenRecord)
        XCTAssertTrue(screenRecord.isEnabled)
        XCTAssertEqual(screenRecord.keyCombination.displayString, "⌥⇧5")

        let dragRecord = defaults.item(for: .dragScreenRecord)
        XCTAssertTrue(dragRecord.isEnabled)
        XCTAssertEqual(dragRecord.keyCombination.displayString, "⌥⇧6")

        let toggleRecording = defaults.item(for: .toggleRecording)
        XCTAssertTrue(toggleRecording.isEnabled)
        XCTAssertEqual(toggleRecording.keyCombination.displayString, "⌥⇧R")
    }

    func testKeyCombinationCarbonModifiers() {
        let combo = KeyCombination(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift, .option, .control])
        let expectedCarbon = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        XCTAssertEqual(combo.carbonModifiers, expectedCarbon)
    }

    func testShortcutPreferencesRoundTripPersistence() throws {
        let suiteName = "CaptureShortcutsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RecordingPreferencesStore(defaults: defaults)
        var prefs = store.load().shortcuts

        var updatedItem = prefs.item(for: .deviceScreenshot)
        updatedItem.keyCombination = KeyCombination(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command, .shift])
        updatedItem.isEnabled = false
        prefs.setItem(updatedItem)

        store.setShortcuts(prefs)

        let reloaded = store.load().shortcuts
        let reloadedItem = reloaded.item(for: .deviceScreenshot)
        XCTAssertFalse(reloadedItem.isEnabled)
        XCTAssertEqual(reloadedItem.keyCombination.displayString, "⇧⌘S")
    }

    func testSettingsDriverShortcutUpdates() {
        var persistedShortcuts: ShortcutPreferences?
        let driver = SettingsDriver(createZoomsAutomatically: true)
        driver.configure(
            persistShortcuts: { shortcuts in
                persistedShortcuts = shortcuts
            }
        )

        var item = driver.state.shortcuts.item(for: .dragScreenshot)
        item.isEnabled = false
        driver.send(.shortcutItemChanged(item))

        XCTAssertFalse(driver.state.shortcuts.item(for: .dragScreenshot).isEnabled)
        XCTAssertEqual(persistedShortcuts?.item(for: .dragScreenshot).isEnabled, false)

        driver.send(.shortcutsResetToDefaults)
        XCTAssertTrue(driver.state.shortcuts.item(for: .dragScreenshot).isEnabled)
    }

    func testAppModelShortcutTriggers() async {
        let model = AppModel(
            screenshotCapture: { _, _ in },
            startRecordingCapture: { _, _, _ in Date() },
            stopRecording: { URL(fileURLWithPath: "/tmp/test.mp4") }
        )

        model.cancelCapture()
        model.triggerDeviceScreenshot()
        XCTAssertEqual(model.captureMode, .screenshot)

        model.cancelCapture()
        model.triggerDragScreenshot()
        XCTAssertEqual(model.captureMode, .screenshot)

        model.cancelCapture()
        model.triggerDeviceScreenRecord()
        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.selectedSource?.kind, .display)

        model.cancelCapture()
        model.triggerDragScreenRecord()
        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertFalse(model.isDragRecordingPending)

        model.cancelCapture()
        XCTAssertFalse(model.isDragRecordingPending)
    }
}
