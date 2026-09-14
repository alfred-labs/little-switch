import LittleSwitchCommon

extension MonitoringConfiguration {
    package func validate() throws {
        guard Self.metricIntervalSecondsRange.contains(metricIntervalSeconds) else {
            throw Error.invalidMetricInterval
        }
        try validate(metrics, signal: .metrics)
        try validate(logs, signal: .logs)
    }

    private func validate(_ destination: MonitoringDestination, signal: MonitoringSignal) throws {
        if destination.enabled || !destination.endpoint.isEmpty {
            _ = try MonitoringEndpoint.validate(destination.endpoint)
        }
        if destination.enabled, destination.authentication == .bearer, destination.credentialID == nil {
            throw Error.missingCredential(signal)
        }
    }
}
