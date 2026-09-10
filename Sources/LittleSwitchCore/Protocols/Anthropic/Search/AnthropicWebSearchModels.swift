import Foundation
import LittleSwitchSearch

package struct PreparedWebSearchRequest: Equatable, Sendable {
    let upstreamBody: Data
    let originalModel: String
    let streaming: Bool
    let maximumUses: Int
    let searchOptions: WebSearchFilterOptions
    package let privateToolName: String?

    package init(
        upstreamBody: Data,
        originalModel: String,
        streaming: Bool,
        maximumUses: Int,
        searchOptions: WebSearchFilterOptions = WebSearchFilterOptions(),
        privateToolName: String? = "web_search"
    ) {
        self.upstreamBody = upstreamBody
        self.originalModel = originalModel
        self.streaming = streaming
        self.maximumUses = maximumUses
        self.searchOptions = searchOptions
        self.privateToolName = privateToolName
    }
}

package struct WebSearchToolCall: Equatable, Sendable {
    let id: String
    let query: String
}

package struct AnthropicUsage: Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationInputTokens: Int
    var cacheReadInputTokens: Int
    var cacheCreationEphemeral1hInputTokens: Int
    var cacheCreationEphemeral5mInputTokens: Int
    var serviceTier: String?

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

    mutating func add(_ other: AnthropicUsage) {
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

package struct AnthropicModelTurn: Equatable, Sendable {
    let id: String
    let contentJSON: Data
    let stopReason: String?
    let stopSequenceJSON: Data?
    let usage: AnthropicUsage
    let webSearchCall: WebSearchToolCall?
}

package enum WebSearchTraceContent: Equatable, Sendable {
    case results([WebSearchResult])
    case error(String)
}

package struct WebSearchTrace: Equatable, Sendable {
    let toolUseID: String
    let query: String
    let content: WebSearchTraceContent
    let publicContentJSON: Data?

    package init(
        toolUseID: String,
        query: String,
        content: WebSearchTraceContent,
        publicContentJSON: Data? = nil
    ) {
        self.toolUseID = toolUseID
        self.query = query
        self.content = content
        self.publicContentJSON = publicContentJSON
    }
}
