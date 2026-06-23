import Foundation
import XCTest

final class PrivacyUsageDescriptionTests: XCTestCase {
    func testInfoPlistDeclaresCameraAndMicrophoneUsageDescriptions() throws {
        let plist = try loadInfoPlist()

        XCTAssertEqual(
            plist["NSCameraUsageDescription"] as? String,
            "Open Recorder uses the camera when you choose to include a facecam in a screen recording."
        )
        XCTAssertEqual(
            plist["NSMicrophoneUsageDescription"] as? String,
            "Open Recorder uses the microphone when you choose to include narration in a screen recording."
        )
    }

    func testInfoPlistDocumentTypeMatchesExportedProjectType() throws {
        let plist = try loadInfoPlist()
        let documentTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]]
        let exportedTypes = plist["UTExportedTypeDeclarations"] as? [[String: Any]]

        XCTAssertEqual(documentTypes?.first?["LSItemContentTypes"] as? [String], ["dev.openrecorder.project"])
        XCTAssertEqual(exportedTypes?.first?["UTTypeIdentifier"] as? String, "dev.openrecorder.project")
    }

    private func loadInfoPlist() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        guard let dictionary = plist as? [String: Any] else {
            XCTFail("Resources/Info.plist should be a dictionary")
            return [:]
        }

        return dictionary
    }
}
