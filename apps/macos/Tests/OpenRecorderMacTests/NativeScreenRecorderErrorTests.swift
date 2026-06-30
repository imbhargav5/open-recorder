import XCTest
@testable import OpenRecorderMac

final class NativeScreenRecorderErrorTests: XCTestCase {
    func testUnsupportedSourceErrorDescriptionExplainsMissingAreaSelection() {
        XCTAssertEqual(
            NativeScreenRecorderError.unsupportedSource.errorDescription,
            "Selected-area video recording requires a valid area selection."
        )
    }
}
