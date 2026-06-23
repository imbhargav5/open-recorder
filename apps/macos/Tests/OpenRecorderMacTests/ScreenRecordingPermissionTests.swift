import XCTest
@testable import OpenRecorderMac

@MainActor
final class ScreenRecordingPermissionTests: XCTestCase {
    func testGrantedScreenRecordingPermissionDoesNotRequestAgain() throws {
        var requestCount = 0
        var promptRequested = true
        let permission = ScreenRecordingPermission(client: ScreenRecordingPermissionClient(
            preflight: { true },
            request: {
                requestCount += 1
                return true
            },
            hasRequestedPrompt: { promptRequested },
            setRequestedPrompt: { promptRequested = $0 }
        ))
        let controller = CaptureController(screenRecordingPermission: permission)

        try controller.ensureScreenRecordingPermissionForTesting()

        XCTAssertEqual(requestCount, 0)
        XCTAssertFalse(promptRequested)
    }

    func testScreenRecordingPromptIsNotRepeatedAcrossRestarts() throws {
        var requestCount = 0
        var promptRequested = false
        let permissionClient = ScreenRecordingPermissionClient(
            preflight: { false },
            request: {
                requestCount += 1
                return false
            },
            hasRequestedPrompt: { promptRequested },
            setRequestedPrompt: { promptRequested = $0 }
        )
        let firstPermission = ScreenRecordingPermission(client: permissionClient)
        let firstController = CaptureController(screenRecordingPermission: firstPermission)

        XCTAssertThrowsError(try firstController.ensureScreenRecordingPermissionForTesting()) { error in
            guard case CaptureControllerError.screenRecordingPermissionRequired = error else {
                return XCTFail("Expected first request to report required permission, got \(error)")
            }
        }

        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(promptRequested)

        let restartedPermission = ScreenRecordingPermission(client: permissionClient)
        let restartedController = CaptureController(screenRecordingPermission: restartedPermission)
        XCTAssertThrowsError(try restartedController.ensureScreenRecordingPermissionForTesting()) { error in
            guard case CaptureControllerError.screenRecordingPermissionUnavailableAfterRequest = error else {
                return XCTFail("Expected repeated request to be suppressed, got \(error)")
            }
        }

        XCTAssertEqual(requestCount, 1)
    }

    func testDeniedScreenRecordingPermissionDoesNotRequestAgainInSameSession() throws {
        var requestCount = 0
        var promptRequested = false
        let permission = ScreenRecordingPermission(client: ScreenRecordingPermissionClient(
            preflight: { false },
            request: {
                requestCount += 1
                return false
            },
            hasRequestedPrompt: { promptRequested },
            setRequestedPrompt: { promptRequested = $0 }
        ))
        let controller = CaptureController(screenRecordingPermission: permission)

        XCTAssertThrowsError(try controller.ensureScreenRecordingPermissionForTesting()) { error in
            guard case CaptureControllerError.screenRecordingPermissionRequired = error else {
                return XCTFail("Expected first request to report required permission, got \(error)")
            }
        }
        XCTAssertThrowsError(try controller.ensureScreenRecordingPermissionForTesting()) { error in
            guard case CaptureControllerError.screenRecordingPermissionUnavailableAfterRequest = error else {
                return XCTFail("Expected same-session repeated request to be suppressed, got \(error)")
            }
        }

        XCTAssertEqual(requestCount, 1)
    }

    func testRepeatedScreenRecordingRequestCanBeForcedForPreviewRefresh() throws {
        var requestCount = 0
        var promptRequested = true
        let permission = ScreenRecordingPermission(client: ScreenRecordingPermissionClient(
            preflight: { false },
            request: {
                requestCount += 1
                return true
            },
            hasRequestedPrompt: { promptRequested },
            setRequestedPrompt: { promptRequested = $0 }
        ))

        let outcome = permission.requestGrant(allowRepeatedRequest: true)

        XCTAssertEqual(outcome, .granted)
        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(promptRequested)
    }

    func testReloadSourcesDoesNotRequestScreenRecordingPermission() async {
        var requestCount = 0
        let permission = ScreenRecordingPermission(client: ScreenRecordingPermissionClient(
            preflight: { false },
            request: {
                requestCount += 1
                return false
            },
            hasRequestedPrompt: { false },
            setRequestedPrompt: { _ in }
        ))
        let controller = CaptureController(screenRecordingPermission: permission)

        await controller.reloadSources()

        XCTAssertEqual(requestCount, 0)
        XCTAssertFalse(controller.sources.isEmpty)
    }
}
