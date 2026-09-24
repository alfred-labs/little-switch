import Foundation

/// One producer and one consumer rendezvous on each chunk. A slow or disconnected
/// desktop cannot accumulate an unbounded provider stream in memory.
package actor ChatGPTStreamChannel {
    package enum Failure: Swift.Error, Equatable {
        case cancelled
        case concurrentAccess
    }

    private enum End { case finished, cancelled }
    private var end: End?
    private var pending: (Data, CheckedContinuation<Void, any Swift.Error>)?
    private var receiver: CheckedContinuation<Data?, any Swift.Error>?

    package func send(_ data: Data) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Swift.Error>) in
                guard end == nil else { return continuation.resume(throwing: Failure.cancelled) }
                guard pending == nil else { return continuation.resume(throwing: Failure.concurrentAccess) }
                if let receiver {
                    self.receiver = nil
                    receiver.resume(returning: data)
                    continuation.resume()
                } else {
                    pending = (data, continuation)
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    package func next() async throws -> Data? {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            if let (data, sender) = pending {
                pending = nil
                sender.resume()
                return data
            }
            switch end {
            case .finished: return nil
            case .cancelled: throw Failure.cancelled
            case nil: break
            }
            guard receiver == nil else { throw Failure.concurrentAccess }
            return try await withCheckedThrowingContinuation { receiver = $0 }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    package func finish() {
        guard end == nil else { return }
        end = .finished
        receiver?.resume(returning: nil)
        receiver = nil
    }

    package func cancel() {
        end = .cancelled
        pending?.1.resume(throwing: Failure.cancelled)
        receiver?.resume(throwing: Failure.cancelled)
        pending = nil
        receiver = nil
    }
}
