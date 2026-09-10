import Foundation

extension AnthropicWebSearch {
    private static let supportedSearchTypes: Set<String> = [
        "web_search_20250305", "web_search_20260209", "web_search_20260318",
    ]

    static func isBuiltInSearchTool(_ tool: [String: Any]) -> Bool {
        guard let type = tool["type"] as? String else {
            return false
        }
        return supportedSearchTypes.contains(type)
    }

    static func isPrivateSearchBlock(_ block: [String: Any], privateToolName: String?) -> Bool {
        guard let privateToolName else {
            return false
        }
        return block["type"] as? String == "tool_use" && block["name"] as? String == privateToolName
    }

    static func builtInSearchTool(in tools: [[String: Any]]) throws -> [String: Any]? {
        var selected: [String: Any]?
        for tool in tools {
            if let type = tool["type"] as? String, type.hasPrefix("web_search") {
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
        clientTools: [[String: Any]],
        messages: [[String: Any]]
    ) -> String {
        var occupied = Set(clientTools.compactMap { $0["name"] as? String })
        var blocks = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        while let block = blocks.popLast() {
            if block["type"] as? String == "tool_use", let name = block["name"] as? String {
                occupied.insert(name)
            }
            if block["type"] as? String == "tool_reference", let name = block["tool_name"] as? String {
                occupied.insert(name)
            }
            if let nested = block["content"] as? [[String: Any]] {
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
