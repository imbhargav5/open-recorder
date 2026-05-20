import Foundation
import XCTest

final class ReleaseVersionTests: XCTestCase {
    func testInfoPlistVersionsMatchRustServiceVersion() throws {
        let plist = try loadInfoPlist()
        let cargoVersion = try loadRustServiceVersion()

        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, cargoVersion)
        XCTAssertEqual(plist["CFBundleVersion"] as? String, cargoVersion)
    }

    private func loadInfoPlist() throws -> [String: Any] {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        guard let dictionary = plist as? [String: Any] else {
            XCTFail("Resources/Info.plist should be a dictionary")
            return [:]
        }

        return dictionary
    }

    private func loadRustServiceVersion() throws -> String {
        let cargoTomlURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../rust-service/Cargo.toml")
        let cargoToml = try String(contentsOf: cargoTomlURL, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(?m)^version\s*=\s*"(\d+\.\d+\.\d+)""#)
        let range = NSRange(cargoToml.startIndex..<cargoToml.endIndex, in: cargoToml)

        guard let match = regex.firstMatch(in: cargoToml, range: range),
              let versionRange = Range(match.range(at: 1), in: cargoToml) else {
            XCTFail("apps/rust-service/Cargo.toml should declare a semantic version")
            return ""
        }

        return String(cargoToml[versionRange])
    }
}
