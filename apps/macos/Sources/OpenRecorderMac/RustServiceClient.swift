import Foundation

enum RustServiceError: LocalizedError {
    case missingExecutable
    case invalidParameters
    case processFailed(String)
    case badResponse
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "The Rust service binary was not found. Run `make build-macos` first."
        case .invalidParameters:
            "The request could not be encoded for the Rust service."
        case .processFailed(let message):
            message
        case .badResponse:
            "The Rust service returned an invalid response."
        case .serviceError(let message):
            message
        }
    }
}

struct RustServiceClient {
    private struct Response<T: Decodable>: Decodable {
        var ok: Bool
        var result: T?
        var error: String?
    }

    private let executableURL: URL?

    init() {
        if let override = ProcessInfo.processInfo.environment["OPEN_RECORDER_SERVICE_PATH"],
           !override.isEmpty {
            executableURL = URL(fileURLWithPath: override)
        } else {
            executableURL = Self.discoverServiceExecutable()
        }
    }

    var isAvailable: Bool {
        guard let executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    func call<T: Decodable>(
        _ method: String,
        params: [String: Any] = [:],
        as responseType: T.Type
    ) throws -> T {
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RustServiceError.missingExecutable
        }

        guard JSONSerialization.isValidJSONObject(params),
              let paramsData = try? JSONSerialization.data(withJSONObject: params),
              let paramsString = String(data: paramsData, encoding: .utf8) else {
            throw RustServiceError.invalidParameters
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--oneshot", method, paramsString]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RustServiceError.processFailed(message ?? "Rust service exited with status \(process.terminationStatus).")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response<T>.self, from: outputData)
        if response.ok, let result = response.result {
            return result
        }
        throw RustServiceError.serviceError(response.error ?? "Rust service returned no result.")
    }

    private static func discoverServiceExecutable() -> URL? {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidates = [
            currentDirectory.appendingPathComponent("../rust-service/target/debug/open-recorder-service"),
            currentDirectory.appendingPathComponent("apps/rust-service/target/debug/open-recorder-service"),
            currentDirectory.appendingPathComponent("../../apps/rust-service/target/debug/open-recorder-service"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/open-recorder-service"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/open-recorder-service")
        ]

        return candidates.first { fileManager.isExecutableFile(atPath: $0.standardizedFileURL.path) }?
            .standardizedFileURL
    }
}
