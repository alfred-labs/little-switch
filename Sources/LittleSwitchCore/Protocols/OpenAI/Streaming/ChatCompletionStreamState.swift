struct ChatCompletionStreamMetadata: Sendable {
    let chatID: String
    let responseID: String
    let created: Int
    let model: String
}

struct ChatCompletionMessageState: Sendable {
    let id: String
    let outputIndex: Int
    var completedText: String?
}

struct ChatCompletionToolCallState: Sendable {
    let itemID: String
    let callID: String
    let name: String
    let outputIndex: Int
    var completedArguments: String
}

struct ChatCompletionChoiceState: Sendable {
    let index: Int
    var message: ChatCompletionMessageState?
    var toolCalls: [Int: ChatCompletionToolCallState] = [:]
    var toolOutputOffset: Int?
    var finishReason: String?
}

struct ChatCompletionUsage: Sendable {
    let promptTokens: Int
    let cachedPromptTokens: Int
    let cacheWritePromptTokens: Int
    let completionTokens: Int
    let reasoningCompletionTokens: Int
    let totalTokens: Int
}

struct CompletedChatCompletionChoice: Sendable {
    let index: Int
    let finishReason: String
    let messageText: String?
    let toolCalls: [ChatCompletionToolCallState]
}
