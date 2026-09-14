import Foundation
import LittleSwitchCommon

@testable import LittleSwitchCore

extension MonitoringMetricsSnapshot {
    func family(_ name: MonitoringMetricName) -> MonitoringMetricFamily? {
        families.first { $0.name == name }
    }
}

extension MonitoringUsageAccumulator {
    /// Container state is independently capped at 64; these are the retained payload bytes.
    var retainedByteCount: Int { keyBytes.count + sample.count }
}
