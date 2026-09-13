import Foundation
import LittleSwitchWire

@testable import LittleSwitchCore

/// Keeps existing Foundation-authored fixtures at the test boundary. Runtime
/// paths accept exact JSONValue or Data and never perform this conversion.
func anthropicTestJSON(_ value: Any) throws -> JSONValue {
    guard JSONSerialization.isValidJSONObject([value]) else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    do {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return try JSONValue.parse(data)
    } catch {
        throw AnthropicWebSearch.Error.invalidMessage
    }
}

func anthropicTestObject(_ value: Any) throws -> [String: JSONValue] {
    guard let object = try anthropicTestJSON(value).anthropicObject else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return object
}

func anthropicFoundationObject(_ value: [String: JSONValue]) throws -> [String: Any] {
    let data = try anthropicJSON(value).serializedData()
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return object
}

func anthropicPublicBlock(_ value: Any) throws -> [String: Any]? {
    try AnthropicPublicSanitizer.block(anthropicTestObject(value)).map(anthropicFoundationObject)
}

func anthropicPublicDelta(_ value: Any) throws -> [String: Any]? {
    try AnthropicPublicSanitizer.delta(anthropicTestObject(value)).map(anthropicFoundationObject)
}

func anthropicPortableHistory(_ value: [String: Any]) throws -> [String: Any] {
    try anthropicFoundationObject(PortableToolHistory.anthropic(anthropicTestObject(value)))
}

func anthropicReplayText(_ value: [String: Any]) throws -> String {
    try PortableWebSearchHistory.anthropicResultText(anthropicTestObject(value))
}
