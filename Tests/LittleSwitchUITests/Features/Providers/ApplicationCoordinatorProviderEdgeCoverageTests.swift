import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application coordinator provider edge coverage")
struct CoordinatorProviderEdgeCoverageTests {
    @Test("A superseded save releases the routing token acquired after discovery")
    func saveSupersededWhileWaitingForRoutingGuard() async throws {
        let transport = GatedProviderCatalogTransport()
        let fixture = try await ProviderEdgeCoverageFixture.make(
            discoveryTransport: transport
        )
        let blockingStore = BlockingSecretReadStore()
        let guardBlocker = Task {
            try await fixture.state.routingMutationGuard.readCredential(
                providerID: UUID(),
                secretStore: blockingStore
            )
        }
        defer {
            blockingStore.releaseRead()
            guardBlocker.cancel()
        }
        #expect(await blockingStore.waitUntilReadIsBlocked())
        await transport.suspendNextRequest()

        let save = Task(priority: .high) {
            try await fixture.coordinator.saveProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Updated",
                    baseURL: "http://127.0.0.1:11435",
                    authMode: .none
                )
            )
        }
        defer {
            save.cancel()
            Task { await transport.releaseRequest() }
        }
        try await transport.waitUntilRequestWasCalled()
        await transport.releaseRequest()
        _ = try await eventually(
            description: "completed provider discovery requests"
        ) {
            await transport.executeCount >= 2 ? true : nil
        }
        for _ in 0..<64 {
            await Task.yield()
        }
        await fixture.coordinator.supersedeProviderIntentForEdgeCoverage(
            providerID: fixture.providerID
        )
        let actorGate = BlockingCoordinatorActorGate()
        let actorBlocker = Task(priority: .low) {
            await fixture.coordinator.blockActorForEdgeCoverage(actorGate)
        }
        defer {
            actorGate.release()
            actorBlocker.cancel()
        }
        #expect(await actorGate.waitUntilBlocked())
        blockingStore.releaseRead()
        _ = try? await guardBlocker.value
        try await waitUntilRoutingMutationIsActiveForEdgeCoverage(
            routingMutationGuard: fixture.state.routingMutationGuard,
            providerID: fixture.providerID,
            secretStore: fixture.secrets
        )
        actorGate.release()
        _ = await actorBlocker.value

        await #expect(throws: ApplicationCoordinator.Error.providerMutationSuperseded) {
            _ = try await save.value
        }
        await fixture.coordinator.stopGateway()
    }

    @Test("A newer save wins while the prior routing replacement is suspended")
    func saveSupersededAfterRoutingReplacement() async throws {
        let pool = OneShotSuspendedReconfigurationPool()
        let fixture = try await ProviderEdgeCoverageFixture.make(requestPool: pool)
        await pool.suspendNextReconfiguration()

        let firstSave = Task {
            try await fixture.coordinator.saveProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "First save",
                    baseURL: fixture.provider.baseURL,
                    authMode: .none
                )
            )
        }
        defer {
            firstSave.cancel()
            Task { await pool.releaseReconfiguration() }
        }
        try await pool.waitUntilReconfigurationWasCalled()
        let firstIntent = try #require(
            await fixture.coordinator.currentProviderIntentForEdgeCoverage(
                providerID: fixture.providerID
            )
        )

        let secondSave = Task {
            try await fixture.coordinator.saveProvider(
                ProviderInput(
                    id: fixture.providerID,
                    name: "Second save",
                    baseURL: fixture.provider.baseURL,
                    authMode: .none
                )
            )
        }
        defer { secondSave.cancel() }
        _ = try await eventually(
            description: "newer provider save intent"
        ) {
            let current = await fixture.coordinator.currentProviderIntentForEdgeCoverage(
                providerID: fixture.providerID
            )
            return current != nil && current != firstIntent ? true : nil
        }
        await pool.releaseReconfiguration()

        _ = try await valueWithinTimeout(
            firstSave,
            description: "superseded save routing replacement"
        )
        let final = try await valueWithinTimeout(
            secondSave,
            description: "newer save routing replacement"
        )
        #expect(final.configuration.providers.first?.name == "Second save")
        await fixture.coordinator.stopGateway()
    }

    @Test("A newer delete wins while the prior routing replacement is suspended")
    func deleteSupersededAfterRoutingReplacement() async throws {
        let pool = OneShotSuspendedReconfigurationPool()
        let fixture = try await ProviderEdgeCoverageFixture.make(requestPool: pool)
        await pool.suspendNextReconfiguration()

        let firstDelete = Task {
            try await fixture.coordinator.deleteProvider(id: fixture.providerID)
        }
        defer {
            firstDelete.cancel()
            Task { await pool.releaseReconfiguration() }
        }
        try await pool.waitUntilReconfigurationWasCalled()
        let firstIntent = try #require(
            await fixture.coordinator.currentProviderIntentForEdgeCoverage(
                providerID: fixture.providerID
            )
        )

        let secondDelete = Task {
            try await fixture.coordinator.deleteProvider(id: fixture.providerID)
        }
        defer { secondDelete.cancel() }
        _ = try await eventually(
            description: "newer provider deletion intent"
        ) {
            let current = await fixture.coordinator.currentProviderIntentForEdgeCoverage(
                providerID: fixture.providerID
            )
            return current != nil && current != firstIntent ? true : nil
        }
        await pool.releaseReconfiguration()

        _ = try await valueWithinTimeout(
            firstDelete,
            description: "superseded deletion routing replacement"
        )
        let final = try await valueWithinTimeout(
            secondDelete,
            description: "newer deletion routing replacement"
        )
        #expect(final.configuration.providers.isEmpty)
        await fixture.coordinator.stopGateway()
    }

    @Test("A refresh reports supersession if its provider vanishes after discovery")
    func refreshProviderRemovedAfterDiscovery() async throws {
        let transport = GatedProviderCatalogTransport()
        let fixture = try await ProviderEdgeCoverageFixture.make(
            discoveryTransport: transport
        )
        await transport.suspendNextRequest()
        let refresh = Task {
            try await fixture.coordinator.refreshProvider(id: fixture.providerID)
        }
        defer {
            refresh.cancel()
            Task { await transport.releaseRequest() }
        }
        try await transport.waitUntilRequestWasCalled()

        await fixture.coordinator.removeProviderForEdgeCoverage(
            providerID: fixture.providerID
        )
        await transport.releaseRequest()

        await #expect(throws: ApplicationCoordinator.Error.providerMutationSuperseded) {
            _ = try await refresh.value
        }
        await fixture.coordinator.stopGateway()
    }

    @Test("Delete reports rollback failure when credential restoration also fails")
    func deleteCredentialRollbackFailure() async throws {
        let fixture = try await ProviderEdgeCoverageFixture.make(credential: "secret")
        fixture.store.failFutureSaves(at: [1])
        fixture.secrets.failWrites(on: [1])

        await #expect(throws: ApplicationCoordinator.Error.rollbackFailed) {
            _ = try await fixture.coordinator.deleteProvider(id: fixture.providerID)
        }
        #expect(
            await fixture.coordinator.snapshot().configuration.providers.map(\.id)
                == [fixture.providerID]
        )
        #expect(fixture.secrets.value(for: .provider(fixture.providerID)) == nil)
        await fixture.coordinator.stopGateway()
    }

    @Test("Provider supersession has actionable localized copy")
    func providerMutationSupersededDescription() {
        #expect(
            ApplicationCoordinator.Error.providerMutationSuperseded.errorDescription
                == "The provider changed while this operation was running. Try again."
        )
    }
}
