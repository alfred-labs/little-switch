import Foundation

package struct MonitoringExportTime: Sendable {
    package let monotonic: Duration
    package let date: Date
}

package protocol MonitoringExportClock: Sendable {
    func now() async -> MonitoringExportTime
    func sleep(until deadline: Duration) async throws
}

package struct MonitoringContinuousExportClock: MonitoringExportClock {
    private let origin = ContinuousClock.now

    package func now() async -> MonitoringExportTime {
        .init(monotonic: origin.duration(to: .now), date: Date())
    }

    package func sleep(until deadline: Duration) async throws {
        try await ContinuousClock().sleep(until: origin.advanced(by: deadline))
    }
}
