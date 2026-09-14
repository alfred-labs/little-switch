import Foundation

package struct ResponsesUsage: Equatable, Sendable {
    package var inputTokens: Int
    package var outputTokens: Int
    package var cachedInputTokens: Int
    package var cacheWriteInputTokens: Int
    package var reasoningOutputTokens: Int
    package var totalTokens: Int

    package init(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int = 0,
        cacheWriteInputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens =
            totalTokens ?? saturatedResponsesUsageSum(inputTokens, outputTokens)
    }

    package mutating func add(_ other: ResponsesUsage) {
        inputTokens = saturatedResponsesUsageSum(inputTokens, other.inputTokens)
        outputTokens = saturatedResponsesUsageSum(outputTokens, other.outputTokens)
        cachedInputTokens = saturatedResponsesUsageSum(
            cachedInputTokens,
            other.cachedInputTokens
        )
        cacheWriteInputTokens = saturatedResponsesUsageSum(
            cacheWriteInputTokens,
            other.cacheWriteInputTokens
        )
        reasoningOutputTokens = saturatedResponsesUsageSum(
            reasoningOutputTokens,
            other.reasoningOutputTokens
        )
        totalTokens = saturatedResponsesUsageSum(totalTokens, other.totalTokens)
    }
}

private func saturatedResponsesUsageSum(_ lhs: Int, _ rhs: Int) -> Int {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? Int.max : result.partialValue
}
