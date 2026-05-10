import XCTest
@testable import OpenRecorderMac

@MainActor
final class AccessibilityPermissionTests: XCTestCase {
    func testGrantedAccessibilityPermissionDoesNotRequestAgain() {
        var requestCount = 0
        var promptRequested = true
        let permission = AccessibilityPermission(client: AccessibilityPermissionClient(
            isTrusted: { true },
            request: {
                requestCount += 1
                return true
            },
            hasRequestedPrompt: { promptRequested },
            setRequestedPrompt: { promptRequested = $0 }
        ))

        XCTAssertEqual(permission.currentState(), .granted)
        XCTAssertEqual(permission.requestGrant(), .granted)
        XCTAssertEqual(requestCount, 0)
        XCTAssertFalse(promptRequested)
    }

    func testAccessibilityPromptIsNotRepeatedAcrossRestarts() {
        var requestCount = 0
        var promptRequested = false
        let permissionClient = AccessibilityPermissionClient(
            isTrusted: { false },
            request: {
                requestCount += 1
                return false
            },
            hasRequestedPrompt: { promptRequested },
            setRequestedPrompt: { promptRequested = $0 }
        )
        let firstPermission = AccessibilityPermission(client: permissionClient)

        XCTAssertEqual(firstPermission.requestGrant(), .promptShownWithoutGrant)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(promptRequested)

        let restartedPermission = AccessibilityPermission(client: permissionClient)
        XCTAssertEqual(restartedPermission.requestGrant(), .promptAlreadyShown)
        XCTAssertEqual(requestCount, 1)
    }

    func testRepeatedAccessibilityRequestCanBeForced() {
        var requestCount = 0
        var promptRequested = true
        let permission = AccessibilityPermission(client: AccessibilityPermissionClient(
            isTrusted: { false },
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
}
