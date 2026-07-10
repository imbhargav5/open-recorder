import AppKit
import XCTest
@testable import OpenRecorderMac

@MainActor
final class StudioWindowCloseInterceptorTests: XCTestCase {
    func testCloseRequestWaitsForAsyncDecisionAndCoalescesRepeatedRequests() async {
        let firstRequestStarted = expectation(description: "First close request started")
        let firstDecisionReturned = expectation(description: "First close decision returned")
        let closePerformed = expectation(description: "Approved close performed")
        let gate = WindowCloseDecisionGate()
        var requestCount = 0
        let interceptor = StudioWindowCloseInterceptionView()
        let window = CloseRecordingWindow()
        window.onPerformClose = {
            closePerformed.fulfill()
        }
        interceptor.onCloseRequest = {
            requestCount += 1
            firstRequestStarted.fulfill()
            await gate.wait()
            firstDecisionReturned.fulfill()
            return false
        }

        XCTAssertFalse(interceptor.windowShouldClose(window))
        XCTAssertFalse(interceptor.windowShouldClose(window))
        await fulfillment(of: [firstRequestStarted], timeout: 1)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(window.performCloseCallCount, 0)

        await gate.open()
        await fulfillment(of: [firstDecisionReturned], timeout: 1)
        await Task.yield()
        XCTAssertEqual(window.performCloseCallCount, 0)

        interceptor.onCloseRequest = {
            requestCount += 1
            return true
        }
        XCTAssertFalse(interceptor.windowShouldClose(window))
        await fulfillment(of: [closePerformed], timeout: 1)
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(window.performCloseCallCount, 1)
        XCTAssertTrue(interceptor.windowShouldClose(window))
    }

    func testInterceptorHonorsAndRestoresExistingWindowDelegate() {
        let window = NSWindow()
        let originalDelegate = VetoingWindowDelegate()
        window.delegate = originalDelegate
        let interceptor = StudioWindowCloseInterceptionView()
        window.contentView = interceptor
        interceptor.attachToCurrentWindow()
        var requestCount = 0
        interceptor.onCloseRequest = {
            requestCount += 1
            return true
        }

        XCTAssertTrue(window.delegate === interceptor)
        XCTAssertFalse(interceptor.windowShouldClose(window))
        XCTAssertEqual(originalDelegate.requestCount, 1)
        XCTAssertEqual(requestCount, 0)

        interceptor.detach()
        XCTAssertTrue(window.delegate === originalDelegate)
    }

}

@MainActor
private final class CloseRecordingWindow: NSWindow {
    var onPerformClose: () -> Void = {}
    private(set) var performCloseCallCount = 0

    override func performClose(_ sender: Any?) {
        performCloseCallCount += 1
        onPerformClose()
    }
}

@MainActor
private final class VetoingWindowDelegate: NSObject, NSWindowDelegate {
    private(set) var requestCount = 0

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestCount += 1
        return false
    }
}

private actor WindowCloseDecisionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
