import AsyncHTTPClient
import Foundation
import LittleSwitchCore
import LittleSwitchTransport

@testable import LittleSwitchUI

struct CoordinatorConcurrencyFixture: Sendable {
    let coordinator: ApplicationCoordinator
    let transport: ConcurrencyTrackingTransport
    let transportBuilder: ConcurrencyTransportBuilder
    let controller: ConcurrencyGatewayController
    let factory: ConcurrencyGatewayFactory
}

actor ConcurrencyTransportBuilder: GatewayTransportBuilding {
    private let transport: any UpstreamTransport
    private(set) var makeCount = 0

    init(transport: any UpstreamTransport) {
        self.transport = transport
    }

    func makeTransport() async -> any UpstreamTransport {
        makeCount += 1
        return transport
    }
}

actor ConcurrencyTrackingTransport: UpstreamTransport {
    private(set) var shutdownCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw CoordinatorConcurrencyTestError.execute
    }

    func shutdown() async throws {
        shutdownCount += 1
    }
}

final class ConcurrencyGatewayFactory: GatewayFactory, @unchecked Sendable {
    private let lock = NSLock()
    private let controller: ConcurrencyGatewayController
    private var storedMakeCount = 0

    init(controller: ConcurrencyGatewayController) {
        self.controller = controller
    }

    var makeCount: Int {
        lock.withLock { storedMakeCount }
    }

    func makeGateway(_ context: GatewayBuildContext) -> any GatewayServing {
        lock.withLock {
            storedMakeCount += 1
        }
        return ConcurrencyGatewayServer(
            controller: controller,
            transport: context.transport
        )
    }
}

actor ConcurrencyGatewayController {
    nonisolated let startedEvents: AsyncStream<Void>
    nonisolated let cancelledEvents: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let cancelledContinuation: AsyncStream<Void>.Continuation
    private var startContinuations: [UUID: CheckedContinuation<Void, any Swift.Error>] = [:]
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isRunning = false

    init() {
        (startedEvents, startedContinuation) = AsyncStream<Void>.makeStream()
        (cancelledEvents, cancelledContinuation) = AsyncStream<Void>.makeStream()
    }

    func start() async throws {
        let id = UUID()
        startCount += 1
        startedContinuation.yield()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startContinuations[id] = continuation
            }
            isRunning = true
        } onCancel: {
            Task {
                await self.recordCancellation(id: id)
            }
        }
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func releaseAll(throwing error: (any Swift.Error)? = nil) {
        let continuations = startContinuations.values
        startContinuations.removeAll()
        for continuation in continuations {
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    private func recordCancellation(id: UUID) {
        guard startContinuations[id] != nil else {
            return
        }
        cancelledContinuation.yield()
    }
}

actor ConcurrencyGatewayServer: GatewayServing {
    private let controller: ConcurrencyGatewayController
    private let transport: any UpstreamTransport

    init(controller: ConcurrencyGatewayController, transport: any UpstreamTransport) {
        self.controller = controller
        self.transport = transport
    }

    var isRunning: Bool {
        get async {
            await controller.isRunning
        }
    }

    func start() async throws {
        try await controller.start()
    }

    func stop() async {
        await controller.stop()
        try? await transport.shutdown()
    }
}

actor ControllableGatewayStartupObserver: GatewayStartupObserving {
    nonisolated let joinedEvents: AsyncStream<Void>
    nonisolated let publicationEvents: AsyncStream<Void>
    nonisolated let cleanupWaitEvents: AsyncStream<Void>
    nonisolated let cancellationWaitEvents: AsyncStream<Void>
    nonisolated let cancellationCompletionEvents: AsyncStream<Void>
    nonisolated let explicitStopEvents: AsyncStream<Int>
    private let joinedContinuation: AsyncStream<Void>.Continuation
    private let publicationContinuation: AsyncStream<Void>.Continuation
    private let cleanupWaitContinuation: AsyncStream<Void>.Continuation
    private let cancellationWaitContinuation: AsyncStream<Void>.Continuation
    private let cancellationCompletionContinuation: AsyncStream<Void>.Continuation
    private let explicitStopContinuation: AsyncStream<Int>.Continuation
    private let suspendsPublication: Bool
    private let suspendsCancellation: Bool
    private let suspendsExplicitStops: Bool
    private var publicationRelease: CheckedContinuation<Void, Never>?
    private var cancellationRelease: CheckedContinuation<Void, Never>?
    private var explicitStopReleases: [CheckedContinuation<Void, Never>] = []
    private var explicitStopCount = 0

    init(
        suspendsPublication: Bool = false,
        suspendsCancellation: Bool = false,
        suspendsExplicitStops: Bool = false
    ) {
        self.suspendsPublication = suspendsPublication
        self.suspendsCancellation = suspendsCancellation
        self.suspendsExplicitStops = suspendsExplicitStops
        (joinedEvents, joinedContinuation) = AsyncStream<Void>.makeStream()
        (publicationEvents, publicationContinuation) = AsyncStream<Void>.makeStream()
        (cleanupWaitEvents, cleanupWaitContinuation) = AsyncStream<Void>.makeStream()
        (cancellationWaitEvents, cancellationWaitContinuation) = AsyncStream<Void>.makeStream()
        (cancellationCompletionEvents, cancellationCompletionContinuation) =
            AsyncStream<Void>.makeStream()
        (explicitStopEvents, explicitStopContinuation) = AsyncStream<Int>.makeStream()
    }

    func joinedStartup() async {
        joinedContinuation.yield()
        joinedContinuation.finish()
    }

    func readyToPublishStartup() async {
        publicationContinuation.yield()
        publicationContinuation.finish()
        guard suspendsPublication else {
            return
        }
        await withCheckedContinuation { continuation in
            publicationRelease = continuation
        }
    }

    func waitingForAbandonedStartupCleanup() {
        cleanupWaitContinuation.yield()
        cleanupWaitContinuation.finish()
    }

    func cancellingStartupWaiter() async {
        cancellationWaitContinuation.yield()
        guard suspendsCancellation else {
            return
        }
        await withCheckedContinuation { continuation in
            cancellationRelease = continuation
        }
    }

    func cancelledStartupWaiter() {
        cancellationCompletionContinuation.yield()
    }

    func stoppingAbandonedStartup() async {
        explicitStopCount += 1
        explicitStopContinuation.yield(explicitStopCount)
        guard suspendsExplicitStops else {
            return
        }
        await withCheckedContinuation { continuation in
            explicitStopReleases.append(continuation)
        }
    }

    func releasePublication() {
        publicationRelease?.resume()
        publicationRelease = nil
    }

    func releaseCancellation() {
        cancellationRelease?.resume()
        cancellationRelease = nil
    }

    func releaseExplicitStops() {
        let releases = explicitStopReleases
        explicitStopReleases.removeAll()
        for release in releases {
            release.resume()
        }
    }
}

actor CoordinatorCompletionCounter {
    private(set) var completionCount = 0

    func record() {
        completionCount += 1
    }
}

func requireConcurrencySignal(_ events: AsyncStream<Void>) async throws {
    guard await observedConcurrencySignal(events) else {
        throw CoordinatorConcurrencyTestError.missingSignal
    }
}

func observedConcurrencySignal(_ events: AsyncStream<Void>) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in events {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(1))
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}

func requireExplicitStopCount(
    _ count: Int,
    events: AsyncStream<Int>
) async throws {
    let observed = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await observedCount in events where observedCount >= count {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(1))
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
    guard observed else {
        throw CoordinatorConcurrencyTestError.missingSignal
    }
}

enum CoordinatorConcurrencyTestError: Swift.Error {
    case execute
    case missingSignal
}
