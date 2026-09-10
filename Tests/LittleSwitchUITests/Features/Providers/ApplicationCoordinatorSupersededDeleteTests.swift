import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

/// Deletes whose provider intent went stale mid-flight: the routing token
/// must return, and no refresh loop may be resurrected for a provider the
/// superseding mutation already removed.
@MainActor
@Suite("Application coordinator superseded deletes")
struct CoordinatorSupersededDeleteTests {
    @Test("A superseded delete releases the routing token before mutation")
    func deleteSupersededWhileWaitingForRoutingGuard() async throws {
        let fixture = try await ProviderEdgeCoverageFixture.make()
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

        let deletion = Task {
            try await fixture.coordinator.deleteProvider(id: fixture.providerID)
        }
        defer { deletion.cancel() }
        _ = try await eventually(
            description: "provider deletion intent"
        ) {
            await fixture.coordinator.currentProviderIntentForEdgeCoverage(
                providerID: fixture.providerID
            )
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
            _ = try await deletion.value
        }
        #expect(
            await fixture.coordinator.snapshot().configuration.providers.map(\.id)
                == [fixture.providerID]
        )
        await fixture.coordinator.stopGateway()
    }

    @Test("A superseded delete of a vanished provider schedules no refresh loop")
    func deleteSupersededAfterProviderVanishes() async throws {
        let fixture = try await ProviderEdgeCoverageFixture.make()
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

        let deletion = Task {
            try await fixture.coordinator.deleteProvider(id: fixture.providerID)
        }
        defer { deletion.cancel() }
        _ = try await eventually(
            description: "provider deletion intent"
        ) {
            await fixture.coordinator.currentProviderIntentForEdgeCoverage(
                providerID: fixture.providerID
            )
        }
        // A concurrent mutation both supersedes the intent and removes the
        // provider: the stale delete must roll back without resurrecting a
        // refresh loop for a provider that no longer exists.
        await fixture.coordinator.supersedeProviderIntentForEdgeCoverage(
            providerID: fixture.providerID
        )
        await fixture.coordinator.removeProviderForEdgeCoverage(
            providerID: fixture.providerID
        )
        blockingStore.releaseRead()
        _ = try? await guardBlocker.value

        await #expect(throws: ApplicationCoordinator.Error.providerMutationSuperseded) {
            _ = try await deletion.value
        }
        await fixture.coordinator.stopGateway()
    }
}
