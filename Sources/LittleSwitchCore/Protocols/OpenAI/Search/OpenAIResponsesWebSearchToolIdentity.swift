extension OpenAIResponsesWebSearch {
    /// The bridge owns only the unnamespaced function. An MCP tool with the
    /// same local name remains a public call that the client must execute.
    static func isPrivateSearchTool(_ tool: [String: Any], privateToolName: String? = "web_search") -> Bool {
        privateToolName != nil && tool["type"] as? String == "function"
            && tool["name"] as? String == privateToolName
            && tool["namespace"] as? String == nil
    }

    static func isPrivateSearchCall(_ item: [String: Any], privateToolName: String? = "web_search") -> Bool {
        privateToolName != nil && item["type"] as? String == "function_call"
            && item["name"] as? String == privateToolName
            && item["namespace"] as? String == nil
    }
}
