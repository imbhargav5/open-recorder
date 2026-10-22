import XCTest
@testable import OpenRecorderMac

@MainActor
final class NativeScreenRecorderErrorTests: XCTestCase {
    func testUnsupportedSourceErrorDescriptionExplainsMissingAreaSelection() {
        XCTAssertEqual(
            NativeScreenRecorderError.unsupportedSource.errorDescription,
            "Selected-area video recording requires a valid area selection."
        )
    }

    func testAlreadyStoppedScreenCaptureStreamIsRecognized() {
        let error = NSError(domain: "SCStreamErrorDomain", code: -3808)

        XCTAssertTrue(NativeScreenRecorder.isAlreadyStoppedStreamError(error))
    }

    func testOtherScreenCaptureErrorsRemainFailures() {
        let error = NSError(domain: "SCStreamErrorDomain", code: -3821)

        XCTAssertFalse(NativeScreenRecorder.isAlreadyStoppedStreamError(error))
    }
}
