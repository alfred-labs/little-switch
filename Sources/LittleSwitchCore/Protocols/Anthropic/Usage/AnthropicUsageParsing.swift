import Foundation

extension AnthropicWebSearch {
    static func parseUsage(_ object: [String: Any]) throws -> AnthropicUsage {
        let cacheCreation = try optionalUsageObject(object["cache_creation"])
        return AnthropicUsage(
            inputTokens: try usageTokenCount(object["input_tokens"]),
            outputTokens: try usageTokenCount(object["output_tokens"]),
            cacheCreationInputTokens: try optionalUsageTokenCount(
                object["cache_creation_input_tokens"]
            ),
            cacheReadInputTokens: try optionalUsageTokenCount(
                object["cache_read_input_tokens"]
            ),
            cacheCreationEphemeral1hInputTokens: try requiredCacheCreationTokenCount(
                cacheCreation,
                key: "ephemeral_1h_input_tokens"
            ),
            cacheCreationEphemeral5mInputTokens: try requiredCacheCreationTokenCount(
                cacheCreation,
                key: "ephemeral_5m_input_tokens"
            ),
            serviceTier: try optionalServiceTier(object["service_tier"])
        )
    }

    private static func usageTokenCount(_ value: Any?) throws -> Int {
        guard let value = value as? Int, value >= 0 else {
            if value == nil {
                return 0
            }
            throw Error.invalidMessage
        }
        return value
    }

    private static func optionalUsageTokenCount(_ value: Any?) throws -> Int {
        guard let value, !(value is NSNull) else {
            return 0
        }
        return try usageTokenCount(value)
    }

    private static func optionalUsageObject(_ value: Any?) throws -> [String: Any]? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let object = value as? [String: Any] else {
            throw Error.invalidMessage
        }
        return object
    }

    private static func requiredCacheCreationTokenCount(
        _ cacheCreation: [String: Any]?,
        key: String
    ) throws -> Int {
        guard let cacheCreation else {
            return 0
        }
        guard cacheCreation[key] != nil else {
            throw Error.invalidMessage
        }
        return try usageTokenCount(cacheCreation[key])
    }

    private static func optionalServiceTier(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        guard let tier = value as? String,
            ["standard", "priority", "batch"].contains(tier)
        else {
            throw Error.invalidMessage
        }
        return tier
    }
}
