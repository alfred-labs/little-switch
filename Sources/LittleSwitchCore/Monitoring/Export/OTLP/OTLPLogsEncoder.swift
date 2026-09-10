import Foundation

package enum OTLPLogsEncoder {
    package static func encode(resource: MonitoringResource, entries: [MonitoringLogEntry]) throws -> Data {
        try OTLPJSON.encode(
            Envelope(resourceLogs: [
                ResourceLogs(
                    resource: OTLPResource(resource),
                    scopeLogs: [
                        ScopeLogs(scope: OTLPScope(), logRecords: entries.map(LogRecord.init))
                    ])
            ]))
    }

    private struct Envelope: Encodable {
        let resourceLogs: [ResourceLogs]
        private enum CodingKeys: String, CodingKey { case resourceLogs }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(resourceLogs, forKey: .resourceLogs)
        }
    }
    private struct ResourceLogs: Encodable {
        let resource: OTLPResource
        let scopeLogs: [ScopeLogs]
        private enum CodingKeys: String, CodingKey { case resource, scopeLogs }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(resource, forKey: .resource)
            try container.encode(scopeLogs, forKey: .scopeLogs)
        }
    }
    private struct ScopeLogs: Encodable {
        let scope: OTLPScope
        let logRecords: [LogRecord]
        private enum CodingKeys: String, CodingKey { case scope, logRecords }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scope, forKey: .scope)
            try container.encode(logRecords, forKey: .logRecords)
        }
    }

    private struct LogRecord: Encodable {
        let timeUnixNano: String
        let observedTimeUnixNano: String
        let severityNumber: Int
        let severityText: String
        let body: OTLPAnyValue
        let attributes: [OTLPAttribute]

        private enum CodingKeys: String, CodingKey {
            case timeUnixNano, observedTimeUnixNano, severityNumber, severityText, body, attributes
        }

        init(_ entry: MonitoringLogEntry) {
            timeUnixNano = OTLPJSON.nanoseconds(entry.timestamp)
            observedTimeUnixNano = OTLPJSON.nanoseconds(entry.observedAt)
            severityNumber = entry.level.severityNumber
            severityText = entry.level.rawValue.uppercased()
            body = .string(entry.message)
            attributes = OTLPLogAttributes.make(entry)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(timeUnixNano, forKey: .timeUnixNano)
            try container.encode(observedTimeUnixNano, forKey: .observedTimeUnixNano)
            try container.encode(severityNumber, forKey: .severityNumber)
            try container.encode(severityText, forKey: .severityText)
            try container.encode(body, forKey: .body)
            try container.encode(attributes, forKey: .attributes)
        }
    }
}

private enum OTLPLogAttributes {
    static func make(_ entry: MonitoringLogEntry) -> [OTLPAttribute] {
        let value = entry.attributes
        var result: [OTLPAttribute] = [
            .init("event.id", .string(entry.eventID.uuidString.lowercased())),
            .init("event.name", .string(entry.eventName)),
        ]
        let strings: [(String, String?)] = [
            ("request_id", value.requestID?.uuidString.lowercased()),
            ("client", value.client?.rawValue), ("route", value.route?.rawValue),
            ("provider_id", value.providerID?.uuidString.lowercased()),
            ("resolved_model", value.resolvedModel), ("outcome", value.outcome?.rawValue),
            ("error_type", value.errorKind?.rawValue),
        ]
        result += strings.compactMap { key, value in value.map { .init(key, .string($0)) } }
        let integers: [(String, Int?)] = [
            ("status", value.statusCode), ("estimated_input_tokens", value.estimatedInputTokens),
            ("web_search_count", value.webSearchCount),
            ("usage.input_tokens", value.usage?.inputTokens), ("usage.output_tokens", value.usage?.outputTokens),
            ("usage.cache_read_tokens", value.usage?.cacheReadTokens),
            ("usage.cache_write_tokens", value.usage?.cacheWriteTokens),
        ]
        result += integers.compactMap { key, value in value.map { .init(key, .integer(Int64($0))) } }
        if let duration = value.durationSeconds { result.append(.init("duration_seconds", .double(duration))) }
        if entry.truncated { result.append(.init("truncated", .boolean(true))) }
        return result
    }
}
