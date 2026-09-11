import Foundation

/// Hosted declarations require an explicit gateway adapter before inference.
package enum ProviderToolRequestPolicy {
    package static func anthropic(_ root: [String: Any]) throws {
        if let servers = root["mcp_servers"] {
            guard let servers = servers as? [[String: Any]], servers.isEmpty else {
                throw ProviderToolContract.Error.invalidRequest
            }
        }
        for tool in try tools(in: root) {
            guard let type = tool["type"] as? String else { continue }
            let hostedTypes = ["web_search", "web_fetch", "code_execution", "tool_search_tool", "mcp_toolset"]
            if hostedTypes.contains(where: type.hasPrefix) {
                throw ProviderToolContract.Error.invalidRequest
            }
        }
    }

    package static func responses(
        _ root: [String: Any], allowingWebSearch: Bool = false
    ) throws {
        try ProviderToolContractCatalog.validateResponsesDeclarations(tools(in: root))
        try validateResponsesTools(
            tools(in: root), allowingWebSearch: allowingWebSearch)
        for item in root["input"] as? [[String: Any]] ?? []
        where ["tool_search_call", "tool_search_output"].contains(item["type"] as? String ?? "") {
            throw ProviderToolContract.Error.invalidRequest
        }
    }

    private static func validateResponsesTools(
        _ tools: [[String: Any]], allowingWebSearch: Bool
    ) throws {
        for tool in tools {
            if allowingWebSearch, OpenAIResponsesWebSearch.isBuiltInSearchTool(tool) { continue }
            switch tool["type"] as? String {
            case "function", "custom": break
            case "namespace":
                try validateResponsesTools(
                    self.tools(in: tool), allowingWebSearch: false)
            default:
                throw ProviderToolContract.Error.invalidRequest
            }
        }
    }

    private static func tools(in root: [String: Any]) throws -> [[String: Any]] {
        guard let value = root["tools"] else { return [] }
        guard let tools = value as? [[String: Any]] else { throw ProviderToolContract.Error.invalidRequest }
        return tools
    }
}
