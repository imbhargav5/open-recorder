import Foundation
import XCTest
@testable import OpenRecorderMac

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private typealias InfoPlistFixture = [String: String]

    func testUpdateCheckerIsEnabledForProductionBundleWithHTTPSFeed() throws {
        let bundle = try makeBundle(
            identifier: "dev.openrecorder.app",
            feedURLString: "https://openrecorder.dev/appcast.xml"
        )

        XCTAssertTrue(UpdateChecker.isEnabled(for: bundle))
    }

    func testUpdateCheckerAcceptsUppercaseHTTPSFeedScheme() throws {
        let bundle = try makeBundle(
            identifier: "dev.openrecorder.app",
            feedURLString: "HTTPS://openrecorder.dev/appcast.xml"
        )

        XCTAssertTrue(UpdateChecker.isEnabled(for: bundle))
    }

    func testUpdateCheckerIsDisabledForNonProductionBundleIdentifier() throws {
        let bundle = try makeBundle(
            identifier: "dev.openrecorder.debug",
            feedURLString: "https://openrecorder.dev/appcast.xml"
        )

        XCTAssertFalse(UpdateChecker.isEnabled(for: bundle))
    }

    func testUpdateCheckerIsDisabledWithoutBundleIdentifier() throws {
        let bundle = try makeBundle(
            identifier: nil,
            feedURLString: "https://openrecorder.dev/appcast.xml"
        )

        XCTAssertFalse(UpdateChecker.isEnabled(for: bundle))
    }

    func testUpdateCheckerIsDisabledForNonHTTPSFeed() throws {
        let bundle = try makeBundle(
            identifier: "dev.openrecorder.app",
            feedURLString: "http://openrecorder.dev/appcast.xml"
        )

        XCTAssertFalse(UpdateChecker.isEnabled(for: bundle))
    }

    func testUpdateCheckerIsDisabledForHTTPSFeedWithoutHost() throws {
        let bundle = try makeBundle(
            identifier: "dev.openrecorder.app",
            feedURLString: "https://"
        )

        XCTAssertFalse(UpdateChecker.isEnabled(for: bundle))
    }

    func testUpdateCheckerIsDisabledForMalformedFeedURL() throws {
        let bundle = try makeBundle(
            identifier: "dev.openrecorder.app",
            feedURLString: " ht tp://openrecorder.dev/appcast.xml"
        )

        XCTAssertFalse(UpdateChecker.isEnabled(for: bundle))
    }

    func testUpdateCheckerIsDisabledForEmptyFeedURL() throws {
        let bundle = try makeBundle(
            identifier: "dev.openrecorder.app",
            feedURLString: ""
        )

        XCTAssertFalse(UpdateChecker.isEnabled(for: bundle))
    }

    func testUpdateCheckerIsDisabledWithoutFeedURL() throws {
        let bundle = try makeBundle(
            identifier: "dev.openrecorder.app",
            feedURLString: nil
        )

        XCTAssertFalse(UpdateChecker.isEnabled(for: bundle))
    }

    private func makeBundle(identifier: String?, feedURLString: String?) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenRecorderMacTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathExtension("bundle")
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")

        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleURL)
        }
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var plist: InfoPlistFixture = [
            "CFBundlePackageType": "BNDL",
        ]
        if let identifier {
            plist["CFBundleIdentifier"] = identifier
        }
        if let feedURLString {
            plist["SUFeedURL"] = feedURLString
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: infoPlistURL)

        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}
