import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import Testing

@testable import LittleSwitchTransport

@Suite("Upstream transport ownership")
struct UpstreamTransportOwnershipTests {
    @Test("Execution stays transparent and concurrent shutdown joins one operation")
    func transparentExecutionAndConcurrentShutdown() async throws {
        let upstream = SuspendingOwnedUpstreamTransport()
        let transport = ShutdownOnceUpstreamTransport(upstream: upstream)
        let request = HTTPClientRequest(url: "https://provider.example/v1/models")

        let response = try await transport.execute(request)
        #expect(response.status == .accepted)
        #expect(await upstream.executeCount == 1)

        let first = Task {
            try await transport.shutdown()
        }
        try await waitForOwnedTransportSignal(upstream.shutdownEvents)
        let second = Task {
            try await transport.shutdown()
        }
        await upstream.releaseShutdown()

        try await first.value
        try await second.value
        #expect(await upstream.shutdownCount == 1)
    }

    @Test("A cancelled caller still starts shutdown in a fresh task")
    func cancelledCallerStillShutsDown() async throws {
        let upstream = CancellationCheckingOwnedTransport()
        let transport = ShutdownOnceUpstreamTransport(upstream: upstream)
        let task = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            try await transport.shutdown()
        }

        try await task.value

        #expect(await upstream.shutdownCount == 1)
    }

    @Test("A per-request deadline passes through to the owned upstream")
    func perRequestDeadlinePassesThrough() async throws {
        let upstream = DeadlineRecordingOwnedTransport()
        let transport = ShutdownOnceUpstreamTransport(upstream: upstream)
        let request = HTTPClientRequest(url: "https://provider.example/v1/models")

        _ = try await transport.execute(request, timeout: .seconds(8))

        // The wrapper must forward the deadline, not collapse it onto the
        // upstream's own traffic-grade window.
        #expect(await upstream.receivedTimeouts == [.seconds(8)])
    }

    @Test("A shutdown failure is shared without retrying the underlying transport")
    func failureIsShared() async {
        let upstream = FailingOwnedUpstreamTransport()
        let transport = ShutdownOnceUpstreamTransport(upstream: upstream)

        await #expect(throws: OwnedTransportTestError.shutdown) {
            try await transport.shutdown()
        }
        await #expect(throws: OwnedTransportTestError.shutdown) {
            try await transport.shutdown()
        }

        #expect(await upstream.shutdownCount == 1)
    }
}

private actor SuspendingOwnedUpstreamTransport: UpstreamTransport {
    nonisolated let shutdownEvents: AsyncStream<Void>
    private let shutdownContinuation: AsyncStream<Void>.Continuation
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var executeCount = 0
    private(set) var shutdownCount = 0

    init() {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        shutdownEvents = events
        shutdownContinuation = continuation
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        executeCount += 1
        return HTTPClientResponse(
            status: .accepted,
            body: .bytes(ByteBuffer())
        )
    }

    func shutdown() async throws {
        shutdownCount += 1
        shutdownContinuation.yield()
        shutdownContinuation.finish()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func releaseShutdown() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor CancellationCheckingOwnedTransport: UpstreamTransport {
    private(set) var shutdownCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw OwnedTransportTestError.execute
    }

    func shutdown() async throws {
        try Task.checkCancellation()
        shutdownCount += 1
    }
}

private actor DeadlineRecordingOwnedTransport: UpstreamTransport {
    private(set) var receivedTimeouts: [TimeAmount] = []

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        // The deadline-bearing entry point must be reached instead.
        return HTTPClientResponse(status: .ok, body: .bytes(ByteBuffer()))
    }

    func execute(
        _ request: HTTPClientRequest,
        timeout: TimeAmount
    ) async throws -> HTTPClientResponse {
        receivedTimeouts.append(timeout)
        return HTTPClientResponse(status: .accepted, body: .bytes(ByteBuffer()))
    }
}

private actor FailingOwnedUpstreamTransport: UpstreamTransport {
    private(set) var shutdownCount = 0

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        throw OwnedTransportTestError.execute
    }

    func shutdown() async throws {
        shutdownCount += 1
        throw OwnedTransportTestError.shutdown
    }
}

private func waitForOwnedTransportSignal(_ events: AsyncStream<Void>) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for await _ in events {
                return
            }
            throw OwnedTransportTestError.missingSignal
        }
        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw OwnedTransportTestError.missingSignal
        }
        _ = try await group.next()
        group.cancelAll()
    }
}

private enum OwnedTransportTestError: Swift.Error, Equatable {
    case execute
    case missingSignal
    case shutdown
}
