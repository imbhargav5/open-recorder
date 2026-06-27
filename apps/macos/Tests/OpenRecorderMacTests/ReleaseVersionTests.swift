import Foundation
import XCTest

final class ReleaseVersionTests: XCTestCase {
    private typealias PlistDictionary = [String: Any]

    func testInfoPlistVersionsMatchRustServiceVersion() throws {
        let plist = try loadInfoPlist()
        let cargoVersion = try loadRustServiceVersion()

        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, cargoVersion)
        XCTAssertEqual(plist["CFBundleVersion"] as? String, cargoVersion)
    }

    private func loadInfoPlist() throws -> PlistDictionary {
        let url = packageRoot()
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, format: &format)

        return try XCTUnwrap(plist as? PlistDictionary, "Resources/Info.plist should be a dictionary")
    }

    private func loadRustServiceVersion() throws -> String {
        let cargoTomlURL = packageRoot()
            .appendingPathComponent("../rust-service/Cargo.toml")
        let cargoToml = try String(contentsOf: cargoTomlURL, encoding: .utf8)
        let regex: NSRegularExpression = try NSRegularExpression(
            pattern: #"(?m)^version\s*=\s*"(\d+\.\d+\.\d+)"\s*$"#
        )
        let range: NSRange = NSRange(cargoToml.startIndex..<cargoToml.endIndex, in: cargoToml)

        let match = try XCTUnwrap(
            regex.firstMatch(in: cargoToml, range: range),
            "apps/rust-service/Cargo.toml should declare a semantic version"
        )
        let versionRange = try XCTUnwrap(
            Range(match.range(at: 1), in: cargoToml),
            "apps/rust-service/Cargo.toml version capture should map to a String range"
        )

        return String(cargoToml[versionRange])
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
