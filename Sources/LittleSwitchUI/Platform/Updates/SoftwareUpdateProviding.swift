import Foundation

/// The application's software-update surface. Production wires Sparkle
/// behind it; unbundled or unsigned runs carry an inert controller with a
/// human-readable reason. Every member is main-isolated: the settings card
/// and the application menu both read it from the main actor.
@MainActor
protocol SoftwareUpdateProviding: AnyObject {
    /// Arms the updater. Must run exactly once, before the settings window
    /// is built — Sparkle's property setters require a started updater.
    func start()

    /// Presents the standard update-check UI. Inert controllers ignore it.
    func checkForUpdates(_ sender: Any?)

    /// One switch drives both Sparkle preferences: checking and
    /// downloading stay together so updates never install unannounced.
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }

    var lastUpdateCheckDate: Date? { get }

    var availability: SoftwareUpdateAvailability { get }
}

enum SoftwareUpdateAvailability: Equatable {
    case enabled
    case disabled(reason: String)
}
