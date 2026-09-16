import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator provider coverage")
struct CoordinatorProviderCoverageTests {
    @Test("Provider validation rejects blank and duplicate names")
    func providerNameValidation() async throws {
        let fixture = try await ProviderCoverageFixture.make()

        await #expect(throws: ApplicationCoordinator.Error.invalidProviderName) {
            _ = try await fixture.coordinator.saveProvider(
                ProviderInput(name: " \n ", baseURL: "https://example.com", authMode: .none)
            )
        }
        await #expect(throws: ApplicationCoordinator.Error.duplicateProviderName) {
            _ = try await fixture.coordinator.saveProvider(
                ProviderInput(name: "local", baseURL: "https://example.com", authMode: .none)
            )
        }
        #expect((await fixture.coordinator.snapshot()).configuration.providers.count == 1)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A new provider is trimmed, discovered, and appended")
    func addProvider() async throws {
        let fixture = try await ProviderCoverageFixture.make()

        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                name: "  New Provider  ",
                baseURL: "https://example.com/v1/",
                authMode: .none
            )
        )

        let added = try #require(saved.configuration.providers.last)
        #expect(added.name == "New Provider")
        #expect(added.baseURL == "https://example.com/v1")
        #expect(added.maximumParallelRequests == Provider.defaultMaximumParallelRequests)
        #expect(added.models.first { $0.id == "applied" }?.contextWindowOverride == nil)
        #expect(added.status == .ready)
        #expect(saved.configuration.providers.count == 2)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A successful provider update replaces its credential and persists context")
    func replaceCredential() async throws {
        let fixture = try await ProviderCoverageFixture.make(
            authMode: .bearer,
            credential: "old-secret"
        )
        let state = try #require(await fixture.coordinator.gatewayState)
        let revisionBefore = try #require(
            await state.routingCapture().providerRevision(for: fixture.providerID)
        )

        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Updated Local",
                baseURL: "http://127.0.0.1:11435/v1/",
                authMode: .bearer,
                credential: "new-secret",
                contextOverrides: ["applied": 16_384],
                maximumParallelRequests: 13
            )
        )

        let persisted = fixture.store.configuration
        let provider = try #require(persisted.providers.first)
        #expect(saved.configuration == persisted)
        #expect(provider.name == "Updated Local")
        #expect(provider.baseURL == "http://127.0.0.1:11435/v1")
        #expect(provider.authMode == .bearer)
        #expect(provider.maximumParallelRequests == 13)
        #expect(
            provider.models
                == [
                    DiscoveredModel(id: "applied", contextWindowOverride: 16_384),
                    DiscoveredModel(id: "replacement"),
                ]
        )
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "new-secret")
        #expect(
            await state.routingCapture().providerRevision(for: fixture.providerID)
                == revisionBefore + 1
        )
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Persisted credential-only changes invalidate the provider revision")
    func persistedCredentialChangeInvalidatesRevision() async throws {
        let fixture = try await ProviderCoverageFixture.make(
            authMode: .bearer,
            credential: "old-secret"
        )
        let state = try #require(await fixture.coordinator.gatewayState)
        let captureBefore = await state.routingCapture()
        let revisionBefore = try #require(captureBefore.providerRevision(for: fixture.providerID))

        _ = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .bearer,
                credential: "new-secret"
            )
        )

        let captureAfter = await state.routingCapture()
        #expect(captureAfter.providerRevision(for: fixture.providerID) == revisionBefore + 1)
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "new-secret")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Provider refresh preserves the configured parallel request limit")
    func refreshPreservesMaximumParallelRequests() async throws {
        let fixture = try await ProviderCoverageFixture.make(maximumParallelRequests: 21)

        let refreshed = try await fixture.coordinator.refreshProvider(id: fixture.providerID)

        #expect(refreshed.configuration.providers.first?.maximumParallelRequests == 21)
        #expect(fixture.store.configuration.providers.first?.maximumParallelRequests == 21)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A successful credential-free update deletes its credential and persists context")
    func deleteCredential() async throws {
        let fixture = try await ProviderCoverageFixture.make(
            authMode: .bearer,
            credential: "old-secret"
        )

        let saved = try await fixture.coordinator.saveProvider(
            ProviderInput(
                id: fixture.providerID,
                name: "Local",
                baseURL: "http://127.0.0.1:11434",
                authMode: .none,
                contextOverrides: ["replacement": 32_768]
            )
        )

        let persisted = fixture.store.configuration
        let provider = try #require(persisted.providers.first)
        #expect(saved.configuration == persisted)
        #expect(provider.authMode == .none)
        #expect(
            provider.models
                == [
                    DiscoveredModel(id: "applied"),
                    DiscoveredModel(id: "replacement", contextWindowOverride: 32_768),
                ]
        )
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == nil)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Provider lookups and mappings reject missing identities")
    func missingProviderAndMapping() async throws {
        let fixture = try await ProviderCoverageFixture.make()
        let missing = ModelMapping(providerID: UUID(), modelID: "missing")

        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.refreshProvider(id: UUID())
        }
        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.setMapping(routeID: "not-a-route", mapping: nil)
        }
        await #expect(throws: ApplicationCoordinator.Error.invalidMapping) {
            _ = try await fixture.coordinator.setMapping(
                routeID: "claude-sonnet-5",
                mapping: missing
            )
        }

        let removed = try await fixture.coordinator.setMapping(
            routeID: "claude-sonnet-5",
            mapping: nil
        )
        #expect(removed.configuration.mappings.isEmpty)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Discovery failure leaves the provider explicitly unavailable")
    func refreshFailure() async throws {
        let transport = ScriptedCatalogTransport(
            executions: [.catalog, .catalog, .failure]
        )
        let fixture = try await ProviderCoverageFixture.make(transport: transport)

        await #expect(throws: ScriptedCatalogTransport.Error.executeInjected) {
            _ = try await fixture.coordinator.refreshProvider(id: fixture.providerID)
        }

        let provider = try #require(
            (await fixture.coordinator.snapshot()).configuration.providers.first
        )
        #expect(provider.status == .unavailable)
        #expect(provider.lastError == "Model discovery failed")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("A refresh save failure also leaves an unavailable diagnostic state")
    func refreshSaveFailure() async throws {
        let fixture = try await ProviderCoverageFixture.make()
        fixture.store.failFutureSaves(at: [1])

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await fixture.coordinator.refreshProvider(id: fixture.providerID)
        }

        let provider = try #require(
            (await fixture.coordinator.snapshot()).configuration.providers.first
        )
        #expect(provider.status == .unavailable)
        #expect(provider.lastError == "Model discovery failed")
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Provider saves restore replaced and absent credentials after persistence failure")
    func saveCredentialRollback() async throws {
        let existing = try await ProviderCoverageFixture.make(
            authMode: .bearer,
            credential: "old-secret"
        )
        existing.store.failFutureSaves(at: [1])
        let existingState = try #require(await existing.coordinator.gatewayState)
        let revisionBefore = try #require(
            await existingState.routingCapture().providerRevision(for: existing.providerID)
        )

        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await existing.coordinator.saveProvider(
                ProviderInput(
                    id: existing.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .bearer,
                    credential: "new-secret"
                )
            )
        }
        #expect(existing.secrets.value(for: .provider(existing.providerID)) == "old-secret")
        #expect(
            (await existing.coordinator.snapshot()).configuration
                == existing.configurationAfterStartup
        )
        #expect(
            await existingState.routingCapture().providerRevision(for: existing.providerID)
                == revisionBefore
        )
        await existing.coordinator.shutdown(mode: .handoff)

        let absent = try await ProviderCoverageFixture.make()
        absent.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await absent.coordinator.saveProvider(
                ProviderInput(
                    id: absent.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none
                )
            )
        }
        #expect(absent.secrets.value(for: .provider(absent.providerID)) == nil)
        await absent.coordinator.shutdown(mode: .handoff)
    }
}

extension CoordinatorProviderCoverageTests {
    @Test("Provider deletion restores configuration and credentials after each failure")
    func deleteRollback() async throws {
        let saveFailure = try await ProviderCoverageFixture.make(
            authMode: .bearer,
            credential: "secret"
        )
        saveFailure.store.failFutureSaves(at: [1])
        await #expect(throws: ScriptedConfigurationStore.Error.saveInjected) {
            _ = try await saveFailure.coordinator.deleteProvider(id: saveFailure.providerID)
        }
        #expect(saveFailure.secrets.value(for: .provider(saveFailure.providerID)) == "secret")
        #expect((await saveFailure.coordinator.snapshot()).configuration.providers.count == 1)
        await saveFailure.coordinator.shutdown(mode: .handoff)

        let deleteFailure = try await ProviderCoverageFixture.make(
            authMode: .bearer,
            credential: "secret"
        )
        deleteFailure.secrets.failNextDelete()
        await #expect(throws: ScriptedSecretStore.Error.deleteInjected) {
            _ = try await deleteFailure.coordinator.deleteProvider(id: deleteFailure.providerID)
        }
        #expect(deleteFailure.secrets.value(for: .provider(deleteFailure.providerID)) == "secret")
        #expect((await deleteFailure.coordinator.snapshot()).configuration.providers.count == 1)
        await deleteFailure.coordinator.shutdown(mode: .handoff)
    }

    @Test("Provider secret reads and nonpositive context overrides fail before persistence")
    func inputFailures() async throws {
        let fixture = try await ProviderCoverageFixture.make()
        fixture.secrets.failNextRead()
        await #expect(throws: ScriptedSecretStore.Error.readInjected) {
            _ = try await fixture.coordinator.saveProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none
                )
            )
        }

        await #expect(throws: ApplicationCoordinator.Error.invalidModelContext) {
            _ = try await fixture.coordinator.saveProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Local",
                    baseURL: "http://127.0.0.1:11434",
                    authMode: .none,
                    contextOverrides: ["applied": 0]
                )
            )
        }
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("Parallel request bounds fail before endpoint, secret, discovery, or persistence work")
    func maximumParallelRequestValidationIsSideEffectFree() async throws {
        for maximumParallelRequests in [0, 33] {
            let transport = ScriptedCatalogTransport()
            let fixture = try await ProviderCoverageFixture.make(
                authMode: .bearer,
                credential: "old-secret",
                transport: transport
            )
            // Startup intentionally returns before image probes finish. Drain
            // those unrelated requests before measuring this validation call.
            _ = try await eventually(description: "startup image probes before provider validation") {
                let progress = await fixture.coordinator.snapshot().imageProbeProgress[fixture.providerID]
                return progress?.running == false ? true : nil
            }
            let initialConfiguration = await fixture.coordinator.snapshot().configuration
            let initialExecutionCount = await transport.executeCount
            let initialSaves = fixture.store.saves
            fixture.secrets.failNextRead()

            await #expect(throws: ApplicationCoordinator.Error.invalidMaximumParallelRequests) {
                _ = try await fixture.coordinator.saveProvider(
                    ProviderInput(
                        id: fixture.providerID,
                        name: "Local",
                        baseURL: "not a valid URL",
                        authMode: .bearer,
                        credential: "new-secret",
                        maximumParallelRequests: maximumParallelRequests
                    )
                )
            }

            #expect(await fixture.coordinator.snapshot().configuration == initialConfiguration)
            #expect(await transport.executeCount == initialExecutionCount)
            #expect(fixture.store.saves == initialSaves)
            #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == "old-secret")
            await fixture.coordinator.shutdown(mode: .handoff)
        }
    }
}

@MainActor
private struct ProviderCoverageFixture {
    let providerID: UUID
    let store: ScriptedConfigurationStore
    let secrets: ScriptedSecretStore
    let coordinator: ApplicationCoordinator
    let configurationAfterStartup: AppConfiguration

    static func make(
        authMode: AuthMode = .none,
        credential: String? = nil,
        maximumParallelRequests: Int = Provider.defaultMaximumParallelRequests,
        transport: ScriptedCatalogTransport = ScriptedCatalogTransport()
    ) async throws -> Self {
        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            name: "Local",
            baseURL: "http://127.0.0.1:11434",
            authMode: authMode,
            models: [DiscoveredModel(id: "applied"), DiscoveredModel(id: "replacement")],
            status: .ready,
            maximumParallelRequests: maximumParallelRequests
        )
        let mapping = ModelMapping(providerID: providerID, modelID: "applied")
        let configuration = AppConfiguration(
            providers: [provider],
            mappings: ["claude-sonnet-5": mapping]
        )
        let store = ScriptedConfigurationStore(configuration: configuration)
        let secrets = ScriptedSecretStore(
            values: credential.map { [.provider(providerID): $0] } ?? [:]
        )
        let coordinator = ApplicationCoordinator(
            configurationStore: store,
            secretStore: secrets,
            profileManager: ScriptedClaudeProfileManager(),
            claudeController: ScriptedApplicationController(),
            discoveryTransport: transport,
            gatewayTransport: TestGatewayTransport(),
            gatewayServerOverride: TestGatewayServer()
        )
        let started = try await coordinator.start()
        return Self(
            providerID: providerID,
            store: store,
            secrets: secrets,
            coordinator: coordinator,
            configurationAfterStartup: started.configuration
        )
    }
}
