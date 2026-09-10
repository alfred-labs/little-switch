import Foundation
import LittleSwitchCore

public enum MonitoringCredentialIntent: Equatable, Sendable {
    case keep
    case replace(String)
    case remove

    package var normalized: Self {
        guard case .replace(let value) = self else { return self }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? .keep : .replace(token)
    }
}

public struct MonitoringApplyInput: Equatable, Sendable {
    public var configuration: MonitoringConfiguration
    public var metricsCredential: MonitoringCredentialIntent
    public var logsCredential: MonitoringCredentialIntent

    public init(
        configuration: MonitoringConfiguration,
        metricsCredential: MonitoringCredentialIntent = .keep,
        logsCredential: MonitoringCredentialIntent = .keep
    ) {
        self.configuration = configuration
        self.metricsCredential = metricsCredential
        self.logsCredential = logsCredential
    }

    func validate() throws(MonitoringSettingsError) {
        guard MonitoringConfiguration.metricIntervalSecondsRange.contains(configuration.metricIntervalSeconds) else {
            throw MonitoringSettingsError.invalidInterval
        }
        try validate(configuration.metrics, intent: metricsCredential, signal: .metrics)
        try validate(configuration.logs, intent: logsCredential, signal: .logs)
    }

    private func validate(
        _ destination: MonitoringDestination, intent: MonitoringCredentialIntent, signal: MonitoringSignal
    ) throws(MonitoringSettingsError) {
        if destination.enabled || !destination.endpoint.isEmpty {
            do { _ = try MonitoringEndpoint.validate(destination.endpoint) } catch {
                throw MonitoringSettingsError.invalidEndpoint(signal)
            }
        }
        let available: Bool
        switch intent.normalized {
        case .keep: available = destination.credentialID != nil
        case .remove: available = false
        case .replace(let token):
            guard token.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw MonitoringSettingsError.invalidToken(signal)
            }
            available = true
        }
        if destination.enabled, destination.authentication == .bearer, !available {
            throw MonitoringSettingsError.missingToken(signal)
        }
    }
}

struct MonitoringSettingsDraft: Equatable, Sendable {
    var configuration: MonitoringConfiguration
    var metricsToken = ""
    var logsToken = ""
    var removeMetricsToken = false
    var removeLogsToken = false

    init(configuration: MonitoringConfiguration, pending: MonitoringPendingSettings? = nil) {
        self.configuration = pending?.configuration ?? configuration
        removeMetricsToken = pending?.removeMetricsToken ?? false
        removeLogsToken = pending?.removeLogsToken ?? false
    }

    var pending: MonitoringPendingSettings {
        MonitoringPendingSettings(
            configuration: configuration,
            removeMetricsToken: removeMetricsToken,
            removeLogsToken: removeLogsToken,
            hasTypedToken: input.metricsCredential != .keep && !removeMetricsToken
                || input.logsCredential != .keep && !removeLogsToken
        )
    }

    var input: MonitoringApplyInput {
        .init(
            configuration: configuration,
            metricsCredential: removeMetricsToken
                ? .remove : MonitoringCredentialIntent.replace(metricsToken).normalized,
            logsCredential: removeLogsToken ? .remove : MonitoringCredentialIntent.replace(logsToken).normalized
        )
    }

    var validationMessage: String? {
        do {
            try input.validate()
            return nil
        } catch {
            return error.errorDescription
        }
    }

    func hasChanges(from applied: MonitoringConfiguration) -> Bool {
        configuration != applied || input.metricsCredential != .keep || input.logsCredential != .keep
    }

    mutating func acknowledge(_ applied: MonitoringConfiguration, submitted: MonitoringApplyInput) {
        let current = input
        if current == submitted {
            self = Self(configuration: applied)
            return
        }
        configuration.metrics.credentialID = applied.metrics.credentialID
        configuration.logs.credentialID = applied.logs.credentialID
        if current.metricsCredential == submitted.metricsCredential {
            metricsToken = ""
            removeMetricsToken = false
        }
        if current.logsCredential == submitted.logsCredential {
            logsToken = ""
            removeLogsToken = false
        }
    }

    mutating func rebase(on applied: MonitoringConfiguration, replacing previous: MonitoringConfiguration) {
        guard hasChanges(from: previous) else {
            self = Self(configuration: applied)
            return
        }
        configuration.metrics.credentialID = applied.metrics.credentialID
        configuration.logs.credentialID = applied.logs.credentialID
        if applied.metrics.credentialID == nil { removeMetricsToken = false }
        if applied.logs.credentialID == nil { removeLogsToken = false }
    }

    mutating func clearTypedTokens() {
        metricsToken = ""
        logsToken = ""
    }
}
