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

    func testHexInitializerAcceptsLowercaseValueWithoutHash() {
        let color = SerializableColor(hex: "0f80c0")

        XCTAssertEqual(color.red, 15.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(color.green, 128.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 192.0 / 255.0, accuracy: 0.0001)
    }

    func testHexInitializerFallsBackToBlackForInvalidInput() {
        let color = SerializableColor(hex: "not-a-color", alpha: 0.75)

        XCTAssertEqual(color.red, 0)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 0)
        XCTAssertEqual(color.alpha, 0.75)
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

    func testNSColorInitializerReadsSRGBComponents() {
        let color = SerializableColor(NSColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 0.6))

        XCTAssertEqual(color.red, 0.25, accuracy: 0.0001)
        XCTAssertEqual(color.green, 0.5, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 0.75, accuracy: 0.0001)
        XCTAssertEqual(color.alpha, 0.6, accuracy: 0.0001)
    }
}
