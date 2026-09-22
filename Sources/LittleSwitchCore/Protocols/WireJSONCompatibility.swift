import CoreFoundation
import Foundation
import LittleSwitchWire

/// A boundary for existing dictionary-based domain transformations. JSON numbers
/// stay boxed as exact JSONValue leaves; only strings, booleans and containers
/// are exposed to those transformations. Wire shapes belong to generated codecs.
enum WireJSONCompatibility {
    enum Error: Swift.Error { case invalidJSON }

    /// Legacy adapters interpret ASCII protocol fields, never arbitrary Unicode
    /// property names. Keep those names in exact storage, like numeric lexemes,
    /// instead of allowing Swift Dictionary to merge canonical equivalents.
    /// Adapters must retain these carriers and mutate only ASCII protocol keys.
    private struct OpaqueFields: Hashable {
        let value: JSONObject
    }

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
            var result: [String: Any] = [:]
            var opaque = JSONObject()
            for (key, value) in fields {
                if key.utf8.allSatisfy({ $0 < 128 }) {
                    result[key] = view(value)
                } else {
                    opaque[key] = value
                }
            }
            if !opaque.isEmpty {
                // A private typed carrier cannot be supplied by a JSON client.
                // Avoid shadowing any real field, including the marker itself.
                var marker = "\0wire.opaque"
                while result[marker] != nil { marker += "\0" }
                result[marker] = OpaqueFields(value: opaque)
            }
            return result
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
            var exact = JSONObject()
            for (key, value) in fields {
                if let opaque = value as? OpaqueFields {
                    for (name, child) in opaque.value { exact[name] = child }
                } else {
                    exact[key] = try Self.value(value)
                }
            }
            return .object(
                .init(uniqueKeysWithValues: exact.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }))
        }
        throw Error.invalidJSON
    }

    static func data(_ value: Any) throws -> Data {
        try Self.value(value).serializedData()
    }
}
