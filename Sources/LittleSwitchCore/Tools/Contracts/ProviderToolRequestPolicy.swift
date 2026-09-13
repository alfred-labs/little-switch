import Foundation
import LittleSwitchWire

/// Hosted declarations require an explicit gateway adapter before inference.
package enum ProviderToolRequestPolicy {
    // Rejected beta extensions are a gateway policy, outside the stable SDK graph.
    private enum UnsupportedAnthropicExtensionKey: String {
        case mcpServers = "mcp_servers"
    }

    package static func anthropic(_ root: [String: JSONValue]) throws {
        if let servers = root[UnsupportedAnthropicExtensionKey.mcpServers.rawValue] {
            guard let servers = servers.anthropicObjects, servers.isEmpty else {
                throw ProviderToolContract.Error.invalidRequest
            }
        }
        let tools: [[String: JSONValue]]
        if let value = root[AnthropicCountTokensProjection.Key.tools.rawValue] {
            guard let objects = value.anthropicObjects else { throw ProviderToolContract.Error.invalidRequest }
            tools = objects
        } else {
            tools = []
        }
        for tool in tools {
            guard let type = tool[AnthropicToolDefinition.Key.type.rawValue]?.string else { continue }
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
