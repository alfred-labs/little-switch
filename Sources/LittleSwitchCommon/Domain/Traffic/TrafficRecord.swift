import Foundation

public struct TrafficRecord: Codable, Equatable, Sendable {
    public var eventID: UUID
    public var sequence: UInt64
    public var timestamp: Date
    public var action: TrafficAction

    public init(
        eventID: UUID,
        sequence: UInt64,
        timestamp: Date,
        action: TrafficAction
    ) {
        self.eventID = eventID
        self.sequence = sequence
        self.timestamp = timestamp
        self.action = action
    }
}
