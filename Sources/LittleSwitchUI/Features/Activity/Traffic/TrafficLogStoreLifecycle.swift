import Foundation
import LittleSwitchCommon

actor TrafficLogInbox {
    nonisolated let stream: AsyncStream<TrafficLogCommand>
    nonisolated let continuation: AsyncStream<TrafficLogCommand>.Continuation

    private var lifecycle = TrafficLogAdmissionLifecycle.idle

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: TrafficLogCommand.self)
    }

    func start() -> Bool {
        guard case .idle = lifecycle else { return false }
        lifecycle = .running
        return true
    }

    nonisolated func record(eventID: UUID, timestamp: Date, action: TrafficAction) {
        continuation.yield(.record(eventID: eventID, timestamp: timestamp, action: action))
    }

    func flush() async {
        guard case .running = lifecycle else { return }
        let completion = TrafficLogCommandCompletion()
        continuation.yield(.flush(completion))
        await completion.wait()
    }

    func requestStop() async -> TrafficLogStopRequest {
        switch lifecycle {
        case .idle:
            let completion = TrafficLogCommandCompletion()
            lifecycle = .stopping(completion)
            continuation.finish()
            await completion.finish()
            return TrafficLogStopRequest(completion: completion)
        case .running:
            let completion = TrafficLogCommandCompletion()
            lifecycle = .stopping(completion)
            continuation.yield(.stop(completion))
            continuation.finish()
            return TrafficLogStopRequest(completion: completion)
        case .stopping(let completion):
            return TrafficLogStopRequest(completion: completion)
        }
    }
}

actor TrafficLogCommandCompletion {
    private var isFinished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isFinished else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finish() {
        isFinished = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pending {
            waiter.resume()
        }
    }
}

struct TrafficLogStopRequest: Sendable {
    let completion: TrafficLogCommandCompletion
}

enum TrafficLogCommand: Sendable {
    case record(eventID: UUID, timestamp: Date, action: TrafficAction)
    case flush(TrafficLogCommandCompletion)
    case stop(TrafficLogCommandCompletion)
}

private enum TrafficLogAdmissionLifecycle {
    case idle
    case running
    case stopping(TrafficLogCommandCompletion)
}
