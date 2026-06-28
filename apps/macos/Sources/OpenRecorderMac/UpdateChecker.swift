import AppKit
import Sparkle

@MainActor
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    private static let productionBundleIdentifier = "dev.openrecorder.app"

    private let controller: SPUStandardUpdaterController?
    let isEnabled: Bool

    override convenience init() {
        self.init(bundle: .main)
    }

    init(bundle: Bundle) {
        isEnabled = Self.isEnabled(for: bundle)
        controller = isEnabled
            ? SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            : nil
        super.init()
    }

    var updater: SPUUpdater? {
        controller?.updater
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    static func isEnabled(for bundle: Bundle) -> Bool {
        guard bundle.bundleIdentifier == productionBundleIdentifier,
              let feedURLString = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString),
              feedURL.scheme?.lowercased() == "https",
              feedURL.host?.isEmpty == false else {
            return false
        }

        return true
    }
}
