import XCTest
@testable import OpenRecorderMac

final class AppVariantTests: XCTestCase {
    func testNightlyHelperEnvironmentCannotBeOverriddenByParent() {
        let environment = AppVariant.serviceEnvironment(
            inherited: ["HOME": "/test/home", "OPEN_RECORDER_APP_VARIANT": "production"],
            bundleIdentifier: "dev.openrecorder.app.nightly"
        )
        XCTAssertEqual(environment["HOME"], "/test/home")
        XCTAssertEqual(environment["OPEN_RECORDER_APP_VARIANT"], "nightly")
    }

    func testProductionAndDevKeepExistingStorage() {
        for identifier in ["dev.openrecorder.app", "dev.openrecorder.app.dev"] {
            let environment = AppVariant.serviceEnvironment(
                inherited: ["OPEN_RECORDER_APP_VARIANT": "nightly"], bundleIdentifier: identifier
            )
            XCTAssertEqual(environment["OPEN_RECORDER_APP_VARIANT"], "production")
        }
    }

    func testNightlyShortcutDefaultsAreDisabledAndCanBeEnabled() {
        var preferences = ShortcutPreferences.defaults(globalShortcutsEnabled: false)
        for action in CaptureShortcutAction.allCases {
            XCTAssertFalse(preferences.item(for: action).isEnabled)
        }
        var item = preferences.item(for: .toggleRecording)
        item.isEnabled = true
        preferences.setItem(item)
        XCTAssertTrue(preferences.item(for: .toggleRecording).isEnabled)
        XCTAssertTrue(ShortcutPreferences.defaults(globalShortcutsEnabled: true).item(for: .toggleRecording).isEnabled)
    }
}
