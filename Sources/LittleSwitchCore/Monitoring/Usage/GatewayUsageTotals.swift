import Foundation

/// Token usage a provider reported for one gateway request.
///
/// Providers spell usage differently — Anthropic reports `input_tokens` next to
/// separate cache counters, OpenAI folds cached input into `prompt_tokens`. The
/// gateway normalizes both into these four disjoint fields so `total` never
/// counts a token twice.
public struct GatewayUsageTotals: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0
    ) {
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cacheReadTokens = max(0, cacheReadTokens)
        self.cacheWriteTokens = max(0, cacheWriteTokens)
    }

    public var total: Int {
        saturatedGatewayUsageSum(
            saturatedGatewayUsageSum(inputTokens, outputTokens),
            saturatedGatewayUsageSum(cacheReadTokens, cacheWriteTokens)
        )
    }

    public var isEmpty: Bool {
        total == 0
    }

    /// Adds two independent measurements, saturating instead of trapping.
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            inputTokens: saturatedGatewayUsageSum(lhs.inputTokens, rhs.inputTokens),
            outputTokens: saturatedGatewayUsageSum(lhs.outputTokens, rhs.outputTokens),
            cacheReadTokens: saturatedGatewayUsageSum(lhs.cacheReadTokens, rhs.cacheReadTokens),
            cacheWriteTokens: saturatedGatewayUsageSum(lhs.cacheWriteTokens, rhs.cacheWriteTokens)
        )
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    /// Combines two samples of the *same* request. Streaming responses report
    /// usage more than once and the later samples are cumulative, so the
    /// per-field maximum is the reading that survives.
    public func merging(_ other: Self) -> Self {
        Self(
            inputTokens: max(inputTokens, other.inputTokens),
            outputTokens: max(outputTokens, other.outputTokens),
            cacheReadTokens: max(cacheReadTokens, other.cacheReadTokens),
            cacheWriteTokens: max(cacheWriteTokens, other.cacheWriteTokens)
        )
    }
}

func saturatedGatewayUsageSum(_ lhs: Int, _ rhs: Int) -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : sum
}
