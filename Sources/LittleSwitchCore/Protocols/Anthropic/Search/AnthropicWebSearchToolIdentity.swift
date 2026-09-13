import Foundation
import LittleSwitchWire

extension AnthropicWebSearch {
    private static let supportedSearchTypes: Set<String> = [
        "web_search_20250305", "web_search_20260209", "web_search_20260318",
    ]

    static func isBuiltInSearchTool(_ tool: [String: JSONValue]) -> Bool {
        guard let type = tool[AnthropicToolDefinition.Key.type.rawValue]?.string else {
            return false
        }
        return supportedSearchTypes.contains(type)
    }

    static func isPrivateSearchBlock(_ block: [String: JSONValue], privateToolName: String?) -> Bool {
        guard let privateToolName else {
            return false
        }
        return block[AnthropicToolUseParam.Key.type.rawValue]?.string == AnthropicToolUseParamType.toolUse.rawValue
            && block[AnthropicToolUseParam.Key.name.rawValue]?.string == privateToolName
    }

    static func builtInSearchTool(in tools: [[String: JSONValue]]) throws -> [String: JSONValue]? {
        var selected: [String: JSONValue]?
        for tool in tools {
            if let type = tool[AnthropicToolDefinition.Key.type.rawValue]?.string, type.hasPrefix("web_search") {
                guard supportedSearchTypes.contains(type) else {
                    throw Error.invalidMessage
                }
            }
            guard isBuiltInSearchTool(tool) else {
                continue
            }
            guard selected == nil else {
                throw Error.invalidMessage
            }
            selected = tool
        }
        return selected
    }

    static func privateSearchToolName(
        clientTools: [[String: JSONValue]],
        messages: [[String: JSONValue]]
    ) -> String {
        var occupied = Set(clientTools.compactMap { $0[AnthropicToolDefinition.Key.name.rawValue]?.string })
        var blocks = messages.flatMap { $0[AnthropicMessageParam.Key.content.rawValue]?.anthropicObjects ?? [] }
        while let block = blocks.popLast() {
            switch block[AnthropicToolUseParam.Key.type.rawValue]?.string {
            case AnthropicToolUseParamType.toolUse.rawValue:
                if let name = block[AnthropicToolUseParam.Key.name.rawValue]?.string { occupied.insert(name) }
            case AnthropicToolReferenceIdentityType.toolReference.rawValue:
                if let name = block[AnthropicToolReferenceIdentity.Key.toolName.rawValue]?.string {
                    occupied.insert(name)
                }
            default: break
            }
            if let nested = block[AnthropicToolResultParam.Key.content.rawValue]?.anthropicObjects {
                blocks.append(contentsOf: nested)
            }
        }
        guard occupied.contains(toolName) else {
            return toolName
        }
        let base = "__little_switch_web_search"
        var name = base
        var ordinal = 2
        while occupied.contains(name) {
            name = "\(base)_\(ordinal)"
            ordinal += 1
        }
        return name
    }
}
