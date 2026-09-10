import ArgumentParser
import Foundation
import RepositoryTooling

struct MonitoringCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monitoring",
        abstract: "Check the local monitoring lab and its synthetic OTLP signals.",
        subcommands: [MonitoringReadinessCommand.self, MonitoringProbeCommand.self])

    @OptionGroup var options: RepositoryOptions
}

struct MonitoringReadinessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "readiness",
        abstract: "Wait for the local Prometheus and Loki receivers to become ready.")

    @OptionGroup var options: RepositoryOptions

    func run() async throws {
        let readiness = MonitoringReadiness(client: MonitoringURLSessionClient()) {
            try await Task.sleep(for: $0)
        }
        try await readiness.run { print($0) }
    }
}

struct MonitoringProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "Send synthetic OTLP JSON metrics and logs, then prove both are queryable.")

    @OptionGroup var options: RepositoryOptions

    func run() async throws {
        let milliseconds = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        let probe = MonitoringProbe(client: MonitoringURLSessionClient()) {
            try await Task.sleep(for: $0)
        }
        try await probe.run(id: UUID(), unixMilliseconds: milliseconds) { print($0) }
    }
}
