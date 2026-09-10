import Foundation

package struct MonitoringExportRetrySchedule: Sendable {
    package let deadline: Duration?
    package let date: Date?

    package init(delay: TimeInterval, now: MonitoringExportTime) {
        // Retry-After is receiver-controlled and can exceed Duration's integer range.
        // An unrepresentable deadline suspends sends until reconfiguration; it never
        // wraps around into an immediate retry or crashes the gateway process.
        guard delay.isFinite, delay >= 0, delay <= Double(Int64.max / 4) else {
            deadline = nil
            date = nil
            return
        }
        let duration = Duration.seconds(delay)
        guard now.monotonic <= .seconds(Int64.max) - duration else {
            deadline = nil
            date = nil
            return
        }
        deadline = now.monotonic + duration
        let candidate = now.date.addingTimeInterval(delay)
        date = candidate <= .distantFuture ? candidate : nil
    }

    package func isDue(at now: Duration) -> Bool { deadline.map { now >= $0 } ?? false }
}
