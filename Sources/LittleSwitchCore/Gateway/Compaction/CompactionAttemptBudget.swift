package struct CompactionAttemptBudget: Equatable, Sendable {
    package enum Retry: Hashable, Sendable {
        case imageFallback, selectionRepair, contextTrim, routeFallback
    }

    package enum Error: Swift.Error, Equatable { case callsExhausted, retryAlreadyUsed }

    package private(set) var upstreamCalls = 0
    private var used: Set<Retry> = []

    package var imageFallbackUsed: Bool { used.contains(.imageFallback) }

    package func taking(_ retry: Retry) throws -> Self {
        var copy = self
        guard copy.used.insert(retry).inserted else { throw Error.retryAlreadyUsed }
        return copy
    }

    package func recordingCall() throws -> Self {
        guard upstreamCalls < 5 else { throw Error.callsExhausted }
        var copy = self
        copy.upstreamCalls += 1
        return copy
    }
}
