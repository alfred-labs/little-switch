import Foundation
import LittleSwitchCommon

enum MonitoringLogQueryError: Error, Equatable, Sendable {
    case invalidQuery
    case cursorExpired
}

package struct MonitoringLogCursor: Codable, Equatable, Sendable {
    package let version: Int
    package let instanceID: UUID
    package let position: UInt64
    package let filters: MonitoringLogFilters

    package func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    package static func decode(_ text: String) throws -> Self {
        guard !text.isEmpty, text.utf8.count <= 4_096,
            text.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
            })
        else { throw MonitoringLogQueryError.invalidQuery }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
            let cursor = try? JSONDecoder().decode(Self.self, from: data), cursor.version == 1,
            cursor.filters.since?.timeIntervalSince1970.isFinite != false
        else { throw MonitoringLogQueryError.invalidQuery }
        return cursor
    }
}

public struct MonitoringLogQuery: Equatable, Sendable {
    public let filters: MonitoringLogFilters
    public let limit: Int
    package let cursor: MonitoringLogCursor?

    public init() {
        filters = MonitoringLogFilters(since: nil, minimumLevel: nil, requestID: nil)
        limit = 100
        cursor = nil
    }

    public init(parameters: [URLQueryItem]) throws {
        let allowed: Set<String> = ["since", "level", "request_id", "limit", "cursor"]
        var values: [String: String] = [:]
        for item in parameters {
            guard allowed.contains(item.name), values[item.name] == nil, let value = item.value, !value.isEmpty else {
                throw MonitoringLogQueryError.invalidQuery
            }
            values[item.name] = value
        }
        if let rawLimit = values["limit"] {
            guard rawLimit.utf8.allSatisfy({ (48...57).contains($0) }),
                let parsedLimit = Int(rawLimit), (1...500).contains(parsedLimit)
            else { throw MonitoringLogQueryError.invalidQuery }
            limit = parsedLimit
        } else {
            limit = 100
        }
        if let rawCursor = values["cursor"] {
            guard values.keys.allSatisfy({ $0 == "cursor" || $0 == "limit" }) else {
                throw MonitoringLogQueryError.invalidQuery
            }
            let parsed = try MonitoringLogCursor.decode(rawCursor)
            cursor = parsed
            filters = parsed.filters
        } else {
            cursor = nil
            filters = try Self.parseFilters(values)
        }
    }

    private static func parseFilters(_ values: [String: String]) throws -> MonitoringLogFilters {
        let since = try values["since"].map { rawText -> Date in
            let text = rawText.uppercased()
            let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#
            guard text.utf8.count <= 64, text.range(of: pattern, options: .regularExpression) != nil else {
                throw MonitoringLogQueryError.invalidQuery
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw MonitoringLogQueryError.invalidQuery }
            return date
        }
        let level = try values["level"].map { text -> MonitoringLevel in
            guard let level = MonitoringLevel(rawValue: text) else { throw MonitoringLogQueryError.invalidQuery }
            return level
        }
        let requestID = try values["request_id"].map { text -> UUID in
            guard let requestID = UUID(uuidString: text) else { throw MonitoringLogQueryError.invalidQuery }
            return requestID
        }
        return MonitoringLogFilters(since: since, minimumLevel: level, requestID: requestID)
    }
}
