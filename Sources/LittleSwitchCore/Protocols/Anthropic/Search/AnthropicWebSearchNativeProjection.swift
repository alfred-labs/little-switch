import Foundation
import LittleSwitchWire

extension AnthropicWebSearch {
    package static func successfulSearchCount(_ traces: [WebSearchTrace]) -> Int {
        traces.reduce(into: 0) { count, trace in
            if case .results = trace.content { count += 1 }
        }
    }

    package static func normalizedStopReason(_ stopReason: String?) -> JSONValue {
        switch stopReason {
        case AnthropicStopReason.pauseTurn.rawValue: return .string(AnthropicStopReason.endTurn.rawValue)
        case .some(let value): return .string(value)
        case .none: return .null
        }
    }

    private static func nativeSearchErrorCode(_ code: String) -> AnthropicWebSearchErrorCode {
        if code == "invalid_request" { return .invalidToolInput }
        return AnthropicWebSearchErrorCode(rawValue: code) ?? .unavailable
    }

    static func nativeResultContent(_ trace: WebSearchTrace) throws -> AnthropicWebSearchContent {
        switch trace.content {
        case .results(let results):
            try PortableWebSearchHistory.validateResults(results)
            return .variant2(
                try results.enumerated().map { index, result in
                    AnthropicWebSearchResult(
                        encryptedContent: try PortableWebSearchHistory.anthropicReplayToken(
                            toolUseID: trace.toolUseID, resultIndex: index, result: result
                        ),
                        pageAge: nil,
                        title: result.title,
                        type: .webSearchResult,
                        url: result.url
                    )
                })
        case .error(let code):
            return .variant1(
                AnthropicWebSearchError(
                    errorCode: nativeSearchErrorCode(code),
                    type: .webSearchToolResultError
                ))
        }
    }
}
