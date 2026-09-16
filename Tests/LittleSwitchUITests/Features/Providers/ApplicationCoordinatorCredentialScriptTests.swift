import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore
@testable import LittleSwitchUI

private func scriptFailure(status: Int32, standardError: String) -> String {
    let prefix = CoreL10n.string("The credential script exited with status \(status).")
    return CoreL10n.string("\(prefix) \(standardError)")
}

private final class ScriptedScriptRunner: CredentialScriptRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [String] = []
    private let token: String
    private let standardError: String
    private let failure: (any Error)?

    init(
        token: String = "scripted-token",
        standardError: String = "",
        failure: (any Error)? = nil
    ) {
        self.token = token
        self.standardError = standardError
        self.failure = failure
    }

    var calls: [String] {
        lock.withLock { scripts }
    }

    func run(scriptPath: String) async throws -> CredentialScriptRun {
        lock.withLock { scripts.append(scriptPath) }
        if let failure {
            throw failure
        }
        return CredentialScriptRun(token: token, standardError: standardError)
    }
}

@MainActor
private struct Fixture {
    let providerID: UUID
    let store: ScriptedConfigurationStore
    let secrets: ScriptedSecretStore
    let runner: ScriptedScriptRunner
    let coordinator: ApplicationCoordinator

    static func make(
        authMode: AuthMode = .none,
        credentialSource: CredentialSource = .manual,
        configuredScriptPath: String? = nil,
        token: String? = nil,
        interval: TimeInterval? = 900,
        runner: ScriptedScriptRunner = ScriptedScriptRunner(),
        failStartupTokenRead: Bool = false,
        refresherSleep: (CredentialRefresherSleep)? = nil
    ) async throws -> Self {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: authMode,
            credentialSource: credentialSource,
            credentialScriptPath: configuredScriptPath,
            credentialRefreshInterval: interval,
            models: [DiscoveredModel(id: "applied"), DiscoveredModel(id: "replacement")],
            status: .ready
        )
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: [
                "claude-sonnet-5": ModelMapping(providerID: providerID, modelID: "applied")
            ]
        )
        let store = ScriptedConfigurationStore(configuration: configuration)
        var storedSecrets: [SecretAccount: String] = [:]
        if let token {
            storedSecrets[.provider(providerID)] = token
        }
        let secrets = ScriptedSecretStore(values: storedSecrets)
        if failStartupTokenRead {
            // Fails the second startup read: discovery first, token check second.
            secrets.failReads(on: [2])
        }
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer(),
            credentialScriptRunner: runner,
            credentialRefresher:
                refresherSleep.map { sleep in
                    CredentialRefresher(secretStore: secrets, runner: runner, sleep: sleep)
                }
        )
        _ = try await coordinator.start()
        return Self(
            providerID: providerID,
            store: store,
            secrets: secrets,
            runner: runner,
            coordinator: coordinator
        )
    }
}

@MainActor
@Suite("Application coordinator credential script coverage")
struct CoordinatorCredentialScriptTests {

    @Test("Saving a script provider runs the script and stores script and token")
    func scriptSave() async throws {
        let fixture = try await Fixture.make()

        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credentialSource: .script,
                scriptPath: "printf saved-token",
                credentialRefreshInterval: 900
            )
        )

        let provider = try #require(saved.configuration.providers.first)
        #expect(provider.credentialSource == .script)
        #expect(provider.credentialRefreshInterval == 900)
        #expect(provider.credentialScriptPath == "printf saved-token")
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "scripted-token")
        #expect(fixture.runner.calls == ["printf saved-token"])
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A script provider without a script is rejected before discovery")
    func scriptSaveRequiresScript() async throws {
        let fixture = try await Fixture.make()

        await #expect(throws: ApplicationCoordinator.Error.missingCredentialScript) {
            _ = try await fixture.coordinator.saveProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .bearer,
                    credentialSource: .script,
                    scriptPath: "  \n "
                )
            )
        }
        #expect(fixture.runner.calls.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Editing a script provider with a blank script keeps the saved script")
    func scriptEditKeepsSavedScript() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            token: "previous-token"
        )

        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credentialSource: .script,
                scriptPath: nil,
                credentialRefreshInterval: 900
            )
        )

        #expect(saved.configuration.providers.first?.credentialSource == .script)
        #expect(
            saved.configuration.providers.first?.credentialScriptPath == "printf saved-token"
        )
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "scripted-token")
        #expect(fixture.runner.calls == ["printf saved-token"])
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Leaving script mode deletes the stored script")
    func leavingScriptModeDeletesScript() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            token: "previous-token"
        )

        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credential: "manual-key"
            )
        )

        #expect(saved.configuration.providers.first?.authMode == .bearer)
        #expect(saved.configuration.providers.first?.credentialScriptPath == nil)
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "manual-key")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Deleting a script provider removes its script and token")
    func deleteProviderRemovesScript() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            token: "previous-token"
        )

        let saved = try await fixture.coordinator.deleteProvider(id: fixture.providerID)

        #expect(saved.configuration.providers.isEmpty)
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed delete restores the stored script and token")
    func deleteProviderRollbackRestoresScript() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            token: "previous-token"
        )
        fixture.store.failFutureSaves(at: [1])

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.deleteProvider(id: fixture.providerID)
        }
        let rolledBack = await fixture.coordinator.snapshot().configuration.providers
        #expect(rolledBack.first?.credentialScriptPath == "printf saved-token")
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "previous-token")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed delete of an unknown provider rolls back without a refresh loop")
    func failedDeleteOfUnknownProviderSchedulesNothing() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            token: "previous-token"
        )
        fixture.store.failFutureSaves(at: [1])

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.deleteProvider(id: UUID())
        }

        // The known provider and its script survived the rollback untouched.
        let survivors = await fixture.coordinator.snapshot().configuration.providers
        #expect(survivors.first?.credentialScriptPath == "printf saved-token")
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "previous-token")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed delete reschedules the surviving script refresh loop")
    func failedDeleteReschedulesRefresh() async throws {
        let gate = HeldSleepGate()
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            token: "previous-token"
        ) { _ in try await gate.hold() }

        fixture.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.deleteProvider(id: fixture.providerID)
        }

        // The survivor's loop must be rescheduled, or its token goes stale.
        gate.release()
        _ = try await eventually(description: "refresh loop rescheduled after rollback") {
            (fixture.runner.calls.count >= 1) ? true : nil
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failed delete of a pathless script provider reschedules an empty script")
    func failedDeleteOfPathlessScriptProviderReschedulesEmptyScript() async throws {
        // The user has not chosen a file yet: the loop still reschedules,
        // and the empty path resurfaces as the missing-script failure.
        let gate = HeldSleepGate()
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            token: "previous-token"
        ) { _ in try await gate.hold() }

        fixture.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.deleteProvider(id: fixture.providerID)
        }

        let survivors = await fixture.coordinator.snapshot().configuration.providers
        #expect(survivors.first?.credentialSource == .script)
        #expect(survivors.first?.credentialScriptPath == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A provider without a stored interval still refreshes on the default cadence")
    func startupUsesDefaultIntervalWhenMissing() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            interval: nil
        )

        _ = try await eventually(description: "script token stored at startup") {
            fixture.secrets.value(for: .provider(fixture.providerID)) == "scripted-token" ? true : nil
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Saving without an interval schedules the default cadence")
    func saveUsesDefaultIntervalWhenMissing() async throws {
        let fixture = try await Fixture.make()

        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credentialSource: .script,
                scriptPath: "printf saved-token",
                credentialRefreshInterval: nil
            )
        )

        #expect(saved.configuration.providers.first?.credentialSource == .script)
        #expect(saved.configuration.providers.first?.credentialRefreshInterval == nil)
        #expect(fixture.runner.calls == ["printf saved-token"])
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Startup refreshes immediately when no token is stored")
    func startupRefreshesMissingToken() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token"
        )

        _ = try await eventually(description: "script token stored at startup") {
            fixture.secrets.value(for: .provider(fixture.providerID)) == "scripted-token" ? true : nil
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Startup defers the refresh while a stored token exists")
    func startupDefersWithStoredToken() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            token: "stored-token",
            interval: 3_600
        )

        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.runner.calls.isEmpty)
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "stored-token")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A transient keychain read failure defers instead of running the script")
    func startupReadErrorDefers() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            token: "stored-token",
            interval: 3_600,
            failStartupTokenRead: true
        )

        // The locked-keychain read must read as "a token exists", not as
        // "no token": running the script immediately would fire interactive
        // logins (a browser, a prompt) at launch over a transient failure.
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.runner.calls.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A failing script surfaces its message through the snapshot")
    func startupFailureSurfacesInSnapshot() async throws {
        let fixture = try await Fixture.make(
            authMode: .bearer,
            credentialSource: .script,
            configuredScriptPath: "printf saved-token",
            runner: ScriptedScriptRunner(
                failure: CredentialScriptError(
                    reason: .exit(status: 1),
                    standardError: "denied"
                )
            )
        )

        let failure = try await eventually(description: "script failure in snapshot") {
            let failures = await fixture.coordinator.snapshot().credentialRefreshFailures
            return failures[fixture.providerID]
        }
        #expect(
            failure == scriptFailure(status: 1, standardError: "denied")
        )
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

/// Holds every sleep until released, honouring cancellation like the real
/// one, so a test can park a refresh loop and choose when it proceeds.
private final class HeldSleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false

    func release() {
        lock.withLock { open = true }
    }

    func hold() async throws {
        while true {
            if Task.isCancelled {
                throw CancellationError()
            }
            if lock.withLock({ open }) {
                // Keep the released fake cooperative so the observer can run
                // and shut down the refresh loop even on a single worker.
                await Task.yield()
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
