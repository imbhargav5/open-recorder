import Foundation
import XCTest
@testable import OpenRecorderMac

final class ProjectLibraryViewStateTests: XCTestCase {
    func testProjectQueryFiltersBySelectedMediaKind() {
        let recording = makeProject(id: "recording", title: "Demo", recordingPath: "/media/demo.mov")
        let screenshot = makeProject(id: "screenshot", title: "Still", screenshotPath: "/media/still.png")

        XCTAssertEqual(
            ProjectLibraryQuery.projects(
                from: [screenshot, recording],
                tab: .screenRecordings,
                searchText: "",
                sortOrder: []
            ).map(\.id),
            ["recording"]
        )
        XCTAssertEqual(
            ProjectLibraryQuery.projects(
                from: [recording, screenshot],
                tab: .screenshots,
                searchText: "",
                sortOrder: []
            ).map(\.id),
            ["screenshot"]
        )
    }

    func testProjectQueryMatchesAllNormalizedTermsAcrossMetadata() {
        let matching = makeProject(
            id: "matching",
            title: "Café walkthrough",
            sourceName: "Design Review",
            recordingPath: "/media/walkthrough.mov"
        )
        let other = makeProject(
            id: "other",
            title: "Café walkthrough",
            sourceName: "Engineering",
            recordingPath: "/media/engineering.mov"
        )

        let result = ProjectLibraryQuery.projects(
            from: [other, matching],
            tab: .screenRecordings,
            searchText: "  CAFE   review ",
            sortOrder: []
        )

        XCTAssertEqual(result.map(\.id), ["matching"])
    }

    func testProjectQueryUsesMediaFileNameWhenSourceNameIsAbsent() {
        let project = makeProject(
            id: "recording",
            title: "Untitled",
            recordingPath: "/media/Quarterly-Demo.mov"
        )

        let result = ProjectLibraryQuery.projects(
            from: [project],
            tab: .screenRecordings,
            searchText: "quarterly",
            sortOrder: []
        )

        XCTAssertEqual(result.map(\.id), ["recording"])
        XCTAssertEqual(projectSourceDisplayName(project), "Quarterly-Demo.mov")

        var blankSource = project
        blankSource.sourceName = "  \n"
        XCTAssertEqual(projectSourceDisplayName(blankSource), "Quarterly-Demo.mov")
    }

    func testDefaultProjectSortUsesActualDatesAcrossStoredFormats() {
        let january = makeProject(id: "january", title: "January", lastOpenedAt: "1767225600")
        let february = makeProject(id: "february", title: "February", lastOpenedAt: "2026-02-01T00:00:00Z")
        let unknown = makeProject(id: "unknown", title: "Unknown", lastOpenedAt: "not-a-date")

        let result = ProjectLibraryQuery.projects(
            from: [unknown, january, february],
            tab: .screenRecordings,
            searchText: "",
            sortOrder: []
        )

        XCTAssertEqual(result.map(\.id), ["february", "january", "unknown"])
    }

    func testProjectSortSupportsNativeTableColumns() {
        let alpha = makeProject(id: "alpha", title: "Alpha", sourceName: "Window B")
        let beta = makeProject(id: "beta", title: "Beta", sourceName: "Window A")

        let titleAscending = ProjectLibraryQuery.projects(
            from: [beta, alpha],
            tab: .screenRecordings,
            searchText: "",
            sortOrder: [ProjectLibraryComparator(field: .title)]
        )
        let sourceDescending = ProjectLibraryQuery.projects(
            from: [alpha, beta],
            tab: .screenRecordings,
            searchText: "",
            sortOrder: [ProjectLibraryComparator(field: .source, order: .reverse)]
        )

        XCTAssertEqual(titleAscending.map(\.id), ["alpha", "beta"])
        XCTAssertEqual(sourceDescending.map(\.id), ["alpha", "beta"])
    }

    func testInvalidProjectDateFormatsAsUnknownInsteadOfCurrentTime() {
        XCTAssertNil(projectDate("not-a-date"))
        XCTAssertEqual(formattedProjectDate("not-a-date"), "Unknown")
    }

    func testProjectAvailabilityControlsOpenBehaviorAndSpecificStatus() {
        var missingMedia = makeProject(id: "missing-media", title: "Missing media")
        missingMedia.availability = .missingMedia

        XCTAssertFalse(missingMedia.isOpenableFromLibrary)
        XCTAssertEqual(missingMedia.libraryAvailabilityLabel, "Media missing")

        var legacyMissing = makeProject(id: "legacy-missing", title: "Legacy missing")
        legacyMissing.missing = true
        legacyMissing.availability = .available

        XCTAssertFalse(legacyMissing.isOpenableFromLibrary)
        XCTAssertEqual(legacyMissing.libraryAvailabilityLabel, "Unavailable")
    }
}

final class SettingsViewPresentationStateTests: XCTestCase {
    func testServiceStartsAsNotCheckedInsteadOfClaimingFailure() {
        let state = settingsServicePresentationState(
            health: nil,
            isRefreshing: false,
            statusMessage: ""
        )

        XCTAssertEqual(state, .notChecked)
        XCTAssertEqual(state.value, "Not checked")
        XCTAssertFalse(state.isChecking)
    }

    func testRefreshingServiceKeepsTheLastKnownValueVisible() {
        let health = HealthPayload(service: "open-recorder", version: "1.2.3", platform: "macOS")

        let state = settingsServicePresentationState(
            health: health,
            isRefreshing: true,
            statusMessage: "Checking service..."
        )

        XCTAssertEqual(state, .checking(previousValue: "open-recorder 1.2.3"))
        XCTAssertEqual(state.value, "open-recorder 1.2.3")
        XCTAssertTrue(state.isChecking)
    }

    func testAvailableServiceUsesTheSuccessfulMachineStatus() {
        let health = HealthPayload(service: "open-recorder", version: "2.0", platform: "macOS")

        XCTAssertEqual(
            settingsServicePresentationState(
                health: health,
                isRefreshing: false,
                statusMessage: "Rust service ready"
            ),
            .available("open-recorder 2.0")
        )
    }

    func testFailedRefreshDoesNotHideBehindStaleHealth() {
        let health = HealthPayload(service: "open-recorder", version: "2.0", platform: "macOS")

        XCTAssertEqual(
            settingsServicePresentationState(
                health: health,
                isRefreshing: false,
                statusMessage: "Service stopped responding."
            ),
            .unavailable("Service stopped responding.")
        )
    }

    func testUnavailableServicePreservesAUsefulTrimmedFailure() {
        let state = settingsServicePresentationState(
            health: nil,
            isRefreshing: false,
            statusMessage: "  Service executable was not found.\n"
        )

        XCTAssertEqual(state, .unavailable("Service executable was not found."))
        XCTAssertEqual(state.value, "Unavailable")
        XCTAssertEqual(state.detail, "Service executable was not found.")
    }
}

private func makeProject(
    id: String,
    title: String,
    sourceName: String? = nil,
    recordingPath: String? = "/media/demo.mov",
    screenshotPath: String? = nil,
    lastOpenedAt: String = "1767225600"
) -> ProjectSummary {
    ProjectSummary(
        id: id,
        title: title,
        path: "/projects/\(id).openrecorder",
        recordingPath: recordingPath,
        screenshotPath: screenshotPath,
        sourceName: sourceName,
        createdAt: "1767225600",
        updatedAt: lastOpenedAt,
        lastOpenedAt: lastOpenedAt,
        missing: false
    )
}
