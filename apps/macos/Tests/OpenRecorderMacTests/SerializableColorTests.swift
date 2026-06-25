import XCTest
@testable import OpenRecorderMac

final class SerializableColorTests: XCTestCase {
    func testHexInitializerTrimsHashAndWhitespace() {
        let color = SerializableColor(hex: " #1A2B3C ")

        XCTAssertEqual(color.red, 26.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(color.green, 43.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 60.0 / 255.0, accuracy: 0.0001)
    }

    func testHexInitializerPreservesProvidedAlpha() {
        let color = SerializableColor(hex: "#FFFFFF", alpha: 0.42)

        XCTAssertEqual(color.alpha, 0.42)
    }

    func testHexStringClampsOutOfRangeComponents() {
        let color = SerializableColor(red: -0.5, green: 0.5, blue: 1.5)

        XCTAssertEqual(color.hexString, "#0080FF")
    }

    func testCodableRoundTripPreservesAlpha() throws {
        let color = SerializableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)

        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(SerializableColor.self, from: data)

        XCTAssertEqual(decoded, color)
        XCTAssertEqual(decoded.alpha, 0.4)
    }
}
