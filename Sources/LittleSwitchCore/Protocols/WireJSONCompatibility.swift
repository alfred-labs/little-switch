import CoreFoundation
import Foundation
import LittleSwitchWire

/// A boundary for existing dictionary-based domain transformations. JSON numbers
/// stay boxed as exact JSONValue leaves; only strings, booleans and containers
/// are exposed to those transformations. Wire shapes belong to generated codecs.
enum WireJSONCompatibility {
    enum Error: Swift.Error { case invalidJSON }

    static func fields(_ data: Data) throws -> [String: Any] {
        try fields(WireCodec.decode(JSONValue.self, from: data).value)
    }

    static func fields(_ value: JSONValue) throws -> [String: Any] {
        guard let fields = view(value) as? [String: Any] else {
            throw Error.invalidJSON
        }
        return fields
    }

    static func view(_ value: JSONValue) -> Any {
        switch value {
        case .string(let text): return text
        case .boolean(let flag): return flag
        case .numberLiteral: return value
        case .null: return NSNull()
        case .array(let values): return values.map(view)
        case .object(let fields):
            return Dictionary(uniqueKeysWithValues: fields.map { ($0.key, view($0.value)) })
        }
    }

    static func value(_ value: Any) throws -> JSONValue {
        if let value = value as? JSONValue { return value }
        if let text = value as? String { return .string(text) }
        if value is NSNull { return .null }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            // These numbers originate in Core's transformations. Incoming wire
            // numbers take the JSONValue branch above, preserving their lexeme.
            return .numberLiteral(try JSONNumber(number.stringValue))
        }
        if let values = value as? [Any] { return .array(try values.map(Self.value)) }
        if let fields = value as? [String: Any] {
            return .object(
                .init(
                    uniqueKeysWithValues: try fields.sorted { $0.key < $1.key }.map {
                        ($0.key, try Self.value($0.value))
                    }))
        }
        throw Error.invalidJSON
    }

    static func data(_ value: Any) throws -> Data {
        try Self.value(value).serializedData()
    }
}
