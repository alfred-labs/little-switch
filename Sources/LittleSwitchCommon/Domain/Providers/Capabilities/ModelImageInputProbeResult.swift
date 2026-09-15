import Foundation

package enum ModelImageProbeInconclusiveReason: Equatable, Sendable {
    case wrongAnswer, incompleteResponse, invalidResponse, routeUnavailable
    case transport, timeout, sizeLimit
    case httpStatus(Int)
}

package enum ModelImageInputProbeOutcome: Equatable, Sendable {
    case verified
    case unsupported
    case inconclusive(ModelImageProbeInconclusiveReason)
}

package struct ModelImageInputProbeResult: Equatable, Sendable {
    package let outcome: ModelImageInputProbeOutcome
    package let usage: ResponsesUsage?
    package let startedAt: Date
    package let durationSeconds: TimeInterval

    package init(
        outcome: ModelImageInputProbeOutcome,
        usage: ResponsesUsage?,
        startedAt: Date,
        durationSeconds: TimeInterval
    ) {
        self.outcome = outcome
        self.usage = usage
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
    }
}
