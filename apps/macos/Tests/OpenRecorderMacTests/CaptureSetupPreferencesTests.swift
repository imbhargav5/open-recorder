import CoreGraphics
import XCTest
@testable import OpenRecorderMac

@MainActor
final class CaptureSetupPreferencesTests: XCTestCase {
    func testStoreRoundTripsModeKindAndLightweightSourceReference() throws {
        let suiteName = "CaptureSetupPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CaptureSetupPreferencesStore(defaults: defaults)
        let preferences = CaptureSetupPreferences(
            mode: .screenshot,
            preferredSourceKind: .window,
            sourceReference: .window(ownerBundleID: "com.example.Editor", name: "Document")
        )

        store.save(preferences)

        XCTAssertEqual(store.load(), preferences)
    }

    func testStoreFallsBackToRecordingAndScreensWhenNothingWasSaved() throws {
        let suiteName = "CaptureSetupPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(CaptureSetupPreferencesStore(defaults: defaults).load(), .default)
    }

    func testStoreFallsBackToDefaultsWhenSavedDataIsCorrupt() throws {
        let suiteName = "CaptureSetupPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "capture.setup")

        XCTAssertEqual(CaptureSetupPreferencesStore(defaults: defaults).load(), .default)
    }

    func testStoreCanReplaceCorruptDataWithAValidSetup() throws {
        let suiteName = "CaptureSetupPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CaptureSetupPreferencesStore(defaults: defaults)
        let expected = CaptureSetupPreferences(
            mode: .screenshot,
            preferredSourceKind: .area,
            sourceReference: .area(CaptureArea(x: 10, y: 20, width: 300, height: 200, displayID: 7))
        )
        defaults.set(Data([0xFF, 0x00, 0x01]), forKey: "capture.setup")

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testEverySourceReferenceKindSurvivesCodableRoundTrip() throws {
        let references: [CaptureSourceReference] = [
            .display(displayID: 42, displayIndex: 1, name: "Studio Display"),
            .window(ownerBundleID: "com.example.Editor", name: "Document"),
            .area(CaptureArea(x: 12, y: 24, width: 640, height: 360, displayID: 42))
        ]

        for reference in references {
            let data = try JSONEncoder().encode(reference)
            XCTAssertEqual(try JSONDecoder().decode(CaptureSourceReference.self, from: data), reference)
        }
    }

    func testSourceReferenceReportsItsMatchingKind() {
        XCTAssertEqual(
            CaptureSourceReference.display(displayID: 1, displayIndex: 0, name: "Display").sourceKind,
            .display
        )
        XCTAssertEqual(
            CaptureSourceReference.window(ownerBundleID: "com.example.App", name: "Window").sourceKind,
            .window
        )
        XCTAssertEqual(
            CaptureSourceReference.area(CaptureArea(x: 0, y: 0, width: 10, height: 10)).sourceKind,
            .area
        )
    }

    func testDisplayRestoresByExactIDBeforeGuardedIndexFallback() {
        let exact = makeDisplay(id: "display:exact", displayID: 41, index: 0, name: "Built-in Display")
        let sameIndexDifferentName = makeDisplay(id: "display:other", displayID: 99, index: 0, name: "Projector")
        let sources = [sameIndexDifferentName, exact]

        let exactReference = CaptureSourceReference.display(
            displayID: 41,
            displayIndex: 7,
            name: "Old Name"
        )
        let fallbackReference = CaptureSourceReference.display(
            displayID: 404,
            displayIndex: 0,
            name: "Built-in Display"
        )
        let unsafeFallback = CaptureSourceReference.display(
            displayID: 404,
            displayIndex: 0,
            name: "Missing Display"
        )

        XCTAssertEqual(exactReference.resolve(in: sources, displayFrames: [:]), exact)
        XCTAssertEqual(fallbackReference.resolve(in: sources, displayFrames: [:]), exact)
        XCTAssertNil(unsafeFallback.resolve(in: sources, displayFrames: [:]))
    }

    func testDisplayFallbackRejectsAmbiguousMatches() {
        let first = makeDisplay(id: "display:1", displayID: 1, index: 0, name: "Display")
        let second = makeDisplay(id: "display:2", displayID: 2, index: 0, name: "Display")
        let reference = CaptureSourceReference.display(displayID: 404, displayIndex: 0, name: "Display")

        XCTAssertNil(reference.resolve(in: [first, second], displayFrames: [:]))
    }

    func testDisplayResolutionRejectsAmbiguousExactIDsWithoutASafeFallback() {
        let first = makeDisplay(id: "display:1", displayID: 7, index: 0, name: "Left")
        let second = makeDisplay(id: "display:2", displayID: 7, index: 1, name: "Right")
        let reference = CaptureSourceReference.display(displayID: 7, displayIndex: nil, name: "Old")

        XCTAssertNil(reference.resolve(in: [first, second], displayFrames: [:]))
    }

    func testDisplayFallbackRequiresBothExactNameAndIndex() {
        let display = makeDisplay(id: "display:1", displayID: 99, index: 2, name: "Studio Display")

        XCTAssertNil(
            CaptureSourceReference.display(displayID: 404, displayIndex: 1, name: "Studio Display")
                .resolve(in: [display], displayFrames: [:])
        )
        XCTAssertNil(
            CaptureSourceReference.display(displayID: 404, displayIndex: 2, name: "Studio display")
                .resolve(in: [display], displayFrames: [:])
        )
        XCTAssertNil(
            CaptureSourceReference.display(displayID: nil, displayIndex: nil, name: "Studio Display")
                .resolve(in: [display], displayFrames: [:])
        )
    }

    func testWindowRestoresOnlyWhenBundleAndTitleHaveOneExactMatch() {
        let match = makeWindow(id: "window:1", bundleID: "com.example.Editor", name: "Document")
        let other = makeWindow(id: "window:2", bundleID: "com.example.Editor", name: "Other")
        let reference = CaptureSourceReference.window(ownerBundleID: "com.example.Editor", name: "Document")

        XCTAssertEqual(reference.resolve(in: [match, other], displayFrames: [:]), match)
        XCTAssertNil(reference.resolve(in: [match, match], displayFrames: [:]))
        XCTAssertNil(
            CaptureSourceReference.window(ownerBundleID: "com.example.Other", name: "Document")
                .resolve(in: [match], displayFrames: [:])
        )
    }

    func testWindowResolutionIsCaseSensitiveAndNeverMatchesDisplaySources() {
        let window = makeWindow(id: "window:1", bundleID: "com.example.Editor", name: "Document")
        let display = makeDisplay(id: "display:1", displayID: 1, index: 0, name: "Document")

        XCTAssertNil(
            CaptureSourceReference.window(ownerBundleID: "com.example.editor", name: "Document")
                .resolve(in: [window], displayFrames: [:])
        )
        XCTAssertNil(
            CaptureSourceReference.window(ownerBundleID: "com.example.Editor", name: "document")
                .resolve(in: [window], displayFrames: [:])
        )
        XCTAssertNil(
            CaptureSourceReference.window(ownerBundleID: "com.example.Editor", name: "Document")
                .resolve(in: [display], displayFrames: [:])
        )
    }

    func testAreaRestoresOnlyInsideAnExistingDisplay() {
        let validArea = CaptureArea(x: 100, y: 120, width: 640, height: 360, displayID: 7)
        let missingDisplay = CaptureArea(x: 100, y: 120, width: 640, height: 360, displayID: 8)
        let outsideDisplay = CaptureArea(x: 900, y: 700, width: 640, height: 360, displayID: 7)
        let frames: [UInt32: CGRect] = [7: CGRect(x: 0, y: 0, width: 1_200, height: 900)]

        XCTAssertEqual(
            CaptureSourceReference.area(validArea).resolve(in: [], displayFrames: frames)?.area,
            validArea
        )
        XCTAssertNil(CaptureSourceReference.area(missingDisplay).resolve(in: [], displayFrames: frames))
        XCTAssertNil(CaptureSourceReference.area(outsideDisplay).resolve(in: [], displayFrames: frames))
    }

    func testAreaRestorationAcceptsExactDisplayEdgesAndBuildsLightweightSource() throws {
        let area = CaptureArea(x: 100, y: 200, width: 800, height: 600, displayID: 7)
        let frames: [UInt32: CGRect] = [7: CGRect(x: 100, y: 200, width: 800, height: 600)]

        let source = try XCTUnwrap(CaptureSourceReference.area(area).resolve(in: [], displayFrames: frames))

        XCTAssertEqual(source.id, "area:interactive")
        XCTAssertEqual(source.kind, .area)
        XCTAssertEqual(source.name, "Selected Area")
        XCTAssertEqual(source.subtitle, "800 x 600")
        XCTAssertEqual(source.area, area)
        XCTAssertEqual(source.displayID, 7)
        XCTAssertNil(source.thumbnailData)
    }

    func testAreaRestorationRejectsMissingDisplayAndNonPositiveGeometry() {
        let frames: [UInt32: CGRect] = [7: CGRect(x: 0, y: 0, width: 1_000, height: 800)]
        let invalidAreas = [
            CaptureArea(x: 0, y: 0, width: 0, height: 100, displayID: 7),
            CaptureArea(x: 0, y: 0, width: 100, height: 0, displayID: 7),
            CaptureArea(x: 0, y: 0, width: -1, height: 100, displayID: 7),
            CaptureArea(x: 0, y: 0, width: 100, height: -1, displayID: 7),
            CaptureArea(x: 0, y: 0, width: 100, height: 100, displayID: nil)
        ]

        for area in invalidAreas {
            XCTAssertNil(CaptureSourceReference.area(area).resolve(in: [], displayFrames: frames), "\(area)")
        }
    }

    func testAreaRestorationRejectsEveryPartiallyOutOfBoundsDirection() {
        let frames: [UInt32: CGRect] = [7: CGRect(x: 100, y: 100, width: 500, height: 400)]
        let invalidAreas = [
            CaptureArea(x: 99, y: 100, width: 100, height: 100, displayID: 7),
            CaptureArea(x: 100, y: 99, width: 100, height: 100, displayID: 7),
            CaptureArea(x: 550, y: 100, width: 100, height: 100, displayID: 7),
            CaptureArea(x: 100, y: 450, width: 100, height: 100, displayID: 7)
        ]

        for area in invalidAreas {
            XCTAssertNil(CaptureSourceReference.area(area).resolve(in: [], displayFrames: frames), "\(area)")
        }
    }

    func testReferenceCreationRejectsUnsafeOrIncompleteSources() {
        var display = makeDisplay(id: "display:unsafe", displayID: nil, index: nil, name: "Display")
        XCTAssertNil(CaptureSourceReference(source: display))

        var window = makeWindow(id: "window:unsafe", bundleID: nil, name: "Document")
        XCTAssertNil(CaptureSourceReference(source: window))

        display.thumbnailData = Data(repeating: 1, count: 1_024)
        display.displayID = 7
        XCTAssertEqual(
            CaptureSourceReference(source: display),
            .display(displayID: 7, displayIndex: nil, name: "Display")
        )

        window.ownerBundleID = "com.example.Editor"
        XCTAssertEqual(
            CaptureSourceReference(source: window),
            .window(ownerBundleID: "com.example.Editor", name: "Document")
        )
    }

    func testWindowReferenceTrimsBundleIDAndRejectsWhitespaceOnlyIdentity() {
        var window = makeWindow(id: "window:1", bundleID: "  com.example.Editor  ", name: "Document")
        XCTAssertEqual(
            CaptureSourceReference(source: window),
            .window(ownerBundleID: "com.example.Editor", name: "Document")
        )

        window.ownerBundleID = "   "
        XCTAssertNil(CaptureSourceReference(source: window))

        window.ownerBundleID = "com.example.Editor"
        window.name = "  \n "
        XCTAssertNil(CaptureSourceReference(source: window))
    }

    func testAreaReferencePreservesOnlyGeometryAndNeverThumbnailData() {
        let area = CaptureArea(x: 10, y: 20, width: 300, height: 200, displayID: 7)
        var source = CaptureSource(
            id: "area:interactive",
            kind: .area,
            name: "Selected Area",
            subtitle: "300 x 200",
            displayIndex: nil,
            displayID: 7,
            windowID: nil,
            area: area,
            thumbnailData: Data(repeating: 9, count: 4_096)
        )

        XCTAssertEqual(CaptureSourceReference(source: source), .area(area))

        source.area = nil
        XCTAssertNil(CaptureSourceReference(source: source))
    }

    private func makeDisplay(
        id: String,
        displayID: UInt32?,
        index: Int?,
        name: String
    ) -> CaptureSource {
        CaptureSource(
            id: id,
            kind: .display,
            name: name,
            subtitle: "Display",
            displayIndex: index,
            displayID: displayID,
            windowID: nil,
            area: nil,
            thumbnailData: nil
        )
    }

    private func makeWindow(
        id: String,
        bundleID: String?,
        name: String
    ) -> CaptureSource {
        CaptureSource(
            id: id,
            kind: .window,
            name: name,
            subtitle: "Editor",
            displayIndex: nil,
            displayID: nil,
            windowID: 42,
            area: nil,
            thumbnailData: nil,
            ownerBundleID: bundleID,
            ownerName: "Editor"
        )
    }
}
