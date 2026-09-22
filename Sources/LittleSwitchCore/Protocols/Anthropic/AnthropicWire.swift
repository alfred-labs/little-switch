import Foundation
import LittleSwitchWire

/// Exact JSON values used for explicit, unconsumed Anthropic subtrees.
/// Known message, block, delta and usage shapes use their generated codecs.
func anthropicJSON(_ object: JSONObject) -> JSONValue {
    .object(.init(uniqueKeysWithValues: object.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }))
}

extension JSONValue {
    var anthropicObject: JSONObject? {
        object
    }

    var anthropicObjects: [JSONObject]? {
        guard let array else { return nil }
        let objects = array.compactMap(\.anthropicObject)
        return objects.count == array.count ? objects : nil
    }
}

func anthropicDecode<Value: WireCodable>(_ type: Value.Type, from value: JSONValue) throws -> Value {
    do {
        return try Value(wireJSON: value)
    } catch {
        throw AnthropicWebSearch.Error.invalidMessage
    }
}

func anthropicTokenCount(_ number: JSONNumber) throws -> Int {
    guard let count = try? number.integerValue(), count >= 0 else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return count
}
