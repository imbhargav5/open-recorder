import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class WindowSourceFilterTests: XCTestCase {
    private let currentProcessName = "OpenRecorderMac"
    private let normalFrame = CGRect(x: 0, y: 0, width: 900, height: 600)

    func testExcludesControlCenterSpotlightAndSystemUIWindows() {
        XCTAssertNil(displayInfo(
            title: "Control Center",
            ownerName: "Control Center",
            bundleIdentifier: "com.apple.controlcenter"
        ))
        XCTAssertNil(displayInfo(
            title: "com.apple.Spotlight",
            ownerName: "Spotlight",
            bundleIdentifier: "com.apple.Spotlight"
        ))
        XCTAssertNil(displayInfo(
            title: "Menu Bar",
            ownerName: "SystemUIServer",
            bundleIdentifier: "com.apple.systemuiserver"
        ))
    }

    func testExcludesTinyTransparentNonNormalAndOwnWindows() {
        XCTAssertNil(displayInfo(title: "Palette", ownerName: "Design App", frame: CGRect(x: 0, y: 0, width: 40, height: 40)))
        XCTAssertNil(displayInfo(title: "Ghost", ownerName: "Design App", alpha: 0))
        XCTAssertNil(displayInfo(title: "Overlay", ownerName: "Design App", layer: 4))
        XCTAssertNil(displayInfo(title: "Choose Source", ownerName: currentProcessName))
        XCTAssertNil(displayInfo(title: "Choose Source", ownerName: "Open Recorder", bundleIdentifier: "dev.openrecorder.app"))
        XCTAssertNil(displayInfo(title: "Open Recorder", ownerName: "Open Recorder", bundleIdentifier: nil))
        XCTAssertNil(displayInfo(title: "Open Recorder", ownerName: "Open Recorder", bundleIdentifier: "dev.openrecorder.app.dev"))
    }

    func testKeepsNormalAppWindows() {
        let displayInfo = displayInfo(
            title: "README.md",
            ownerName: "Code",
            bundleIdentifier: "com.microsoft.VSCode"
        )

        XCTAssertEqual(displayInfo?.name, "README.md")
        XCTAssertEqual(displayInfo?.subtitle, "Code")
    }

    func testKeepsBrowserWindows() {
        let displayInfo = displayInfo(
            title: "Open Recorder Pull Request",
            ownerName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )

        XCTAssertEqual(displayInfo?.name, "Open Recorder Pull Request")
        XCTAssertEqual(displayInfo?.subtitle, "Google Chrome")
    }

    func testUsesOwnerNameWhenTitleLooksLikeBundleIdentifier() {
        let displayInfo = displayInfo(
            title: "com.example.HiddenWindow",
            ownerName: "Example App",
            bundleIdentifier: "com.example.app"
        )

        XCTAssertEqual(displayInfo?.name, "Example App")
        XCTAssertEqual(displayInfo?.subtitle, "Example App")
    }

    func testTrimsWindowTitleAndOwnerNameForDisplay() {
        let displayInfo = displayInfo(
            title: "  Project Notes  \n",
            ownerName: "\tNotes App  ",
            bundleIdentifier: "com.example.notes"
        )

        XCTAssertEqual(displayInfo?.name, "Project Notes")
        XCTAssertEqual(displayInfo?.subtitle, "Notes App")
    }

    private func displayInfo(
        title: String?,
        ownerName: String?,
        bundleIdentifier: String? = nil,
        frame: CGRect? = nil,
        layer: Int? = 0,
        alpha: Double? = 1
    ) -> WindowSourceDisplayInfo? {
        WindowSourceFilter.displayInfo(
            for: WindowSourceMetadata(
                title: title,
                ownerName: ownerName,
                bundleIdentifier: bundleIdentifier,
                frame: frame ?? normalFrame,
                layer: layer,
                alpha: alpha
            ),
            currentProcessName: currentProcessName,
            currentApplicationName: "Open Recorder",
            currentBundleIdentifier: "dev.openrecorder.app"
        )
    }
}
