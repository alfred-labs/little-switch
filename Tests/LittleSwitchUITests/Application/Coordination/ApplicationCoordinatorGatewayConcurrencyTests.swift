import AsyncHTTPClient
import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Application coordinator gateway concurrency")
struct CoordinatorGatewayConcurrencyTests {
    @Test("Stop cancels and joins a suspended startup before returning")
    func stopJoinsSuspendedStartup() async throws {
        let fixture = await makeConcurrencyFixture()
        let start = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        let stopCompletions = CoordinatorCompletionCounter()
        let stop = Task {
            await fixture.coordinator.stopGateway()
            await stopCompletions.record()
        }

        let cancelled = await observedConcurrencySignal(fixture.controller.cancelledEvents)
        #expect(cancelled)
        #expect(await stopCompletions.completionCount == 0)
        await fixture.controller.releaseAll(throwing: CancellationError())

        await #expect(throws: CancellationError.self) {
            try await start.value
        }
        await stop.value
        #expect(await fixture.transportBuilder.makeCount == 1)
        #expect(fixture.factory.makeCount == 1)
        #expect(await fixture.controller.startCount == 1)
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
        #expect(!(await fixture.coordinator.snapshot()).proxyRunning)
    }

    @Test("Concurrent starts join one allocation and publish one server")
    func concurrentStartsShareStartup() async throws {
        let observer = ControllableGatewayStartupObserver()
        let fixture = await makeConcurrencyFixture(observer: observer)
        let first = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        let second = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(observer.joinedEvents)

        #expect(await fixture.transportBuilder.makeCount == 1)
        #expect(fixture.factory.makeCount == 1)
        #expect(await fixture.controller.startCount == 1)
        await fixture.controller.releaseAll()

        try await first.value
        try await second.value
        #expect((await fixture.coordinator.snapshot()).proxyRunning)

        await fixture.coordinator.stopGateway()
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
        #expect(await !fixture.controller.isRunning)
    }

    @Test("Cancelling one waiter preserves the shared startup for another")
    func cancelledWaiterDoesNotCancelSharedStartup() async throws {
        let observer = ControllableGatewayStartupObserver()
        let fixture = await makeConcurrencyFixture(observer: observer)
        let first = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        let cancelled = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(observer.joinedEvents)

        cancelled.cancel()
        await fixture.controller.releaseAll()

        try await first.value
        await #expect(throws: CancellationError.self) {
            try await cancelled.value
        }
        #expect(await fixture.transportBuilder.makeCount == 1)
        #expect(fixture.factory.makeCount == 1)
        #expect(await fixture.controller.startCount == 1)
        #expect((await fixture.coordinator.snapshot()).proxyRunning)

        await fixture.coordinator.stopGateway()
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
    }

    @Test("Cancelling the last waiter cancels and cleans the shared startup")
    func cancelledLastWaiterCancelsSharedStartup() async throws {
        let fixture = await makeConcurrencyFixture()
        let start = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)

        start.cancel()
        try await requireConcurrencySignal(fixture.controller.cancelledEvents)
        await fixture.controller.releaseAll(throwing: CancellationError())

        await #expect(throws: CancellationError.self) {
            try await start.value
        }
        #expect(await fixture.transportBuilder.makeCount == 1)
        #expect(fixture.factory.makeCount == 1)
        #expect(await fixture.controller.startCount == 1)
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
        #expect(!(await fixture.coordinator.snapshot()).proxyRunning)
    }

    @Test("A start after last-waiter cancellation waits for a fresh generation")
    func startAfterLastWaiterCancellationUsesFreshGeneration() async throws {
        let observer = ControllableGatewayStartupObserver()
        let fixture = await makeConcurrencyFixture(observer: observer)
        let abandoned = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        abandoned.cancel()
        try await requireConcurrencySignal(fixture.controller.cancelledEvents)

        let replacement = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(observer.cleanupWaitEvents)
        #expect(await fixture.transportBuilder.makeCount == 1)
        #expect(fixture.factory.makeCount == 1)
        #expect(await fixture.controller.startCount == 1)

        await fixture.controller.releaseAll(throwing: CancellationError())
        await #expect(throws: CancellationError.self) {
            try await abandoned.value
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        #expect(await fixture.transport.shutdownCount == 1)
        await fixture.controller.releaseAll()

        try await replacement.value
        #expect(await fixture.transportBuilder.makeCount == 2)
        #expect(fixture.factory.makeCount == 2)
        #expect(await fixture.controller.startCount == 2)
        #expect((await fixture.coordinator.snapshot()).proxyRunning)

        await fixture.coordinator.stopGateway()
        #expect(await fixture.controller.stopCount == 2)
        #expect(await fixture.transport.shutdownCount == 2)
    }

    @Test("Stop owns a completed startup that has not yet been published")
    func stopOwnsCompletedUnpublishedStartup() async throws {
        let observer = ControllableGatewayStartupObserver(suspendsPublication: true)
        let fixture = await makeConcurrencyFixture(observer: observer)
        let start = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        await fixture.controller.releaseAll()
        try await requireConcurrencySignal(observer.publicationEvents)

        await fixture.coordinator.stopGateway()

        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
        #expect(!(await fixture.coordinator.snapshot()).proxyRunning)
        await observer.releasePublication()
        await #expect(throws: CancellationError.self) {
            try await start.value
        }
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
    }

    @Test("Caller cancellation cleans a completed startup before publication")
    func cancellationCleansCompletedUnpublishedStartup() async throws {
        let observer = ControllableGatewayStartupObserver(suspendsPublication: true)
        let fixture = await makeConcurrencyFixture(observer: observer)
        let start = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        await fixture.controller.releaseAll()
        try await requireConcurrencySignal(observer.publicationEvents)

        start.cancel()
        await observer.releasePublication()

        await #expect(throws: CancellationError.self) {
            try await start.value
        }
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
        #expect(!(await fixture.coordinator.snapshot()).proxyRunning)
    }

    @Test("Public handoff shutdown cancels and joins an in-flight startup")
    func handoffJoinsSuspendedStartup() async throws {
        let fixture = await makeConcurrencyFixture()
        let start = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        let shutdownCompletions = CoordinatorCompletionCounter()
        let shutdown = Task {
            await fixture.coordinator.shutdown(mode: .handoff)
            await shutdownCompletions.record()
        }

        let cancelled = await observedConcurrencySignal(fixture.controller.cancelledEvents)
        #expect(cancelled)
        #expect(await shutdownCompletions.completionCount == 0)
        await fixture.controller.releaseAll(throwing: CancellationError())

        await #expect(throws: CancellationError.self) {
            try await start.value
        }
        await shutdown.value
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
        #expect(!(await fixture.coordinator.snapshot()).proxyRunning)
    }

    @Test("A delayed cancellation becomes stale after completed startup cleanup")
    func staleCancellationAfterCompletedCleanup() async throws {
        let observer = ControllableGatewayStartupObserver(
            suspendsPublication: true,
            suspendsCancellation: true
        )
        let fixture = await makeConcurrencyFixture(observer: observer)
        let start = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        await fixture.controller.releaseAll()
        try await requireConcurrencySignal(observer.publicationEvents)

        start.cancel()
        try await requireConcurrencySignal(observer.cancellationWaitEvents)
        await observer.releasePublication()

        await #expect(throws: CancellationError.self) {
            try await start.value
        }
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)

        await observer.releaseCancellation()
        try await requireConcurrencySignal(observer.cancellationCompletionEvents)
        #expect(!(await fixture.coordinator.snapshot()).proxyRunning)
    }

    @Test("Explicit stop invalidates cleanup restarts and joins repeated stops")
    func explicitStopInvalidatesCleanupRestart() async throws {
        let observer = ControllableGatewayStartupObserver(suspendsExplicitStops: true)
        let fixture = await makeConcurrencyFixture(observer: observer)
        let abandoned = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(fixture.controller.startedEvents)
        abandoned.cancel()
        try await requireConcurrencySignal(observer.cancellationCompletionEvents)

        let replacement = Task {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }
        try await requireConcurrencySignal(observer.cleanupWaitEvents)

        let firstStopObserved = Task {
            try await requireExplicitStopCount(1, events: observer.explicitStopEvents)
        }
        let firstStop = Task {
            await fixture.coordinator.stopGateway()
        }
        try await firstStopObserved.value

        await #expect(throws: CancellationError.self) {
            try await fixture.coordinator.startGateway(snapshot: emptyRoutingSnapshot())
        }

        let secondStopObserved = Task {
            try await requireExplicitStopCount(2, events: observer.explicitStopEvents)
        }
        let secondStop = Task {
            await fixture.coordinator.stopGateway()
        }
        try await secondStopObserved.value

        await fixture.controller.releaseAll(throwing: CancellationError())
        await observer.releaseExplicitStops()

        await #expect(throws: CancellationError.self) {
            try await abandoned.value
        }
        await #expect(throws: CancellationError.self) {
            try await replacement.value
        }
        await firstStop.value
        await secondStop.value
        #expect(await fixture.controller.stopCount == 1)
        #expect(await fixture.transport.shutdownCount == 1)
        #expect(!(await fixture.coordinator.snapshot()).proxyRunning)
    }

    @MainActor
    private func makeConcurrencyFixture(
        observer: any GatewayStartupObserving = LiveGatewayStartupObserver()
    ) -> CoordinatorConcurrencyFixture {
        let transport = ConcurrencyTrackingTransport()
        let transportBuilder = ConcurrencyTransportBuilder(transport: transport)
        let controller = ConcurrencyGatewayController()
        let factory = ConcurrencyGatewayFactory(controller: controller)
        let coordinator = ApplicationCoordinator(
            configurationStore: RecordingConfigurationStore(configuration: AppConfiguration()),
            secretStore: MemorySecretStore(),
            profileManager: TestClaudeProfileManager(),
            claudeController: TestClaudeController(),
            discoveryTransport: StaticCatalogTransport(),
            gatewayTransportBuilder: transportBuilder,
            gatewayFactory: factory,
            gatewayStartupObserver: observer
        )
        return CoordinatorConcurrencyFixture(
            coordinator: coordinator,
            transport: transport,
            transportBuilder: transportBuilder,
            controller: controller,
            factory: factory
        )
    }

    private func emptyRoutingSnapshot() -> RoutingSnapshot {
        RoutingSnapshot(generation: 0, providers: [], mappings: [:])
    }
}
