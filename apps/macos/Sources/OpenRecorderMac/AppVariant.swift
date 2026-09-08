import Foundation

/// Bundle identity is the source of truth; inherited shell variables cannot select app storage.
enum AppVariant {
    static let nightlyBundleIdentifier = "dev.openrecorder.app.nightly"
    static var isNightly: Bool { isNightly(bundleIdentifier: Bundle.main.bundleIdentifier) }
    static func isNightly(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == nightlyBundleIdentifier
    }
    static var storageDirectoryName: String { isNightly ? "OpenRecorderNightly" : "Open Recorder" }
    static func serviceEnvironment(
        inherited: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> [String: String] {
        var environment = inherited
        environment["OPEN_RECORDER_APP_VARIANT"] = isNightly(bundleIdentifier: bundleIdentifier) ? "nightly" : "production"
        return environment
    }
}
