import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Claude Desktop startup ownership failures")
struct ClaudeDesktopStartupOwnershipTests {
    @Test("An unreadable profile does not relinquish responsibility for restoration")
    func unreadableProfile() async {
        let store = ScriptedConfigurationStore(configuration: AppConfiguration(connected: true))
        let profile = ScriptedClaudeProfileManager(active: true)
        profile.failStatus()
        let coordinator = makeCoordinator(store: store, profile: profile)

        await #expect(throws: ScriptedClaudeProfileManager.Error.statusInjected) {
            _ = try await coordinator.start()
        }

        #expect(store.configuration.connected)
        #expect((await coordinator.snapshot()).configuration.connected)
        await coordinator.shutdown(mode: .handoff)
    }

    @Test("Empty routing restores an owned profile before clearing connected", arguments: [false, true])
    func emptyRouting(failsRestore: Bool) async throws {
        let store = ScriptedConfigurationStore(configuration: AppConfiguration(connected: true))
        let profile = ScriptedClaudeProfileManager(active: true)
        if failsRestore { profile.failRestores(on: [1]) }
        let coordinator = makeCoordinator(store: store, profile: profile)

        if failsRestore {
            await #expect(throws: ScriptedClaudeProfileManager.Error.restoreInjected) {
                _ = try await coordinator.start()
            }
            #expect(store.configuration.connected)
        } else {
            let started = try await coordinator.start()
            #expect(!started.configuration.connected)
            #expect(!store.configuration.connected)
        }
        #expect(profile.restoreCount == 1)
        await coordinator.shutdown(mode: .handoff)
    }

    @Test("Startup never restores a foreign profile")
    func foreignProfile() async throws {
        let store = ScriptedConfigurationStore(configuration: AppConfiguration(connected: true))
        let profile = ScriptedClaudeProfileManager(active: false)
        let coordinator = makeCoordinator(store: store, profile: profile)

        let started = try await coordinator.start()

        #expect(!started.configuration.connected)
        #expect(profile.restoreCount == 0)
        await coordinator.shutdown(mode: .handoff)
    }

    private func makeCoordinator(
        store: ScriptedConfigurationStore,
        profile: ScriptedClaudeProfileManager
    ) -> ApplicationCoordinator {
        ApplicationCoordinator(
            configurationStore: store,
            secretStore: MemorySecretStore(),
            profileManager: profile,
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
    }
}
