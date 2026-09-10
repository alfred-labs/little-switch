import Foundation

/// Reconstructs inference tools from explicit declarations and client discovery.
struct OpenAIResponsesToolSearchCatalog {
    private struct Identity: Hashable {
        let namespace: String?
        let name: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(namespace)
            hasher.combine(name)
        }
    }

    private struct LoadedTool {
        let identity: Identity
        let tool: [String: Any]
        let namespace: [String: Any]?
    }

    let tools: [[String: Any]]

    init(tools: [[String: Any]], loaded: [[String: Any]], deferUndiscovered: Bool) throws {
        let loadedTools = Self.latestDefinitions(try Self.loadedTools(loaded))
        let discovered = Set(loadedTools.map(\.identity))
        var seen: Set<Identity> = []
        var inference: [[String: Any]] = []
        for tool in tools {
            if tool["type"] as? String == "namespace" {
                guard let namespace = nonemptyResponsesString(tool["name"]),
                    let children = tool["tools"] as? [[String: Any]]
                else { throw OpenAIResponsesToolSearch.Error.invalidRequest }
                let visible = try children.compactMap {
                    try Self.visibleTool(
                        $0,
                        namespace: namespace,
                        discovered: discovered,
                        deferUndiscovered: deferUndiscovered,
                        seen: &seen
                    )
                }
                if !visible.isEmpty {
                    var group = tool
                    group["tools"] = visible
                    inference.append(group)
                }
            } else {
                let visible = try Self.visibleTool(
                    tool,
                    namespace: nil,
                    discovered: discovered,
                    deferUndiscovered: deferUndiscovered,
                    seen: &seen
                )
                if let visible { inference.append(visible) }
            }
        }
        for loaded in loadedTools where seen.insert(loaded.identity).inserted {
            var tool = loaded.tool
            tool.removeValue(forKey: "defer_loading")
            if var namespace = loaded.namespace {
                namespace["tools"] = [tool]
                inference.append(namespace)
            } else {
                inference.append(tool)
            }
        }
        self.tools = inference
    }

    private static func latestDefinitions(_ tools: [LoadedTool]) -> [LoadedTool] {
        var ordered: [LoadedTool] = []
        var positions: [Identity: Int] = [:]
        for tool in tools {
            if let index = positions[tool.identity] {
                ordered[index] = tool
            } else {
                positions[tool.identity] = ordered.count
                ordered.append(tool)
            }
        }
        return ordered
    }

    private static func visibleTool(
        _ tool: [String: Any],
        namespace: String?,
        discovered: Set<Identity>,
        deferUndiscovered: Bool,
        seen: inout Set<Identity>
    ) throws -> [String: Any]? {
        if tool["type"] as? String == "custom" { throw OpenAIResponsesToolSearch.Error.invalidRequest }
        guard tool["type"] as? String == "function" else { return tool }
        guard let name = nonemptyResponsesString(tool["name"]) else {
            throw OpenAIResponsesToolSearch.Error.invalidRequest
        }
        let identity = Identity(namespace: namespace, name: name)
        guard seen.insert(identity).inserted else { return nil }
        if let deferred = tool["defer_loading"] {
            guard let deferred = deferred as? Bool else { throw OpenAIResponsesToolSearch.Error.invalidRequest }
            if deferUndiscovered && deferred && !discovered.contains(identity) { return nil }
        }
        var result = tool
        result.removeValue(forKey: "defer_loading")
        return result
    }

    private static func loadedTools(_ tools: [[String: Any]]) throws -> [LoadedTool] {
        var loaded: [LoadedTool] = []
        for tool in tools {
            if tool["type"] as? String == "namespace" {
                guard let name = nonemptyResponsesString(tool["name"]),
                    let children = tool["tools"] as? [[String: Any]]
                else { throw OpenAIResponsesToolSearch.Error.invalidRequest }
                for child in children {
                    loaded.append(try entry(child, namespace: name, descriptor: tool))
                }
            } else {
                loaded.append(try entry(tool, namespace: nil, descriptor: nil))
            }
        }
        return loaded
    }

    private static func entry(
        _ tool: [String: Any],
        namespace: String?,
        descriptor: [String: Any]?
    ) throws -> LoadedTool {
        guard tool["type"] as? String == "function",
            let name = nonemptyResponsesString(tool["name"]),
            tool["parameters"] is [String: Any]
        else { throw OpenAIResponsesToolSearch.Error.invalidRequest }
        return LoadedTool(identity: Identity(namespace: namespace, name: name), tool: tool, namespace: descriptor)
    }
}
