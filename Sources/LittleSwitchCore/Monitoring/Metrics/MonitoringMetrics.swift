import Foundation
import LittleSwitchCommon

// The value lives in Common; Core injects the live build identity that the
// bounded `serviceVersion` used to default to.
extension MonitoringResource {
    public init(instanceID: UUID = UUID(), startedAt: Date = Date()) {
        self.init(
            serviceVersion: ApplicationBuild.currentTag,
            instanceID: instanceID,
            startedAt: startedAt
        )
    }
}
