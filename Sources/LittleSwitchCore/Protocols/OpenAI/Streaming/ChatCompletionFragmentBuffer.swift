struct ChatCompletionFragmentBuffer: Sendable {
    private struct ToolCallKey: Hashable, Sendable {
        let choiceIndex: Int
        let toolIndex: Int
    }

    private var messageText: [Int: [String]] = [:]
    private var toolArguments: [ToolCallKey: [String]] = [:]

    mutating func appendText(_ fragment: String, choiceIndex: Int) {
        messageText[choiceIndex, default: []].append(fragment)
    }

    mutating func appendArguments(
        _ fragment: String,
        choiceIndex: Int,
        toolIndex: Int
    ) {
        let key = ToolCallKey(choiceIndex: choiceIndex, toolIndex: toolIndex)
        toolArguments[key, default: []].append(fragment)
    }

    mutating func finalizeText(choiceIndex: Int) -> String {
        messageText.removeValue(forKey: choiceIndex)?.joined() ?? ""
    }

    mutating func finalizeArguments(choiceIndex: Int, toolIndex: Int) -> String {
        let key = ToolCallKey(choiceIndex: choiceIndex, toolIndex: toolIndex)
        return toolArguments.removeValue(forKey: key)?.joined() ?? ""
    }
}
