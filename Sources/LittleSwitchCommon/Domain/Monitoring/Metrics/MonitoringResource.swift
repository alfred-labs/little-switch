import Foundation

public struct MonitoringResource: Equatable, Sendable {
    public let serviceVersion: String
    public let instanceID: UUID
    public let startedAt: Date

    public init(
        serviceVersion: String,
        instanceID: UUID = UUID(),
        startedAt: Date = Date()
    ) {
        self.serviceVersion = monitoringBoundedText(serviceVersion, maximumBytes: 256)
        self.instanceID = instanceID
        self.startedAt = startedAt
    }
}
