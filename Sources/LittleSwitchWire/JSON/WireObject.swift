/// Field operations used by generated codecs. Presence is defined by each schema field.
public struct WireObject: Sendable {
    private var fields: [String: JSONValue]

    public init(_ json: JSONValue) throws {
        guard case .object(let object) = json else {
            throw WireCodingError(.typeMismatch)
        }
        fields = Dictionary(uniqueKeysWithValues: object.map { ($0.key, $0.value) })
    }

    public init(additionalFields: [String: JSONValue], knownKeys: [String]) throws {
        if let collision = knownKeys.first(where: { additionalFields[$0] != nil }) {
            throw WireCodingError(.additionalFieldCollision, path: [collision])
        }
        fields = additionalFields
    }

    public var wireJSON: JSONValue {
        .object(.init(uniqueKeysWithValues: fields.sorted { $0.key < $1.key }))
    }

    public func required<Value: WireCodable>(_ key: String) throws -> Value {
        guard let value = fields[key] else {
            throw WireCodingError(.missingField, path: [key])
        }
        guard !value.isNull else {
            throw WireCodingError(.unexpectedNull, path: [key])
        }
        return try decode(value, key: key)
    }

    public func nullable<Value: WireCodable>(_ key: String) throws -> Value? {
        guard let value = fields[key] else {
            throw WireCodingError(.missingField, path: [key])
        }
        return value.isNull ? nil : try decode(value, key: key)
    }

    public func optional<Value: WireCodable>(_ key: String) throws -> Value? {
        guard fields[key] != nil else { return nil }
        return try required(key)
    }

    public func presence<Value: WireCodable>(_ key: String) throws -> JSONPresence<Value> {
        guard let value = fields[key] else { return .absent }
        return value.isNull ? .null : .value(try decode(value, key: key))
    }

    public func additionalFields(excluding knownKeys: [String]) -> [String: JSONValue] {
        let known = Set(knownKeys)
        return fields.filter { !known.contains($0.key) }
    }

    public mutating func set<Value: WireCodable>(_ value: Value, for key: String) throws {
        fields[key] = try value.wireJSON()
    }

    public mutating func setOptional<Value: WireCodable>(_ value: Value?, for key: String) throws {
        fields[key] = try value?.wireJSON()
    }

    public mutating func setNullable<Value: WireCodable>(_ value: Value?, for key: String) throws {
        fields[key] = try value?.wireJSON() ?? .null
    }

    public mutating func setPresence<Value: WireCodable>(_ value: JSONPresence<Value>, for key: String) throws {
        switch value {
        case .absent: fields[key] = nil
        case .null: fields[key] = .null
        case .value(let value): fields[key] = try value.wireJSON()
        }
    }

    private func decode<Value: WireCodable>(_ value: JSONValue, key: String) throws -> Value {
        do {
            return try Value(wireJSON: value)
        } catch let error as WireCodingError {
            throw error.prepending(key)
        }
    }
}
