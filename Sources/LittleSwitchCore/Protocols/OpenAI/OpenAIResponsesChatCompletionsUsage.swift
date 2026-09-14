import LittleSwitchCommon
import LittleSwitchWire

extension OpenAIResponsesChatCompletions {
    static func responsesUsage(_ value: OpenAIChatBufferedUsage?) throws -> ResponsesUsage {
        guard let value else {
            return ResponsesUsage(inputTokens: 0, outputTokens: 0)
        }
        return try ResponsesUsage(
            inputTokens: value.promptTokens.map(chatWireIndex) ?? 0,
            outputTokens: value.completionTokens.map(chatWireIndex) ?? 0,
            cachedInputTokens: value.promptTokensDetails.value?.cachedTokens.map(chatWireIndex) ?? 0,
            cacheWriteInputTokens: value.promptTokensDetails.value?.cacheWriteTokens.map(chatWireIndex) ?? 0,
            reasoningOutputTokens: value.completionTokensDetails.value?.reasoningTokens.map(chatWireIndex) ?? 0,
            totalTokens: value.totalTokens.value.map(chatWireIndex)
        )
    }
}
