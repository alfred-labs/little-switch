import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring configuration")
struct MonitoringConfigurationTests {
    @Test("Current configurations persist a monitoring section in version 8")
    func currentConfigurationIncludesMonitoring() throws {
        let configuration = AppConfiguration()
        let encoded = try JSONEncoder().encode(configuration)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(configuration.version == 8)
        #expect(object["monitoring"] is [String: Any])
    }

    @Test("Defaults expose local metrics without starting remote exports")
    func defaults() throws {
        let configuration = MonitoringConfiguration()
        let destination = MonitoringDestination(
            enabled: false,
            endpoint: "",
            authentication: .none,
            credentialID: nil
        )

        #expect(
            configuration
                == MonitoringConfiguration(
                    exposeMetrics: true,
                    exposeLogs: false,
                    metrics: destination,
                    logs: destination,
                    metricIntervalSeconds: 15,
                    minimumLogLevel: .info
                )
        )
        try configuration.validate()
        let encoded = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(MonitoringConfiguration.self, from: encoded) == configuration)
    }

    @Test("Configured destinations round-trip with opaque credential references only")
    func configuredRoundTrip() throws {
        let configuration = MonitoringConfiguration(
            exposeMetrics: false,
            exposeLogs: true,
            metrics: MonitoringDestination(
                enabled: true,
                endpoint: "https://metrics.example.com/custom/metrics/",
                authentication: .bearer,
                credentialID: UUID()
            ),
            logs: MonitoringDestination(
                enabled: true,
                endpoint: "https://logs.example.com/otlp/v1/logs",
                authentication: .bearer,
                credentialID: UUID()
            ),
            metricIntervalSeconds: 300,
            minimumLogLevel: .error
        )
        let encoded = try JSONEncoder().encode(configuration)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        try configuration.validate()
        #expect(try JSONDecoder().decode(MonitoringConfiguration.self, from: encoded) == configuration)
        #expect(
            Set(object.keys)
                == ["exposeMetrics", "exposeLogs", "metrics", "logs", "metricIntervalSeconds", "minimumLogLevel"]
        )
        for signal in MonitoringSignal.allCases {
            let destination = try #require(object[signal.rawValue] as? [String: Any])
            #expect(Set(destination.keys) == ["enabled", "endpoint", "authentication", "credentialID"])
        }
    }

    @Test("Metric export intervals include both supported boundaries", arguments: [5, 15, 300])
    func validIntervals(seconds: Int) throws {
        let configuration = MonitoringConfiguration(metricIntervalSeconds: seconds)

        #expect(MonitoringConfiguration.metricIntervalSecondsRange.contains(seconds))
        try configuration.validate()
    }

    @Test(
        "Metric export intervals outside the supported range are rejected",
        arguments: [Int.min, -1, 0, 4, 301, Int.max])
    func invalidIntervals(seconds: Int) {
        #expect(throws: MonitoringConfiguration.Error.invalidMetricInterval) {
            try MonitoringConfiguration(metricIntervalSeconds: seconds).validate()
        }
    }

    @Test("An enabled export requires an endpoint", arguments: MonitoringSignal.allCases)
    func enabledDestinationRequiresEndpoint(signal: MonitoringSignal) {
        let configuration = configuration(for: signal, destination: MonitoringDestination(enabled: true))

        #expect(throws: MonitoringEndpoint.Error.invalidURL) {
            try configuration.validate()
        }
    }

    @Test("A disabled export still validates a nonempty endpoint", arguments: MonitoringSignal.allCases)
    func disabledDestinationValidatesEndpoint(signal: MonitoringSignal) {
        let configuration = configuration(
            for: signal,
            destination: MonitoringDestination(endpoint: "http://example.com/v1/logs")
        )

        #expect(throws: MonitoringEndpoint.Error.insecureRemoteHTTP) {
            try configuration.validate()
        }
    }

    @Test("An enabled bearer destination requires a credential reference", arguments: MonitoringSignal.allCases)
    func enabledBearerRequiresCredential(signal: MonitoringSignal) {
        let configuration = configuration(
            for: signal,
            destination: MonitoringDestination(
                enabled: true,
                endpoint: "https://example.com/v1/otlp",
                authentication: .bearer
            )
        )

        #expect(throws: MonitoringConfiguration.Error.missingCredential(signal)) {
            try configuration.validate()
        }
    }

    @Test("Disabled bearer destinations may remain empty", arguments: MonitoringSignal.allCases)
    func disabledBearerNeedsNoCredential(signal: MonitoringSignal) throws {
        let configuration = configuration(
            for: signal,
            destination: MonitoringDestination(authentication: .bearer)
        )

        try configuration.validate()
    }

    @Test("Unauthenticated enabled destinations need no credential", arguments: MonitoringSignal.allCases)
    func enabledUnauthenticatedDestination(signal: MonitoringSignal) throws {
        let configuration = configuration(
            for: signal,
            destination: MonitoringDestination(enabled: true, endpoint: "http://localhost:4318/v1/otlp")
        )

        try configuration.validate()
    }

    @Test("Log levels preserve the OTLP severity order")
    func severityOrder() throws {
        let levels = [MonitoringLevel.info, .warn, .error]

        #expect(levels.map(\.severityNumber) == [9, 13, 17])
        #expect(levels.reversed().sorted() == levels)
        #expect(MonitoringLevel.info < .warn)
        #expect(MonitoringLevel.warn < .error)
        #expect(!(MonitoringLevel.error < .error))
        let encoded = try JSONEncoder().encode(levels)
        #expect(try JSONDecoder().decode([MonitoringLevel].self, from: encoded) == levels)
    }

    private func configuration(
        for signal: MonitoringSignal,
        destination: MonitoringDestination
    ) -> MonitoringConfiguration {
        switch signal {
        case .metrics:
            MonitoringConfiguration(metrics: destination)
        case .logs:
            MonitoringConfiguration(logs: destination)
        }
    }
}
