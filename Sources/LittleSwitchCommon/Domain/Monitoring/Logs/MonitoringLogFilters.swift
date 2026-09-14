import Foundation

public struct MonitoringLogFilters: Codable, Equatable, Sendable {
    public let since: Date?
    public let minimumLevel: MonitoringLevel?
    public let requestID: UUID?

    package init(since: Date? = nil, minimumLevel: MonitoringLevel? = nil, requestID: UUID? = nil) {
        self.since = since
        self.minimumLevel = minimumLevel
        self.requestID = requestID
    }

    package func matches(_ entry: MonitoringLogEntry) -> Bool {
        (since.map { entry.timestamp >= $0 } ?? true)
            && (minimumLevel.map { entry.level >= $0 } ?? true)
            && (requestID.map { entry.attributes.requestID == $0 } ?? true)
    }
}
