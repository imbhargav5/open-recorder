import Foundation
import XCTest
@testable import OpenRecorderMac

final class RustServiceClientTests: XCTestCase {
    private typealias JSONParameters = [String: Any]

    func testInvalidParametersFailBeforeLaunchingService() {
        let client = RustServiceClient(executableURL: nil)
        let invalidParameters: JSONParameters = ["value": Double.nan]

        XCTAssertThrowsError(
            try client.call("listProjects", params: invalidParameters, as: String.self)
        ) { error in
            guard case RustServiceError.invalidParameters = error else {
                XCTFail("Expected invalidParameters, got \(error).")
                return
            }
        }
    }

    func testMissingExecutableFailsBeforeDecodingRawParameters() {
        let client = RustServiceClient(executableURL: nil)
        let invalidUTF8 = Data([0xFF])

        XCTAssertThrowsError(
            try client.call("listProjects", paramsData: invalidUTF8, as: String.self)
        ) { error in
            guard case RustServiceError.missingExecutable = error else {
                XCTFail("Expected missingExecutable, got \(error).")
                return
            }
        }
    }

    func testLargeServiceResponseDoesNotDeadlockWhenStdoutExceedsPipeBuffer() throws {
        let serviceURL = try makeServiceScript(
            name: "large-response-service",
            body: """
            #!/bin/sh
            printf '{"ok":true,"result":"'
            head -c 70000 /dev/zero | tr '\\0' x
            printf '"}\\n'
            """
        )
        let client = RustServiceClient(executableURL: serviceURL)
        let completed = expectation(description: "service call completes")
        let result = LockedBox<Result<String, Error>>()

        DispatchQueue.global(qos: .userInitiated).async {
            result.set(Result { try client.call("listProjects", as: String.self) })
            completed.fulfill()
        }

        let waitResult = XCTWaiter.wait(for: [completed], timeout: 10)
        guard waitResult == .completed else {
            terminateServiceScript(at: serviceURL)
            XCTFail("RustServiceClient did not complete a response larger than the stdout pipe buffer: \(waitResult).")
            return
        }

        let payload = try XCTUnwrap(result.get()).get()
        XCTAssertEqual(payload.count, 70_000)
    }

    func testLargeServiceFailureDoesNotDeadlockWhenStderrExceedsPipeBuffer() throws {
        let serviceURL = try makeServiceScript(
            name: "large-error-service",
            body: """
            #!/bin/sh
            head -c 70000 /dev/zero | tr '\\0' x >&2
            exit 1
            """
        )
        let client = RustServiceClient(executableURL: serviceURL)
        let completed = expectation(description: "service call completes")
        let result = LockedBox<Result<String, Error>>()

        DispatchQueue.global(qos: .userInitiated).async {
            result.set(Result { try client.call("listProjects", as: String.self) })
            completed.fulfill()
        }

        let waitResult = XCTWaiter.wait(for: [completed], timeout: 10)
        guard waitResult == .completed else {
            terminateServiceScript(at: serviceURL)
            XCTFail("RustServiceClient did not complete a failure larger than the stderr pipe buffer: \(waitResult).")
            return
        }

        XCTAssertThrowsError(try XCTUnwrap(result.get()).get()) { error in
            guard case RustServiceError.processFailed(let message) = error else {
                XCTFail("Expected processFailed, got \(error).")
                return
            }
            XCTAssertEqual(message.count, 70_000)
        }
    }

    private func makeServiceScript(name: String, body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenRecorderMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent(name)
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return scriptURL
    }

    private func terminateServiceScript(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    func set(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        storage = value
    }

    func get() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
