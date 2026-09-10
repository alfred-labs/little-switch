import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Status item visibility recovery")
@MainActor
struct StatusItemVisibilityRecoveryTests {
    @Test("The status item keeps one stable AppKit autosave identity")
    func stableAutosaveIdentity() {
        #expect(
            StatusItemIdentity.autosaveName
                == "\(ProductIdentity.bundleIdentifier).menu-bar"
        )
    }

    @Test("All AppKit visibility signals are required")
    func visibilitySignals() {
        #expect(
            StatusItemVisibilitySnapshot(
                statusItemVisible: true,
                windowVisible: true,
                occlusionVisible: true
            ).isPresented
        )
        #expect(
            !StatusItemVisibilitySnapshot(
                statusItemVisible: false,
                windowVisible: true,
                occlusionVisible: true
            ).isPresented
        )
        #expect(
            !StatusItemVisibilitySnapshot(
                statusItemVisible: true,
                windowVisible: false,
                occlusionVisible: true
            ).isPresented
        )
        #expect(
            !StatusItemVisibilitySnapshot(
                statusItemVisible: true,
                windowVisible: true,
                occlusionVisible: false
            ).isPresented
        )
    }

    @Test("A hidden episode triggers one recreation and resets after visibility returns")
    func oneRecoveryPerHiddenEpisode() {
        var policy = StatusItemVisibilityRecoveryPolicy()
        let hidden = StatusItemVisibilitySnapshot(
            statusItemVisible: true,
            windowVisible: false,
            occlusionVisible: false
        )
        let visible = StatusItemVisibilitySnapshot(
            statusItemVisible: true,
            windowVisible: true,
            occlusionVisible: true
        )

        let firstHiddenCheck = policy.shouldRecreate(for: hidden)
        let repeatedHiddenCheck = policy.shouldRecreate(for: hidden)
        let visibleCheck = policy.shouldRecreate(for: visible)
        let nextHiddenCheck = policy.shouldRecreate(for: hidden)

        #expect(
            [firstHiddenCheck, repeatedHiddenCheck, visibleCheck, nextHiddenCheck]
                == [true, false, false, true]
        )
    }

    @Test("The application delegate checks and rebuilds a missing status item")
    func delegateIntegration() throws {
        let repository = RepositorySources.root
        let delegateSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/Application/Lifecycle/LittleSwitchApplicationDelegate.swift"
            ),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/MenuBar/StatusItemVisibilityRecovery.swift"
            ),
            encoding: .utf8
        )

        #expect(delegateSource.contains("applicationDidBecomeActive"))
        #expect(delegateSource.contains("statusItemController?.applicationDidBecomeActive()"))
        #expect(controllerSource.contains("statusItemRecoveryPolicy.shouldRecreate"))
        #expect(controllerSource.contains("NSStatusBar.system.removeStatusItem(statusItem)"))
    }
}
