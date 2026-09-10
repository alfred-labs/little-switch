import Foundation

package enum OTLPAnyValue: Encodable, Sendable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case boolean(Bool)

    private enum CodingKeys: String, CodingKey { case stringValue, intValue, doubleValue, boolValue }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value): try container.encode(value, forKey: .stringValue)
        case .integer(let value): try container.encode(String(value), forKey: .intValue)
        case .double(let value): try container.encode(value, forKey: .doubleValue)
        case .boolean(let value): try container.encode(value, forKey: .boolValue)
        }
    }
}

package struct OTLPAttribute: Encodable, Sendable {
    package let key: String
    package let value: OTLPAnyValue

    private enum CodingKeys: String, CodingKey { case key, value }

    package init(_ key: String, _ value: OTLPAnyValue) {
        self.key = key
        self.value = value
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(value, forKey: .value)
    }
}

package struct OTLPResource: Encodable, Sendable {
    package let attributes: [OTLPAttribute]

    private enum CodingKeys: String, CodingKey { case attributes }

    package init(_ resource: MonitoringResource) {
        attributes = [
            .init("service.name", .string("littleswitch")),
            .init("service.version", .string(resource.serviceVersion)),
            .init("service.instance.id", .string(resource.instanceID.uuidString.lowercased())),
        ]
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attributes, forKey: .attributes)
    }
}

package struct OTLPScope: Encodable, Sendable {
    private enum CodingKeys: String, CodingKey { case name, version }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("littleswitch.gateway", forKey: .name)
        try container.encode("1", forKey: .version)
    }
}

package enum OTLPJSON {
    package static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    package static func nanoseconds(_ date: Date) -> String {
        let value = date.timeIntervalSince1970 * 1_000_000_000
        guard value.isFinite, value > 0 else { return "0" }
        return value >= Double(UInt64.max) ? String(UInt64.max) : String(UInt64(value))
    }
}

package struct OTLPPayload: Sendable {
    package let body: Data
    package let itemCount: Int
}

package struct OTLPEncodingResult: Sendable {
    package let payloads: [OTLPPayload]
    package let dropped: Int
}

/// Splits only whole observations. Subdivision is logarithmic, avoiding an encode of the
/// growing candidate for every point in a high-cardinality snapshot.
package enum OTLPPayloadPartitioner {
    package static func partition<Item>(
        _ items: [Item], maximumBytes: Int, encode: ([Item]) throws -> Data
    ) throws -> OTLPEncodingResult {
        var pending = items.isEmpty ? [] : [items[items.startIndex..<items.endIndex]]
        var payloads: [OTLPPayload] = []
        var dropped = 0
        while let segment = pending.popLast() {
            let body = try encode(Array(segment))
            if body.count <= maximumBytes {
                payloads.append(.init(body: body, itemCount: segment.count))
            } else if segment.count == 1 {
                dropped += 1
            } else {
                let middle = segment.index(segment.startIndex, offsetBy: segment.count / 2)
                pending.append(segment[middle...])
                pending.append(segment[..<middle])
            }
        }
        return .init(payloads: payloads, dropped: dropped)
    }
}
