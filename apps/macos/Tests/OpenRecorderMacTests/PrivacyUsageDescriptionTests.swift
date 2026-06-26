import Foundation
import XCTest

final class PrivacyUsageDescriptionTests: XCTestCase {
    private typealias PlistDictionary = [String: Any]

    func testInfoPlistDeclaresCameraAndMicrophoneUsageDescriptions() throws {
        let plist = try loadInfoPlist()

        XCTAssertEqual(plist["CFBundleName"] as? String, "Open Recorder")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "15.0")
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
        let documentType = try XCTUnwrap(
            (plist["CFBundleDocumentTypes"] as? [PlistDictionary])?.first,
            "Info.plist should declare a document type"
        )
        let exportedType = try XCTUnwrap(
            (plist["UTExportedTypeDeclarations"] as? [PlistDictionary])?.first,
            "Info.plist should export the Open Recorder project type"
        )

        XCTAssertEqual(documentType["CFBundleTypeExtensions"] as? [String], ["openrecorder"])
        XCTAssertEqual(documentType["CFBundleTypeName"] as? String, "Open Recorder Project")
        XCTAssertEqual(documentType["CFBundleTypeRole"] as? String, "Editor")
        XCTAssertEqual(documentType["LSHandlerRank"] as? String, "Owner")
        XCTAssertEqual(documentType["LSItemContentTypes"] as? [String], ["dev.openrecorder.project"])
        XCTAssertEqual(exportedType["UTTypeIdentifier"] as? String, "dev.openrecorder.project")
        XCTAssertEqual(exportedType["UTTypeDescription"] as? String, "Open Recorder Project")
        XCTAssertEqual(exportedType["UTTypeConformsTo"] as? [String], ["public.json"])
        XCTAssertEqual(
            exportedType["UTTypeTagSpecification"] as? [String: [String]],
            ["public.filename-extension": ["openrecorder"]]
        )
    }

    private func loadInfoPlist() throws -> PlistDictionary {
        let url = packageRoot()
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        return try XCTUnwrap(plist as? PlistDictionary, "Resources/Info.plist should be a dictionary")
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
