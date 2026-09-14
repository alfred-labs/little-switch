import LittleSwitchWire

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
    var refusal: [String] = []
    var textStarted = false
    var textIndex = 0
    var refusalIndex: Int?
}

struct ChatCompletionToolCallState: Sendable {
    let itemID: String
    let callID: String
    let kind: ProviderToolContractCatalog.Kind
    var name: String
    var namespace: String?
    let outputIndex: Int
    var completedArguments: String
    var published = false
    var pendingArguments: [String] = []
}

struct ChatCompletionChoiceState: Sendable {
    let index: Int
    var message: ChatCompletionMessageState?
    var toolCalls: [Int: ChatCompletionToolCallState] = [:]
    var toolOutputOffset: Int?
    var finishReason: OpenAIChatFinishReason?
    var reasoning: [String: [String]] = [:]
    var reasoningIndex: Int?

    var leadingOutputCount: Int { reasoningIndex == nil ? 0 : 1 }
}

struct CompletedChatCompletionChoice: Sendable {
    let finishReason: OpenAIChatFinishReason
    let messageText: String?
    let toolCalls: [ChatCompletionToolCallState]
    let reasoning: [String: String]
    var refusal: String?
}
