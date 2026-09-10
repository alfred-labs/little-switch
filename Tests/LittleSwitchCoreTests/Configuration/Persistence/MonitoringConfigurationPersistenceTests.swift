import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring configuration persistence boundaries")
struct MonitoringConfigurationPersistenceTests {
    @Test(
        "Independent saves preserve invalid monitoring settings loaded from disk",
        arguments: [
            MonitoringConfiguration(metricIntervalSeconds: 0),
            MonitoringConfiguration(metrics: .init(enabled: true)),
            MonitoringConfiguration(logs: .init(endpoint: "http://remote.example/v1/logs")),
            MonitoringConfiguration(
                metrics: .init(enabled: true, endpoint: "https://receiver.example/v1/metrics", authentication: .bearer)),
        ]
    )
    func independentSave(monitoring: MonitoringConfiguration) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )
        let original = AppConfiguration(monitoring: monitoring)
        try JSONEncoder().encode(original).write(to: store.fileURL)
        var independent = try store.load()
        independent.autoMode = false
        try store.save(independent)
        #expect(try store.load() == independent)
        #expect(try store.load().monitoring == monitoring)
    }

    @Test("Loading hand-edited monitoring settings preserves local flags for controlled startup validation")
    func loadingRemainsTolerant() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(
            fileURL: directory.appending(path: "config.json"),
            backupDirectory: directory.appending(path: "backups")
        )
        let edited = AppConfiguration(
            monitoring: .init(
                exposeLogs: true,
                metrics: .init(enabled: true, endpoint: "hand-edited-invalid"),
                metricIntervalSeconds: 0
            )
        )
        try JSONEncoder().encode(edited).write(to: store.fileURL)
        #expect(try store.load() == edited)
    }
}
