import Foundation

/// Keeps tool selection references on the same namespace mapping as their declarations.
enum ResponsesToolChoice {
    static func normalized(
        _ value: Any,
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> Any {
        guard var choice = value as? [String: Any] else { return value }
        if choice["type"] as? String == "allowed_tools" {
            let selection = try allowedSelection(choice)
            choice["tools"] = try selection.tools.map { try reference($0, bindings: bindings) }
            return choice
        }
        return try reference(choice, bindings: bindings)
    }

    static func chat(_ value: Any?, bindings: [String: ResponsesToolNamespaces.Binding]) throws -> Any? {
        guard let value else { return nil }
        if let string = value as? String, ["auto", "none", "required"].contains(string) { return string }
        guard let choice = value as? [String: Any] else {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
        if choice["type"] as? String == "allowed_tools" {
            let selection = try allowedSelection(choice)
            let tools = try selection.tools.map { try chatReference(reference($0, bindings: bindings)) }
            return ["type": "allowed_tools", "allowed_tools": ["mode": selection.mode, "tools": tools]]
        }
        return try chatReference(reference(choice, bindings: bindings))
    }

    private static func allowedSelection(_ choice: [String: Any]) throws -> (mode: String, tools: [[String: Any]]) {
        guard let tools = choice["tools"] as? [[String: Any]],
            let mode = choice["mode"] as? String, ["auto", "required"].contains(mode)
        else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        return (mode, tools)
    }

    private static func reference(
        _ reference: [String: Any],
        bindings: [String: ResponsesToolNamespaces.Binding]
    ) throws -> [String: Any] {
        guard ["function", "custom"].contains(reference["type"] as? String ?? "") else { return reference }
        guard let namespaceValue = reference["namespace"], !(namespaceValue is NSNull) else { return reference }
        guard let namespace = nonemptyResponsesString(namespaceValue),
            let name = nonemptyResponsesString(reference["name"]),
            let wireName = bindings.first(where: { $0.value == .init(namespace: namespace, name: name) })?.key
        else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        var result = reference
        result["name"] = wireName
        result.removeValue(forKey: "namespace")
        return result
    }

    private static func chatReference(_ reference: [String: Any]) throws -> [String: Any] {
        guard let type = reference["type"] as? String, ["function", "custom"].contains(type),
            let name = nonemptyResponsesString(reference["name"])
        else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        return ["type": type, type: ["name": name]]
    }
}
