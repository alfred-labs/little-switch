import LittleSwitchCommon

package struct GatewayCommittedStreamFailure: Swift.Error, Sendable {
    package let reason: String?
    package let toolError: ProviderToolContract.Error?

    package init(reason: String? = nil, toolError: ProviderToolContract.Error? = nil) {
        self.reason = reason
        self.toolError = toolError
    }

    package var trafficMessage: String {
        guard let reason else {
            return "Response stream reported failure"
        }
        return "Response stream reported failure: \(reason)"
    }

    package var trafficFailure: TrafficFailure {
        // swiftlint:disable:next pattern_matching_keywords
        if case .undeclaredTool(let name, let namespace) = toolError {
            return TrafficFailure(kind: "stream", message: trafficMessage, toolName: name, toolNamespace: namespace)
        }
        return TrafficFailure(kind: "stream", message: trafficMessage)
    }
}
