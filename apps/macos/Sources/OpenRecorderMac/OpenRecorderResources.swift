import Foundation

enum OpenRecorderResources {
    private static let resourceBundleName = "OpenRecorderMac_OpenRecorderMac.bundle"

    static func url(
        forResource name: String,
        withExtension fileExtension: String,
        subdirectory: String? = nil
    ) -> URL? {
        for root in resourceRoots {
            let url = resourceURL(
                root: root,
                name: name,
                fileExtension: fileExtension,
                subdirectory: subdirectory
            )
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private static let resourceRoots = uniqueExistingDirectories(candidateResourceRoots)

    private static var candidateResourceRoots: [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(resourceBundleName, isDirectory: true))
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true))

        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDirectory.appendingPathComponent(resourceBundleName, isDirectory: true))
            candidates.append(
                executableDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(resourceBundleName, isDirectory: true)
            )
        }

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(workingDirectory.appendingPathComponent(".build/debug/\(resourceBundleName)", isDirectory: true))
        candidates.append(workingDirectory.appendingPathComponent(".build/release/\(resourceBundleName)", isDirectory: true))
        candidates.append(workingDirectory.appendingPathComponent("apps/macos/.build/debug/\(resourceBundleName)", isDirectory: true))
        candidates.append(workingDirectory.appendingPathComponent("apps/macos/.build/release/\(resourceBundleName)", isDirectory: true))

        return candidates
    }

    private static func resourceURL(
        root: URL,
        name: String,
        fileExtension: String,
        subdirectory: String?
    ) -> URL {
        var url = root
        if let subdirectory, !subdirectory.isEmpty {
            for component in subdirectory.split(separator: "/") {
                url.appendPathComponent(String(component), isDirectory: true)
            }
        }
        url.appendPathComponent(name, isDirectory: false)
        url.appendPathExtension(fileExtension)
        return url
    }

    private static func uniqueExistingDirectories(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return nil
            }

            guard seen.insert(standardized.path).inserted else {
                return nil
            }

            return standardized
        }
    }
}
