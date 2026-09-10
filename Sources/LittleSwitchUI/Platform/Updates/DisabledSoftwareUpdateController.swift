import Foundation

/// The updater runs only in the installed, Developer ID signed application.
/// Everywhere else — `swift run`, debug launches of the bare executable,
/// ad-hoc builds — this controller stands in: every member is inert and
/// reports why, so the settings card and menu item can explain themselves.
@MainActor
final class DisabledSoftwareUpdateController: SoftwareUpdateProviding {
    let availability: SoftwareUpdateAvailability

    init(availability: SoftwareUpdateAvailability) {
        self.availability = availability
    }

    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { _ = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { false }
        set { _ = newValue }
    }

    var lastUpdateCheckDate: Date? {
        nil
    }

    func start() {}

    func checkForUpdates(_ sender: Any?) {
        _ = sender
    }
}
