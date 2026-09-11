import Foundation

/// Managed providers may accept `allowed_tools` while ignoring its subset.
/// Send the selected declarations with the equivalent ordinary choice mode.
enum ResponsesAllowedToolSelection {
    static func apply(to request: inout [String: Any]) throws -> Bool {
        guard let choice = request["tool_choice"] as? [String: Any],
            choice["type"] as? String == "allowed_tools"
        else { return false }
        guard let references = choice["tools"] as? [[String: Any]],
            let mode = choice["mode"] as? String, ["auto", "required"].contains(mode)
        else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        let allowed = try Set(references.map(identity))
        let selected = try (request["tools"] as? [[String: Any]] ?? []).filter {
            try allowed.contains(identity($0))
        }
        guard try Set(selected.map(identity)) == allowed, mode != "required" || !selected.isEmpty else {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
        request["tools"] = selected.isEmpty ? nil : selected
        request["tool_choice"] = selected.isEmpty ? "none" : mode
        return true
    }

    private static func identity(_ tool: [String: Any]) throws -> ProviderToolContractCatalog.Identity {
        guard let type = tool["type"] as? String, let kind = ProviderToolContractCatalog.Kind(rawValue: type),
            let name = nonemptyResponsesString(tool["name"])
        else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        return .init(name: name, namespace: nil, kind: kind)
    }
}
