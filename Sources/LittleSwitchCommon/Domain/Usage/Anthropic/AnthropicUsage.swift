import Foundation

package struct AnthropicUsage: Equatable, Sendable {
    package var inputTokens: Int
    package var outputTokens: Int
    package var cacheCreationInputTokens: Int
    package var cacheReadInputTokens: Int
    package var cacheCreationEphemeral1hInputTokens: Int
    package var cacheCreationEphemeral5mInputTokens: Int
    package var serviceTier: String?

    package init(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int = 0,
        cacheReadInputTokens: Int = 0,
        cacheCreationEphemeral1hInputTokens: Int = 0,
        cacheCreationEphemeral5mInputTokens: Int = 0,
        serviceTier: String? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationEphemeral1hInputTokens = cacheCreationEphemeral1hInputTokens
        self.cacheCreationEphemeral5mInputTokens = cacheCreationEphemeral5mInputTokens
        self.serviceTier = serviceTier
    }

    package mutating func add(_ other: AnthropicUsage) {
        inputTokens = saturatedAnthropicUsageSum(inputTokens, other.inputTokens)
        outputTokens = saturatedAnthropicUsageSum(outputTokens, other.outputTokens)
        cacheCreationInputTokens = saturatedAnthropicUsageSum(
            cacheCreationInputTokens,
            other.cacheCreationInputTokens
        )
        cacheReadInputTokens = saturatedAnthropicUsageSum(
            cacheReadInputTokens,
            other.cacheReadInputTokens
        )
        cacheCreationEphemeral1hInputTokens = saturatedAnthropicUsageSum(
            cacheCreationEphemeral1hInputTokens,
            other.cacheCreationEphemeral1hInputTokens
        )
        cacheCreationEphemeral5mInputTokens = saturatedAnthropicUsageSum(
            cacheCreationEphemeral5mInputTokens,
            other.cacheCreationEphemeral5mInputTokens
        )
        serviceTier = other.serviceTier ?? serviceTier
    }
}

private func saturatedAnthropicUsageSum(_ lhs: Int, _ rhs: Int) -> Int {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? Int.max : result.partialValue
}
