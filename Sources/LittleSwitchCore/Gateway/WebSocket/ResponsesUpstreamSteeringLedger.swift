import LittleSwitchWire

/// Connection-owned bookkeeping. An intent keeps its observer through every
/// state, and draining the ledger consumes each unapplied intent exactly once.
struct ResponsesUpstreamSteeringLedger: Sendable {
    private typealias SteeringField = ResponsesWebSocketContract.SteeringField
    private typealias ControlField = ResponsesWebSocketContract.ControlField
    private struct Submission: Sendable {
        let steering: ResponsesWebSocketSteering
        let observer: @Sendable (String) -> Void
    }
    private var submitted: [Submission] = []
    private var accepted: [(String, Submission)] = []
    private var pendingTools: Set<String> = []
    private var applied: [String: [JSONValue]] = [:]
    private(set) var retainedBytes = 0

    var count: Int { submitted.count + accepted.count }
    var hasSubmitted: Bool { !submitted.isEmpty }
    var hasAccepted: Bool { !accepted.isEmpty }
    var awaitsContinuation: Bool { accepted.contains { !pendingTools.contains($0.0) } }

    mutating func submit(_ steering: ResponsesWebSocketSteering, observer: @escaping @Sendable (String) -> Void) {
        submitted.append(Submission(steering: steering, observer: observer))
        retainedBytes += steering.body.count
        observer(ResponsesWebSocketContract.Event.steerSubmitted.rawValue)
    }

    mutating func receive(_ event: JSONObject, type: String) throws {
        let steer = event[ControlField.steer.rawValue]?.object
        switch type {
        case ResponsesWebSocketContract.Event.steerAccepted.rawValue:
            guard let identifier = steer?[SteeringField.id.rawValue]?.string, let first = submitted.first,
                steer?[SteeringField.previousResponseID.rawValue]?.string == first.steering.previousResponseID
            else { throw ResponsesWebSocketEvents.Error.invalidEvent }
            let submission = submitted.removeFirst()
            accepted.append((identifier, submission))
            submission.observer(type)
        case ResponsesWebSocketContract.Event.steerFailed.rawValue:
            let submission: Submission
            let index = steer?[SteeringField.id.rawValue]?.string.flatMap { identifier in
                accepted.firstIndex { $0.0 == identifier }
            }
            if let index {
                let removed = accepted.remove(at: index)
                submission = removed.1
                pendingTools.remove(removed.0)
            } else if steer?[SteeringField.id.rawValue] == nil, !submitted.isEmpty {
                submission = submitted.removeFirst()
            } else {
                throw ResponsesWebSocketEvents.Error.invalidEvent
            }
            retainedBytes -= submission.steering.body.count
            submission.observer(type)
        case ResponsesWebSocketContract.Event.steerPending.rawValue:
            guard let identifier = steer?[SteeringField.id.rawValue]?.string else {
                throw ResponsesWebSocketEvents.Error.invalidEvent
            }
            let previous = steer?[SteeringField.previousResponseID.rawValue]?.string
            let submission: Submission
            if let existing = accepted.first(where: { $0.0 == identifier })?.1 {
                submission = existing
            } else if let first = submitted.first, previous == first.steering.previousResponseID {
                // Pending may itself acknowledge a submitted intent. Keep it
                // accepted but waiting for tools, not an automatic successor.
                submission = submitted.removeFirst()
                accepted.append((identifier, submission))
            } else {
                throw ResponsesWebSocketEvents.Error.invalidEvent
            }
            pendingTools.insert(identifier)
            submission.observer(type)
        default:
            throw ResponsesWebSocketEvents.Error.invalidEvent
        }
    }

    mutating func apply(to responseID: String) {
        guard !accepted.isEmpty else { return }
        applied[responseID] = accepted.flatMap(\.1.steering.input)
        retainedBytes -= accepted.reduce(0) { $0 + $1.1.steering.body.count }
        accepted.removeAll()
        pendingTools.removeAll()
    }

    mutating func takeAppliedInput(responseID: String) -> [JSONValue] {
        applied.removeValue(forKey: responseID) ?? []
    }

    mutating func takeFailures(
        submittedCode: ResponsesWebSocketContract.ErrorCode,
        acceptedCode: ResponsesWebSocketContract.ErrorCode = .steeringConnectionRetired
    ) -> [ResponsesUpstreamSteeringFailure] {
        let reports =
            accepted.map { identifier, submission in
                ResponsesUpstreamSteeringFailure(
                    identifier: identifier,
                    previousResponseID: submission.steering.previousResponseID,
                    code: pendingTools.contains(identifier) ? .steeringConnectionRetired : acceptedCode,
                    observer: submission.observer)
            }
            + submitted.map { submission in
                ResponsesUpstreamSteeringFailure(
                    identifier: nil,
                    previousResponseID: submission.steering.previousResponseID,
                    code: submittedCode,
                    observer: submission.observer)
            }
        submitted.removeAll()
        accepted.removeAll()
        pendingTools.removeAll()
        retainedBytes = 0
        return reports
    }
}
