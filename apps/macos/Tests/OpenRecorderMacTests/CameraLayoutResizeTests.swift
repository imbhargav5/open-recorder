import XCTest
@testable import OpenRecorderMac

final class CameraLayoutResizeTests: XCTestCase {
    @MainActor
    private func driver() -> TimelineEditDriver {
        let driver = TimelineEditDriver()
        let clips = [CameraLayout.split, .cameraOnly, .sideBySide].enumerated().map { index, layout in
            var settings = defaultFacecamSettings(enabled: true)
            settings.layout = layout.rawValue
            settings.layoutTransition = .init(duration: 1.5, motion: .spring)
            return TimelineCameraClip(span: .init(start: Double(index * 2), end: Double(index * 2 + 2)), settings: settings)
        }
        driver.applySnapshot(.init(cameraClips: clips))
        return driver
    }

    @MainActor
    func testBothEdgesMoveSharedBoundariesWithoutChangingSettings() {
        let driver = driver()
        let original = driver.cameraClips
        let middle = original[1].id
        driver.resizeCameraClip(id: middle, edge: .leading, time: 1, duration: 6)
        XCTAssertEqual(driver.cameraClips.map(\.span), [.init(start: 0, end: 1), .init(start: 1, end: 4), .init(start: 4, end: 6)])
        driver.resizeCameraClip(id: middle, edge: .trailing, time: 5, duration: 6)
        XCTAssertEqual(driver.cameraClips.map(\.span), [.init(start: 0, end: 1), .init(start: 1, end: 5), .init(start: 5, end: 6)])
        XCTAssertEqual(driver.cameraClips.map(\.settings), original.map(\.settings))
        XCTAssertEqual(driver.cameraClips.map(\.id), original.map(\.id))
        XCTAssertEqual(driver.snapshot.activeCameraSettings(at: 1.1, duration: 6, fallback: nil)?.resolvedLayout, .cameraOnly)
        XCTAssertEqual(driver.snapshot.activeCameraSettings(at: 5.1, duration: 6, fallback: nil)?.resolvedLayout, .sideBySide)
    }

    @MainActor
    func testResizeClampsBeforeNeighborsCollapseAndAtVideoBounds() {
        let driver = driver()
        let id = driver.cameraClips[1].id
        driver.resizeCameraClip(id: id, edge: .leading, time: -100, duration: 6)
        XCTAssertEqual(driver.cameraClips[0].span.duration, 0.1, accuracy: 0.00001)
        driver.resizeCameraClip(id: id, edge: .trailing, time: 100, duration: 6)
        XCTAssertEqual(driver.cameraClips[2].span.duration, 0.1, accuracy: 0.00001)
        driver.resizeCameraClip(id: id, edge: .leading, time: 100, duration: 6)
        XCTAssertEqual(driver.cameraClips[1].span.duration, 0.1, accuracy: 0.00001)
        driver.resizeCameraClip(id: driver.cameraClips[0].id, edge: .leading, time: -100, duration: 6)
        driver.resizeCameraClip(id: driver.cameraClips[2].id, edge: .trailing, time: 100, duration: 6)
        XCTAssertEqual(driver.cameraClips.first?.span.start, 0)
        XCTAssertEqual(driver.cameraClips.last?.span.end, 6)
        let before = driver.snapshot
        driver.resizeCameraClip(id: id, edge: .leading, time: .nan, duration: 6)
        XCTAssertEqual(driver.snapshot, before)
    }

    @MainActor
    func testWholeDragIsOneUndoAndResizedTimingPersists() throws {
        let driver = driver()
        let original = driver.snapshot
        let id = driver.cameraClips[1].id
        driver.beginUndoTransaction()
        for end in [4.2, 4.6, 5] { driver.resizeCameraClip(id: id, edge: .trailing, time: end, duration: 6) }
        driver.endUndoTransaction()
        let changed = driver.snapshot
        XCTAssertEqual(try JSONDecoder().decode(TimelineEditSnapshot.self, from: JSONEncoder().encode(changed)), changed)
        driver.undo()
        XCTAssertEqual(driver.snapshot, original)
        driver.redo()
        XCTAssertEqual(driver.snapshot, changed)
    }

    @MainActor
    func testOutsideEdgesTrimAndExistingGapsDoNotCreateOverlaps() {
        let driver = driver()
        let first = driver.cameraClips[0].id, last = driver.cameraClips[2].id
        driver.resizeCameraClip(id: first, edge: .leading, time: 0.5, duration: 6)
        driver.resizeCameraClip(id: last, edge: .trailing, time: 5.5, duration: 6)
        XCTAssertEqual(driver.cameraClips[0].span.start, 0.5)
        XCTAssertEqual(driver.cameraClips[2].span.end, 5.5)
        XCTAssertNil(driver.snapshot.activeCameraSettings(at: 0.25, duration: 6, fallback: nil))
        XCTAssertNil(driver.snapshot.activeCameraSettings(at: 5.75, duration: 6, fallback: nil))
        var snapshot = driver.snapshot
        snapshot.cameraClips[1].span.start = 3
        driver.applySnapshot(snapshot)
        driver.resizeCameraClip(id: first, edge: .trailing, time: 4, duration: 6)
        XCTAssertEqual(driver.cameraClips[0].span.end, 3)
        XCTAssertEqual(driver.cameraClips[1].span.start, 3)
    }

    @MainActor
    func testExtendingShortCameraOnlySegmentRestoresFullTransitionTime() {
        let driver = driver()
        var snapshot = driver.snapshot
        snapshot.cameraClips[1].span.end = 2.76
        snapshot.cameraClips[2].span.start = 2.76
        driver.applySnapshot(snapshot)
        let canvas = CGSize(width: 640, height: 360)
        let crop = CGRect(origin: .zero, size: canvas)
        let target = CameraLayoutPresentation.layout(driver.cameraClips[1].settings, canvas: canvas, crop: crop, styling: .none)
        func pose(_ time: Double) -> CameraLayoutPresentation {
            CameraLayoutMotion.presentation(edits: driver.snapshot, plan: .build(duration: 6, edits: driver.snapshot), time: time,
                duration: 6, fallback: nil, canvas: canvas, crop: crop, styling: .none)
        }
        XCTAssertEqual(pose(2.759).camera.width, target.camera.width, accuracy: 0.001)
        driver.resizeCameraClip(id: driver.cameraClips[1].id, edge: .trailing, time: 4, duration: 6)
        XCTAssertNotEqual(pose(2.76), target)
        XCTAssertEqual(pose(3.5), target)
        XCTAssertEqual(driver.cameraClips[1].settings.resolvedLayoutTransition.duration, 1.5)
    }
}
