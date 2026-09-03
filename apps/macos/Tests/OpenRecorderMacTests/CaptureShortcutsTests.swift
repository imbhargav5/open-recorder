import AppKit
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

    func testKeyCombinationDisplaysSpecialAndKeypadKeys() {
        XCTAssertEqual(KeyCombination(keyCode: UInt32(kVK_F12), modifiers: []).displayString, "F12")
        XCTAssertEqual(KeyCombination(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control]).displayString, "⌃←")
        XCTAssertEqual(KeyCombination(keyCode: UInt32(kVK_ANSI_Slash), modifiers: [.command]).displayString, "⌘/")
        XCTAssertEqual(KeyCombination(keyCode: UInt32(kVK_ANSI_Keypad7), modifiers: [.option]).displayString, "⌥⌨7")
    }

    func testShortcutCapturePolicyAcceptsSafeGlobalChords() {
        XCTAssertNil(ShortcutCapturePolicy.validationError(for: KeyCombination(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: [.command]
        )))
        XCTAssertNil(ShortcutCapturePolicy.validationError(for: KeyCombination(
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: [.option, .shift]
        )))
        XCTAssertNil(ShortcutCapturePolicy.validationError(for: KeyCombination(
            keyCode: UInt32(kVK_F12),
            modifiers: []
        )))
    }

    func testShortcutCapturePolicyRejectsUnsafeOrUnsupportedChords() {
        XCTAssertEqual(
            ShortcutCapturePolicy.validationError(for: KeyCombination(
                keyCode: UInt32(kVK_ANSI_K),
                modifiers: []
            )),
            .missingRequiredModifier
        )
        XCTAssertEqual(
            ShortcutCapturePolicy.validationError(for: KeyCombination(
                keyCode: UInt32(kVK_ANSI_K),
                modifiers: [.shift]
            )),
            .missingRequiredModifier
        )
        XCTAssertEqual(
            ShortcutCapturePolicy.validationError(for: KeyCombination(
                keyCode: UInt32(kVK_Command),
                modifiers: [.command]
            )),
            .unsupportedKey
        )
        XCTAssertTrue(ShortcutCapturePolicy.isCancelKey(UInt32(kVK_Escape)))
    }

    func testShortcutModifierFlagsNormalizeToSupportedModifiers() {
        let modifiers = ShortcutModifiers(eventModifierFlags: [.capsLock, .command, .shift, .numericPad])

        XCTAssertEqual(modifiers, [.command, .shift])
        XCTAssertEqual(modifiers.eventModifierFlags, [.command, .shift])
    }

    func testShortcutPreferencesDetectConflictIncludingDisabledActions() {
        var preferences = ShortcutPreferences.defaultPreferences
        let combination = preferences.item(for: .deviceScreenshot).keyCombination
        var dragItem = preferences.item(for: .dragScreenshot)
        dragItem.keyCombination = combination
        dragItem.isEnabled = false
        preferences.setItem(dragItem)

        XCTAssertEqual(
            preferences.conflictingAction(for: combination, excluding: .deviceScreenshot),
            .dragScreenshot
        )
        XCTAssertNil(preferences.conflictingAction(
            for: CaptureShortcutAction.toggleRecording.defaultKeyCombination,
            excluding: .toggleRecording
        ))
    }

    func testShortcutAvailabilityValidatorBlocksDuplicatesBeforeRegistrationProbe() {
        let preferences = ShortcutPreferences.defaultPreferences
        let combination = preferences.item(for: .deviceScreenshot).keyCombination
        let capturedKey = ShortcutCapturedKey(combination: combination, charactersIgnoringModifiers: "3")
        var didProbeRegistration = false
        let validator = ShortcutAvailabilityValidator { _ in
            didProbeRegistration = true
            return true
        }

        XCTAssertEqual(
            validator.validationError(
                for: capturedKey,
                editing: .dragScreenshot,
                preferences: preferences,
                applicationMenu: NSMenu()
            ),
            .duplicate(.deviceScreenshot)
        )
        XCTAssertFalse(didProbeRegistration)
    }

    func testShortcutAvailabilityValidatorBlocksApplicationMenuCommands() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let menuItem = NSMenuItem(title: "Show Shortcuts", action: nil, keyEquivalent: "k")
        menuItem.keyEquivalentModifierMask = [.command]
        menuItem.isEnabled = true
        menu.addItem(menuItem)
        let capturedKey = ShortcutCapturedKey(
            combination: KeyCombination(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command]),
            charactersIgnoringModifiers: "k"
        )
        let validator = ShortcutAvailabilityValidator { _ in true }

        XCTAssertEqual(
            validator.validationError(
                for: capturedKey,
                editing: .deviceScreenshot,
                preferences: .defaultPreferences,
                applicationMenu: menu
            ),
            .applicationMenu("Show Shortcuts")
        )
    }

    func testShortcutAvailabilityValidatorReportsRegistrationFailure() {
        let capturedKey = ShortcutCapturedKey(
            combination: KeyCombination(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .option]),
            charactersIgnoringModifiers: "k"
        )
        let validator = ShortcutAvailabilityValidator { _ in false }

        XCTAssertEqual(
            validator.validationError(
                for: capturedKey,
                editing: .deviceScreenshot,
                preferences: .defaultPreferences,
                applicationMenu: NSMenu()
            ),
            .unavailable
        )
    }

    func testShortcutRecorderSessionTracksPreviewRejectionAndKeyRelease() {
        var session = ShortcutRecorderSession()
        session.begin(.deviceScreenshot)
        session.updateModifiers([.option, .shift])

        XCTAssertTrue(session.isRecording(.deviceScreenshot))
        XCTAssertEqual(session.previewModifiers, [.option, .shift])

        session.reject(.missingRequiredModifier)
        XCTAssertEqual(session.errorMessage, ShortcutCaptureValidationError.missingRequiredModifier.message)

        let combination = KeyCombination(keyCode: UInt32(kVK_ANSI_7), modifiers: [.option, .shift])
        session.accept(combination)
        XCTAssertTrue(session.isAwaitingRelease(.deviceScreenshot))
        XCTAssertNil(session.errorMessage)
        XCTAssertFalse(session.completeKeyRelease(UInt32(kVK_ANSI_8)))
        XCTAssertTrue(session.completeKeyRelease(UInt32(kVK_ANSI_7)))
        XCTAssertFalse(session.isActive)
    }

    func testGlobalHotKeyRegistrationPolicySuspendsWhileRecordingShortcut() {
        let item = ShortcutPreferences.defaultPreferences.item(for: .deviceScreenshot)

        XCTAssertTrue(GlobalRecordingHotKeyRegistrationPolicy.shouldRegister(
            action: .deviceScreenshot,
            item: item,
            captureState: .choosingMode,
            runtimeIsRecording: false,
            shortcutRecorderIsActive: false
        ))
        XCTAssertFalse(GlobalRecordingHotKeyRegistrationPolicy.shouldRegister(
            action: .deviceScreenshot,
            item: item,
            captureState: .choosingMode,
            runtimeIsRecording: false,
            shortcutRecorderIsActive: true
        ))
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
        var recorderStates: [Bool] = []
        let driver = SettingsDriver(createZoomsAutomatically: true)
        driver.configure(
            persistShortcuts: { shortcuts in
                persistedShortcuts = shortcuts
            },
            setShortcutRecorderActive: { isActive in
                recorderStates.append(isActive)
            }
        )

        var item = driver.state.shortcuts.item(for: .dragScreenshot)
        item.isEnabled = false
        driver.send(.shortcutItemChanged(item))

        XCTAssertFalse(driver.state.shortcuts.item(for: .dragScreenshot).isEnabled)
        XCTAssertEqual(persistedShortcuts?.item(for: .dragScreenshot).isEnabled, false)

        driver.send(.shortcutsResetToDefaults)
        XCTAssertTrue(driver.state.shortcuts.item(for: .dragScreenshot).isEnabled)

        driver.shortcutRecorderActive(true)
        driver.shortcutRecorderActive(false)
        XCTAssertEqual(recorderStates, [true, false])
    }

    func testAppModelShortcutTriggers() async {
        let model = AppModel(
            screenshotCapture: { _, _ in },
            startRecordingCapture: { _, _, _ in Date() },
            stopRecording: { URL(fileURLWithPath: "/tmp/test.mp4") }
        )

        model.setShortcutRecorderActive(true)
        model.setShortcutRecorderActive(true)
        model.setShortcutRecorderActive(false)
        XCTAssertTrue(model.isShortcutRecorderActive)
        model.setShortcutRecorderActive(false)
        XCTAssertFalse(model.isShortcutRecorderActive)

        model.cancelCapture()
        model.triggerDeviceScreenshot()
        XCTAssertEqual(model.captureMode, .screenshot)

        model.cancelCapture()
        model.triggerDragScreenshot()
        XCTAssertEqual(model.captureMode, .screenshot)

        model.cancelCapture()
        model.triggerDeviceScreenRecord()
        XCTAssertEqual(model.captureMode, .recording)

        model.cancelCapture()
        model.triggerDragScreenRecord()
        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertTrue(model.isDragRecordingPending)

        model.cancelCapture()
        XCTAssertFalse(model.isDragRecordingPending)
    }
}
