import XCTest
@testable import OpenRecorderMac

@MainActor
final class AppModelStateTests: XCTestCase {
    func testBeginRecordingMovesToSetupAndRequestsSelector() {
        let model = AppModel()

        model.beginCapture(.recording)

        XCTAssertEqual(model.captureMode, .recording)
        XCTAssertEqual(model.captureFlow, .recordingSetup)
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
    }

    func testBeginScreenshotMovesToSetupAndRequestsSelector() {
        let model = AppModel()

        model.beginCapture(.screenshot)

        XCTAssertEqual(model.captureMode, .screenshot)
        XCTAssertEqual(model.captureFlow, .screenshotSetup)
        XCTAssertEqual(model.windowCommand?.action, .showSourceSelector)
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
