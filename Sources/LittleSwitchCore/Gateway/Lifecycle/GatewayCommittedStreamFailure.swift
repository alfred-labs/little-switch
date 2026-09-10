package struct GatewayCommittedStreamFailure: Swift.Error, Sendable {
    package let reason: String?

    package init(reason: String? = nil) {
        self.reason = reason
    }

    package var trafficMessage: String {
        guard let reason else {
            return "Response stream reported failure"
        }
        return "Response stream reported failure: \(reason)"
    }
}
