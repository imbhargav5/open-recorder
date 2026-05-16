import AppKit
import Sparkle

@MainActor
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    private let controller: SPUStandardUpdaterController

    override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var updater: SPUUpdater {
        controller.updater
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
