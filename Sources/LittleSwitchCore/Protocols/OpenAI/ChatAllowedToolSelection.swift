import Foundation

/// Chat-compatible providers may lack the newer `allowed_tools` union case.
/// Restricting the declarations and preserving its mode enforces the same set
/// using the original Chat tool-selection fields.
enum ChatAllowedToolSelection {
    static func apply(to request: inout [String: Any]) throws {
        guard let choice = request["tool_choice"] as? [String: Any],
            choice["type"] as? String == "allowed_tools"
        else { return }
        guard let selection = choice["allowed_tools"] as? [String: Any],
            let references = selection["tools"] as? [[String: Any]],
            let mode = selection["mode"] as? String, ["auto", "required"].contains(mode)
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
    }

    private static func identity(_ tool: [String: Any]) throws -> ProviderToolContractCatalog.Identity {
        guard let type = tool["type"] as? String, let kind = ProviderToolContractCatalog.Kind(rawValue: type),
            let reference = tool[type] as? [String: Any], let name = nonemptyResponsesString(reference["name"])
        else { throw OpenAIResponsesChatCompletions.Error.invalidRequest }
        return .init(name: name, namespace: nil, kind: kind)
    }
}
