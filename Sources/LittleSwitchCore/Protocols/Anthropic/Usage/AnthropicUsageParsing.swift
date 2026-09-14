import LittleSwitchCommon
import LittleSwitchWire

extension AnthropicWebSearch {
    static func parseUsage(_ value: JSONValue) throws -> AnthropicUsage {
        let fields = try anthropicDecode(AnthropicUsageFields.self, from: value)
        let cache = fields.cacheCreation.value
        return AnthropicUsage(
            inputTokens: try bufferedTokenCount(fields.inputTokens),
            outputTokens: try bufferedTokenCount(fields.outputTokens),
            cacheCreationInputTokens: try fields.cacheCreationInputTokens.value.map(anthropicTokenCount) ?? 0,
            cacheReadInputTokens: try fields.cacheReadInputTokens.value.map(anthropicTokenCount) ?? 0,
            cacheCreationEphemeral1hInputTokens: try cache.map { try anthropicTokenCount($0.ephemeral1hInputTokens) }
                ?? 0,
            cacheCreationEphemeral5mInputTokens: try cache.map { try anthropicTokenCount($0.ephemeral5mInputTokens) }
                ?? 0,
            serviceTier: fields.serviceTier.value?.rawValue
        )
    }

    private static func bufferedTokenCount(_ value: JSONPresence<JSONNumber>) throws -> Int {
        switch value {
        case .absent: return 0
        case .null: throw Error.invalidMessage
        case .value(let number): return try anthropicTokenCount(number)
        }
    }
}
