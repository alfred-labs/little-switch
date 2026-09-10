import Foundation

@testable import LittleSwitchUI

final class AsyncStreamTestIterator<Element: Sendable>: @unchecked Sendable {
    private let requests: AsyncStream<AsyncStreamNextRequest<Element>>.Continuation
    private let worker: Task<Void, Never>

    init(_ stream: AsyncStream<Element>) {
        let (requestStream, requests) = AsyncStream.makeStream(
            of: AsyncStreamNextRequest<Element>.self
        )
        self.requests = requests
        worker = Task {
            var iterator = stream.makeAsyncIterator()
            for await request in requestStream {
                request.continuation.resume(returning: await iterator.next())
            }
        }
    }

    func next() async -> Element? {
        await withCheckedContinuation { continuation in
            if case .terminated = requests.yield(AsyncStreamNextRequest(continuation)) {
                continuation.resume(returning: nil)
            }
        }
    }

    func cancel() {
        requests.finish()
        worker.cancel()
    }

    deinit {
        cancel()
    }
}

func nextWithinTimeout<Element: Sendable>(
    from iterator: AsyncStreamTestIterator<Element>,
    timeout: Duration = .seconds(2)
) async throws -> Element? {
    let timedOut = TrafficLogTimeoutFlag()
    let element: Element? = await withTaskGroup(of: Element?.self) { group in
        group.addTask {
            await iterator.next()
        }
        group.addTask {
            do {
                try await Task.sleep(for: timeout)
                timedOut.mark()
                iterator.cancel()
            } catch {}
            return nil
        }
        defer { group.cancelAll() }
        guard let first = await group.next() else { return nil }
        return first
    }
    guard !timedOut.value else {
        throw TrafficLogAsyncTestError.timedOut
    }
    return element
}

enum TrafficLogAsyncTestError: Error {
    case timedOut
}

private struct AsyncStreamNextRequest<Element: Sendable>: @unchecked Sendable {
    let continuation: CheckedContinuation<Element?, Never>

    init(_ continuation: CheckedContinuation<Element?, Never>) {
        self.continuation = continuation
    }
}

private final class TrafficLogTimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.withLock { storage }
    }

    func mark() {
        lock.withLock { storage = true }
    }
}
