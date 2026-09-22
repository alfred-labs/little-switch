import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import NIOHTTP1

@testable import LittleSwitchCore

enum ResolverTransportError: Swift.Error, Sendable {
    case failed
}

struct ResolverCancellingResponseSequence: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    struct AsyncIterator: AsyncIteratorProtocol {
        var body: ByteBuffer?

        mutating func next() async throws -> ByteBuffer? {
            if let body {
                self.body = nil
                return body
            }
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return nil
        }
    }

    let body: String

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(body: ByteBuffer(string: body))
    }
}

actor ResolverStepTransport: UpstreamTransport {
    enum Step: Sendable {
        case response(HTTPClientResponse)
        case failure
    }

    private var steps: [Step]
    private(set) var requestCount = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        requestCount += 1
        guard !steps.isEmpty else { throw ResolverTransportError.failed }
        switch steps.removeFirst() {
        case .response(let response):
            return response
        case .failure:
            throw ResolverTransportError.failed
        }
    }
}

actor ResolverClockAdvancingTransport: UpstreamTransport {
    private let clock: ResolverTestClock
    private let advanceBy: UInt64
    private let response: HTTPClientResponse
    private(set) var requestCount = 0

    init(
        clock: ResolverTestClock,
        advanceBy: UInt64,
        response: HTTPClientResponse
    ) {
        self.clock = clock
        self.advanceBy = advanceBy
        self.response = response
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        requestCount += 1
        clock.advance(by: advanceBy)
        return response
    }
}

actor ResolverGatedTransport: UpstreamTransport {
    let gate: ResolverTestGate
    private(set) var observedCancellation = false

    init(gate: ResolverTestGate) {
        self.gate = gate
    }

    func execute(_ request: HTTPClientRequest) async throws -> HTTPClientResponse {
        _ = request
        do {
            try await gate.wait()
        } catch is CancellationError {
            observedCancellation = true
            throw CancellationError()
        }
        return HTTPClientResponse(
            status: .ok,
            body: .bytes(ByteBuffer(string: #"{"input_tokens":99}"#))
        )
    }
}

final class ResolverTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds: UInt64

    init(milliseconds: UInt64) {
        self.milliseconds = milliseconds
    }

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return milliseconds
    }

    func advance(by delta: UInt64) {
        lock.lock()
        milliseconds += delta
        lock.unlock()
    }
}

struct ResolverTestTiming: AnthropicInitialUsageTiming {
    let clock: ResolverTestClock
    let deadline: ResolverTestGate

    func nowMilliseconds() -> UInt64 {
        clock.now()
    }

    func waitForDeadline() async throws {
        try await deadline.wait()
    }
}

actor ResolverTestGate {
    private var enteredCount = 0
    private var enteredWaiters: [UUID: (Int, CheckedContinuation<Void, Never>)] = [:]
    private var waiters: [UUID: CheckedContinuation<Void, any Swift.Error>] = [:]
    private(set) var cancelledWaitCount = 0

    func wait() async throws {
        let id = UUID()
        enteredCount += 1
        resumeEnteredWaiters()
        try await withTaskCancellationHandler {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func waitUntilEntered(
        count: Int,
        timeout: Duration = .seconds(5)
    ) async throws {
        try await withAsyncTestTimeout(
            timeout,
            description: "the resolver gate to be entered \(count) times"
        ) {
            try await self.waitForEnteredCount(count)
        }
    }

    func releaseAll() {
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    private func cancel(id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        cancelledWaitCount += 1
        continuation.resume(throwing: CancellationError())
    }

    private func waitForEnteredCount(_ count: Int) async throws {
        guard enteredCount < count else { return }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if enteredCount >= count || Task.isCancelled {
                    continuation.resume()
                } else {
                    enteredWaiters[waiterID] = (count, continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelEnteredWaiter(id: waiterID) }
        }
        try Task.checkCancellation()
    }

    private func cancelEnteredWaiter(id: UUID) {
        enteredWaiters.removeValue(forKey: id)?.1.resume()
    }

    private func resumeEnteredWaiters() {
        let ready = enteredWaiters.compactMap { id, waiter in
            enteredCount >= waiter.0 ? id : nil
        }
        for id in ready {
            enteredWaiters.removeValue(forKey: id)?.1.resume()
        }
    }
}

final class ResolverRecordingEstimator: GatewayTokenEstimating, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Int
    private var calls = 0

    init(result: Int) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func estimate(_ request: Data) throws -> Int {
        _ = request
        lock.lock()
        calls += 1
        lock.unlock()
        return result
    }

    func estimate(root: JSONObject) throws -> Int {
        _ = root
        lock.lock()
        calls += 1
        lock.unlock()
        return result
    }
}
