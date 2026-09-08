import XCTest
@testable import OpenRecorderMac

final class OpenRecorderCaptureExclusionTests: XCTestCase {
    func testExcludesTheCurrentProcess() {
        XCTAssertTrue(OpenRecorderCaptureExclusion.shouldExcludeApplication(
            bundleIdentifier: "com.example.unrelated",
            applicationName: "Example",
            processID: 4242,
            currentProcessID: 4242,
            currentBundleIdentifier: "dev.openrecorder.app.dev"
        ))
    }

    func testAllowsOtherVariantsAndExcludesOwnBundle() {
        XCTAssertFalse(OpenRecorderCaptureExclusion.shouldExcludeApplication(
            bundleIdentifier: "dev.openrecorder.app",
            applicationName: "Open Recorder",
            processID: 100,
            currentProcessID: 200,
            currentBundleIdentifier: "dev.openrecorder.app.dev"
        ))
        XCTAssertTrue(OpenRecorderCaptureExclusion.shouldExcludeApplication(
            bundleIdentifier: "dev.openrecorder.app.dev",
            applicationName: "Open Recorder Dev",
            processID: 100,
            currentProcessID: 200,
            currentBundleIdentifier: "dev.openrecorder.app.dev"
        ))
    }

    func testDoesNotExcludeAnotherProcessByNameAlone() {
        XCTAssertFalse(OpenRecorderCaptureExclusion.shouldExcludeApplication(
            bundleIdentifier: nil,
            applicationName: "OpenRecorderMac",
            processID: 100,
            currentProcessID: 200,
            currentBundleIdentifier: "dev.openrecorder.app.dev"
        ))
    }

    func testExcludesOpenRecorderApplicationsAfterTrimmingMetadata() {
        XCTAssertTrue(OpenRecorderCaptureExclusion.shouldExcludeApplication(
            bundleIdentifier: "  dev.openrecorder.app.dev\n",
            applicationName: "  Open Recorder Dev  ",
            processID: 100,
            currentProcessID: 200,
            currentBundleIdentifier: "dev.openrecorder.app.dev"
        ))
    }

    func testProductionAndNightlyCanCaptureEachOther() {
        for (current, target) in [
            ("dev.openrecorder.app", "dev.openrecorder.app.nightly"),
            ("dev.openrecorder.app.nightly", "dev.openrecorder.app")
        ] {
            XCTAssertFalse(OpenRecorderCaptureExclusion.shouldExcludeApplication(
                bundleIdentifier: target,
                applicationName: "OpenRecorderMac",
                processID: 100,
                currentProcessID: 200,
                currentBundleIdentifier: current
            ))
        }
    }

    func testAllowsUnrelatedApplications() {
        XCTAssertFalse(OpenRecorderCaptureExclusion.shouldExcludeApplication(
            bundleIdentifier: "com.example.editor",
            applicationName: "Editor",
            processID: 100,
            currentProcessID: 200,
            currentBundleIdentifier: "dev.openrecorder.app.dev"
        ))
    }
}
