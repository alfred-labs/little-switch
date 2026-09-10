import Foundation
import Sparkle

/// Sparkle adapter. The standard updater controller carries Sparkle's own
/// UI, scheduling, and install flow; nothing here makes policy decisions —
/// the factory owns those, and this file only translates types.
@MainActor
final class SparkleSoftwareUpdateController: SoftwareUpdateProviding {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var started = false

    var availability: SoftwareUpdateAvailability {
        .enabled
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    func start() {
        guard !started else {
            return
        }
        started = true
        controller.startUpdater()
    }

    func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}
