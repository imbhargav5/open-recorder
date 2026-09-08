import Foundation

enum OpenRecorderCaptureExclusion {
    static func shouldExcludeApplication(
        bundleIdentifier: String?,
        applicationName: String?,
        processID: pid_t?,
        currentProcessID: pid_t? = ProcessInfo.processInfo.processIdentifier,
        currentBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        if let processID,
           let currentProcessID,
           processID == currentProcessID {
            return true
        }

        let normalizedBundleIdentifier = cleaned(bundleIdentifier)?.lowercased()
        let normalizedCurrentBundleIdentifier = cleaned(currentBundleIdentifier)?.lowercased()
        if let normalizedBundleIdentifier,
           let normalizedCurrentBundleIdentifier,
           normalizedBundleIdentifier == normalizedCurrentBundleIdentifier {
            return true
        }

        // Other variants must remain capturable, including unbundled processes.
        // Names are not reliable identity: both variants use OpenRecorderMac internally.
        return false
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
