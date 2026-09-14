import LittleSwitchCommon
import LittleSwitchWire

func chatWireIndex(_ value: JSONNumber) throws -> Int {
    guard let count: Int = try? value.integerValue(), count >= 0 else {
        throw OpenAIResponsesChatCompletions.Error.invalidResponse
    }
    return count
}

func chatWireUsage(_ value: OpenAIChatStreamUsage) throws -> ResponsesUsage {
    try ResponsesUsage(
        inputTokens: chatWireIndex(value.promptTokens),
        outputTokens: chatWireIndex(value.completionTokens),
        cachedInputTokens: value.promptTokensDetails.value?.cachedTokens.map(chatWireIndex) ?? 0,
        cacheWriteInputTokens: value.promptTokensDetails.value?.cacheWriteTokens.map(chatWireIndex) ?? 0,
        reasoningOutputTokens: value.completionTokensDetails.value?.reasoningTokens.map(chatWireIndex) ?? 0,
        totalTokens: value.totalTokens.value.map(chatWireIndex)
    )
}
