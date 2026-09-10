extension OpenAIResponsesWebSearch {
    /// Keep a choice consistent with the tools left after search is removed,
    /// both when the client refuses search and after a terminal search error.
    static func toolChoiceWithoutSearch(
        _ choice: Any?,
        remainingTools: [[String: Any]],
        privateToolName: String? = "web_search"
    ) -> Any? {
        guard !remainingTools.isEmpty else {
            return nil
        }
        guard let forced = choice as? [String: Any] else {
            return choice
        }
        if isBuiltInSearchTool(forced) || isPrivateSearchTool(forced, privateToolName: privateToolName) {
            return "auto"
        }
        return choice
    }
}
