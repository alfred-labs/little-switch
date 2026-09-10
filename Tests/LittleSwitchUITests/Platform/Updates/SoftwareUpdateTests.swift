import AppKit
import Foundation
import Testing

@testable import LittleSwitchUI

/// The updater's own policy: the factory alone decides which controller
/// runs, the disabled controller stays inert, and the menu item reaches the
/// delegate through the responder chain.
@Suite("Software update controller")
struct SoftwareUpdateTests {

    // MARK: Factory

    @Test("An unbundled run carries the not-installed reason")
    @MainActor
    func unbundledRunIsDisabled() {
        let chosen =
            SoftwareUpdateControllerFactory.make(
                bundleURL: { URL(fileURLWithPath: "/usr/local/bin") },
                isDeveloperIDSigned: { _ in true },
                makeDisabledController: { availability in
                    RecordingUpdateController(availability: availability)
                },
                sparkleController: RecordingUpdateController()
            ) as? RecordingUpdateController

        #expect(
            chosen?.availability
                == .disabled(reason: "Software updates run in the installed application.")
        )
    }

    @Test("A bundled but unsigned run carries the Developer ID reason")
    @MainActor
    func unsignedBundleIsDisabled() {
        let chosen =
            SoftwareUpdateControllerFactory.make(
                bundleURL: { URL(fileURLWithPath: "/tmp/LittleSwitch.app") },
                isDeveloperIDSigned: { _ in false },
                makeDisabledController: { availability in
                    RecordingUpdateController(availability: availability)
                },
                sparkleController: RecordingUpdateController()
            ) as? RecordingUpdateController

        #expect(
            chosen?.availability
                == .disabled(
                    reason: "Software updates require the Developer ID signed release build."
                )
        )
    }

    @Test("An installed Developer ID run takes the real updater")
    @MainActor
    func signedBundleTakesSparkle() {
        let sparkle = RecordingUpdateController()
        let chosen = SoftwareUpdateControllerFactory.make(
            bundleURL: { URL(fileURLWithPath: "/Applications/LittleSwitch.app") },
            isDeveloperIDSigned: { url in
                #expect(url.pathExtension == "app")
                return true
            },
            makeDisabledController: { availability in
                RecordingUpdateController(availability: availability)
            },
            sparkleController: sparkle
        )

        #expect(chosen === sparkle)
    }

    // MARK: Disabled controller

    @Test("The disabled controller ignores every member and reports its reason")
    @MainActor
    func disabledControllerIsInert() {
        let controller = DisabledSoftwareUpdateController(
            availability: .disabled(reason: "Not the release build.")
        )

        controller.start()
        controller.checkForUpdates(nil)
        controller.automaticallyChecksForUpdates = true
        controller.automaticallyDownloadsUpdates = true

        #expect(controller.automaticallyChecksForUpdates == false)
        #expect(controller.automaticallyDownloadsUpdates == false)
        #expect(controller.lastUpdateCheckDate == nil)
        #expect(
            controller.availability == .disabled(reason: "Not the release build.")
        )
    }

    // MARK: Menu wiring

    @Test("The app menu offers Check for Updates below About")
    func appMenuCheckForUpdatesItem() throws {
        let menu = ApplicationMenuFactory.make()
        let appItem = try #require(menu.items.first { $0.title == "LittleSwitch" })
        let appSubmenu = try #require(appItem.submenu)
        let about = try #require(
            appSubmenu.items.first {
                $0.action == NSSelectorFromString("orderFrontStandardAboutPanel:")
            }
        )
        let checkForUpdates = try #require(
            appSubmenu.items.first {
                $0.action == NSSelectorFromString("checkForUpdates:")
            }
        )

        #expect(checkForUpdates.title == "Check for Updates…")
        #expect(checkForUpdates.target == nil)
        #expect(checkForUpdates.keyEquivalent.isEmpty)
        #expect(
            appSubmenu.index(of: checkForUpdates) == appSubmenu.index(of: about) + 1
        )
    }

    @Test("The application delegate answers the menu's check selector")
    @MainActor
    func delegateImplementsCheckForUpdates() {
        #expect(
            LittleSwitchApplicationDelegate.instancesRespond(
                to: NSSelectorFromString("checkForUpdates:")
            )
        )
    }

    @Test("The Common settings card binds one switch to both Sparkle preferences")
    func commonCardCopy() throws {
        let source = try source(named: "Features/General/CommonSettingsView.swift")

        #expect(source.contains("\"Software updates\""))
        #expect(source.contains("\"Install updates automatically\""))
        #expect(source.contains("Button(\"Check for Updates Now…\")"))
        #expect(source.contains("updater.automaticallyChecksForUpdates = enabled"))
        #expect(source.contains("updater.automaticallyDownloadsUpdates = enabled"))
    }
}

@MainActor
private final class RecordingUpdateController: SoftwareUpdateProviding {
    let availability: SoftwareUpdateAvailability

    init(availability: SoftwareUpdateAvailability = .enabled) {
        self.availability = availability
    }

    func start() {}

    func checkForUpdates(_ sender: Any?) {}

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
}

private func source(named filename: String) throws -> String {
    let repository = RepositorySources.root
    return try String(
        contentsOf: repository.appendingPathComponent(
            "Sources/LittleSwitchUI/\(filename)"
        ),
        encoding: .utf8
    )
}
