import Foundation

/// Names on the exact provider request. Plain declarations participate in
/// namespace resolution so restoring a call cannot change its identity;
/// historical names reserve their spelling without authorizing new calls.
package struct ProviderToolNameCatalog: Equatable, Sendable {
    let declared: Set<String>
    let historical: Set<String>

    package init(declared: Set<String> = [], historical: Set<String> = []) {
        self.declared = declared
        self.historical = historical
    }

    static func history(in request: [String: Any], wire: ProviderToolContract.Wire) -> Set<String> {
        switch wire {
        case .anthropic:
            return []
        case .responses:
            let input = request["input"] as? [[String: Any]] ?? []
            return Set(
                input.compactMap { item in
                    guard ["function_call", "custom_tool_call"].contains(item["type"] as? String ?? "") else {
                        return nil
                    }
                    return item["name"] as? String
                })
        case .chatCompletions:
            let messages = request["messages"] as? [[String: Any]] ?? []
            return Set(
                messages.flatMap { message -> [String] in
                    var names = ((message["tool_calls"] as? [[String: Any]]) ?? []).compactMap { call -> String? in
                        guard let type = call["type"] as? String, ["function", "custom"].contains(type) else {
                            return nil
                        }
                        return (call[type] as? [String: Any])?["name"] as? String
                    }
                    if let legacyName = (message["function_call"] as? [String: Any])?["name"] as? String {
                        names.append(legacyName)
                    }
                    return names
                })
        }
    }
}
