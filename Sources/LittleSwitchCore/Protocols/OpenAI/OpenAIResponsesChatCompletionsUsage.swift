import Foundation

extension OpenAIResponsesChatCompletions {
    package static func responsesUsage(_ value: Any?) throws -> ResponsesUsage {
        guard let value, !(value is NSNull) else {
            return ResponsesUsage(inputTokens: 0, outputTokens: 0)
        }
        guard let usage = value as? [String: Any] else {
            throw Error.invalidResponse
        }
        let input = try chatUsageTokenCount(usage["prompt_tokens"])
        let output = try chatUsageTokenCount(usage["completion_tokens"])
        let inputDetails = try optionalChatUsageDetails(
            usage["prompt_tokens_details"]
        )
        let outputDetails = try optionalChatUsageDetails(
            usage["completion_tokens_details"]
        )
        let total: Int?
        if let value = usage["total_tokens"], !(value is NSNull) {
            total = try chatUsageTokenCount(value)
        } else {
            total = nil
        }
        return ResponsesUsage(
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: try chatUsageTokenCount(
                inputDetails?["cached_tokens"]
            ),
            cacheWriteInputTokens: try chatUsageTokenCount(
                inputDetails?["cache_write_tokens"]
            ),
            reasoningOutputTokens: try chatUsageTokenCount(
                outputDetails?["reasoning_tokens"]
            ),
            totalTokens: total
        )
    }

    private static func optionalChatUsageDetails(
        _ value: Any?
    ) throws -> [String: Any]? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let details = value as? [String: Any] else {
            throw Error.invalidResponse
        }
        return details
    }

    private static func chatUsageTokenCount(_ value: Any?) throws -> Int {
        guard let value else {
            return 0
        }
        guard let count = value as? Int, count >= 0 else {
            throw Error.invalidResponse
        }
        return count
    }
}
