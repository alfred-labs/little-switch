import Foundation

struct AnthropicTerminalDeltaState: Sendable {
    private var stopReason: String?
    private var stopSequence: String?

    mutating func apply(_ update: [String: Any]) throws {
        if let value = try anthropicTerminalString(update, key: "stop_reason") {
            stopReason = value
        }
        if let value = try anthropicTerminalString(update, key: "stop_sequence") {
            stopSequence = value
        }
    }

    func apply(to message: inout [String: Any]) {
        if let stopReason {
            message["stop_reason"] = stopReason
        }
        if let stopSequence {
            message["stop_sequence"] = stopSequence
        }
    }
}

struct AnthropicTerminalUsageState: Sendable {
    private var usage = AnthropicUsage(inputTokens: 0, outputTokens: 0)

    init() {}

    init(_ initial: [String: Any]) throws {
        try apply(initial)
    }

    var jsonObject: [String: Any] {
        [
            "input_tokens": usage.inputTokens,
            "output_tokens": usage.outputTokens,
            "cache_creation_input_tokens": usage.cacheCreationInputTokens,
            "cache_read_input_tokens": usage.cacheReadInputTokens,
            "cache_creation": [
                "ephemeral_1h_input_tokens": usage.cacheCreationEphemeral1hInputTokens,
                "ephemeral_5m_input_tokens": usage.cacheCreationEphemeral5mInputTokens,
            ],
            "service_tier": usage.serviceTier.map { $0 as Any } ?? NSNull(),
        ]
    }

    mutating func apply(_ update: [String: Any]) throws {
        if let value = try anthropicTerminalTokenCount(update, key: "input_tokens") {
            usage.inputTokens = value
        }
        if let value = try anthropicTerminalTokenCount(update, key: "output_tokens") {
            usage.outputTokens = value
        }
        if let value = try anthropicTerminalTokenCount(
            update,
            key: "cache_creation_input_tokens"
        ) {
            usage.cacheCreationInputTokens = value
        }
        if let value = try anthropicTerminalTokenCount(
            update,
            key: "cache_read_input_tokens"
        ) {
            usage.cacheReadInputTokens = value
        }
        if let cacheCreation = try anthropicTerminalObject(
            update,
            key: "cache_creation"
        ) {
            usage.cacheCreationEphemeral1hInputTokens = try anthropicRequiredTokenCount(
                cacheCreation,
                key: "ephemeral_1h_input_tokens"
            )
            usage.cacheCreationEphemeral5mInputTokens = try anthropicRequiredTokenCount(
                cacheCreation,
                key: "ephemeral_5m_input_tokens"
            )
        }
        if let value = try anthropicTerminalServiceTier(update) {
            usage.serviceTier = value
        }
    }
}

private func anthropicTerminalString(
    _ object: [String: Any],
    key: String
) throws -> String? {
    guard let value = object[key], !(value is NSNull) else {
        return nil
    }
    guard let value = value as? String else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return value
}

private func anthropicTerminalTokenCount(
    _ object: [String: Any],
    key: String
) throws -> Int? {
    guard let value = object[key], !(value is NSNull) else {
        return nil
    }
    guard let value = value as? Int, value >= 0 else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return value
}

private func anthropicRequiredTokenCount(
    _ object: [String: Any],
    key: String
) throws -> Int {
    guard let value = object[key] as? Int, value >= 0 else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return value
}

private func anthropicTerminalObject(
    _ object: [String: Any],
    key: String
) throws -> [String: Any]? {
    guard let value = object[key], !(value is NSNull) else {
        return nil
    }
    guard let value = value as? [String: Any] else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return value
}

private func anthropicTerminalServiceTier(_ object: [String: Any]) throws -> String? {
    guard let value = object["service_tier"], !(value is NSNull) else {
        return nil
    }
    guard let value = value as? String,
        ["standard", "priority", "batch"].contains(value)
    else {
        throw AnthropicWebSearch.Error.invalidMessage
    }
    return value
}
