import Foundation

enum ExportFileSafety {
    enum Failure: LocalizedError {
        case originalFile
        var errorDescription: String? { "Choose a different filename to preserve the original media." }
    }
    static func sameFile(_ first: URL, _ second: URL) -> Bool {
        if first.resolvingSymlinksInPath().standardizedFileURL == second.resolvingSymlinksInPath().standardizedFileURL { return true }
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let a = try? first.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject,
           let b = try? second.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject { return a == b }
        return false
    }

    /// Stage beside the destination so a failed copy cannot delete an existing export.
    static func install(source: URL, destination: URL) throws {
        let manager = FileManager.default
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".open-recorder-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: staged) }
        try manager.copyItem(at: source, to: staged)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staged)
        } else { try manager.moveItem(at: staged, to: destination) }
    }
}
