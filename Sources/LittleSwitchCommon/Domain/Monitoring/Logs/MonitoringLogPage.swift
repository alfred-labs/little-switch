import Foundation

public struct MonitoringLogPage: Encodable, Equatable, Sendable {
    public let entries: [MonitoringLogEntry]
    public let nextCursor: String?
    public let retentionLost: Bool

    package init(entries: [MonitoringLogEntry], nextCursor: String? = nil, retentionLost: Bool) {
        self.entries = entries
        self.nextCursor = nextCursor
        self.retentionLost = retentionLost
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, entries, nextCursor, retentionLost }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(entries, forKey: .entries)
        try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
        try container.encode(retentionLost, forKey: .retentionLost)
    }

    public func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    package static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.ISO8601Format(.init(includingFractionalSeconds: true)))
        }
        return encoder
    }
}
