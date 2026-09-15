import Foundation

/// Chooses the application's updater: Sparkle only when the running bundle
/// is an installed, Developer ID signed application; an inert controller
/// with the matching reason otherwise. The probes are injected closures so
/// every branch is testable without Sparkle or real code signatures.
@MainActor
enum SoftwareUpdateControllerFactory {
    static func make(
        bundleURL: @MainActor () -> URL,
        isDeveloperIDSigned: @MainActor (URL) -> Bool,
        makeDisabledController: @MainActor (SoftwareUpdateAvailability) -> SoftwareUpdateProviding,
        sparkleController: SoftwareUpdateProviding
    ) -> SoftwareUpdateProviding {
        let url = bundleURL()
        guard url.pathExtension == "app" else {
            return makeDisabledController(
                .disabled(
                    reason: L10n.string("Software updates run in the installed application.")
                )
            )
        }
        guard isDeveloperIDSigned(url) else {
            return makeDisabledController(
                .disabled(
                    reason: L10n.string("Software updates require the Developer ID signed release build.")
                )
            )
        }
        return sparkleController
    }
}
