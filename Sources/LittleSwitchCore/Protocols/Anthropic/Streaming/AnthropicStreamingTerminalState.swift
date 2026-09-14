import LittleSwitchCommon
import LittleSwitchWire

struct AnthropicTerminalDeltaState: Sendable {
    private var stopReason: OpenWireValue<AnthropicDeltaStopReason>?
    private var stopSequence: String?

    mutating func apply(_ update: AnthropicMessageDelta) {
        if let value = update.stopReason.value { stopReason = value }
        if let value = update.stopSequence.value { stopSequence = value }
    }

    func apply(to message: inout AnthropicMessage) {
        if let stopReason { message.stopReason = .value(OpenWireValue(rawValue: stopReason.rawValue)) }
        if let stopSequence { message.stopSequence = .value(.string(stopSequence)) }
    }
}

struct AnthropicTerminalUsageState: Sendable {
    private var usage = AnthropicUsage(inputTokens: 0, outputTokens: 0)

    init() {}

    init(_ initial: JSONValue) throws { try apply(initial) }

    func wireJSON() throws -> JSONValue {
        try usageFields(usage).wireJSON()
    }

    mutating func apply(_ update: JSONValue) throws {
        let fields = try anthropicDecode(AnthropicUsageFields.self, from: update)
        if let value = fields.inputTokens.value { usage.inputTokens = try anthropicTokenCount(value) }
        if let value = fields.outputTokens.value { usage.outputTokens = try anthropicTokenCount(value) }
        if let value = fields.cacheCreationInputTokens.value {
            usage.cacheCreationInputTokens = try anthropicTokenCount(value)
        }
        if let value = fields.cacheReadInputTokens.value { usage.cacheReadInputTokens = try anthropicTokenCount(value) }
        if let cache = fields.cacheCreation.value {
            usage.cacheCreationEphemeral1hInputTokens = try anthropicTokenCount(cache.ephemeral1hInputTokens)
            usage.cacheCreationEphemeral5mInputTokens = try anthropicTokenCount(cache.ephemeral5mInputTokens)
        }
        if let tier = fields.serviceTier.value { usage.serviceTier = tier.rawValue }
    }
}

func usageFields(_ usage: AnthropicUsage, outputTokens: Int? = nil) -> AnthropicUsageFields {
    AnthropicUsageFields(
        cacheCreation: .value(
            AnthropicCacheCreation(
                ephemeral1hInputTokens: JSONNumber(usage.cacheCreationEphemeral1hInputTokens),
                ephemeral5mInputTokens: JSONNumber(usage.cacheCreationEphemeral5mInputTokens)
            )),
        cacheCreationInputTokens: .value(JSONNumber(usage.cacheCreationInputTokens)),
        cacheReadInputTokens: .value(JSONNumber(usage.cacheReadInputTokens)),
        inputTokens: .value(JSONNumber(usage.inputTokens)),
        outputTokens: .value(JSONNumber(outputTokens ?? usage.outputTokens)),
        serviceTier: usage.serviceTier.flatMap(AnthropicServiceTier.init(rawValue:)).map(JSONPresence.value) ?? .null
    )
}
