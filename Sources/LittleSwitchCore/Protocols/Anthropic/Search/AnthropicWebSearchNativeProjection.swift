import Foundation

extension AnthropicWebSearch {
    package static func successfulSearchCount(_ traces: [WebSearchTrace]) -> Int {
        traces.reduce(into: 0) { count, trace in
            if case .results = trace.content {
                count += 1
            }
        }
    }

    package static func normalizedStopReason(_ stopReason: String?) -> Any {
        switch stopReason {
        case "pause_turn":
            return "end_turn"
        case .some(let value):
            return value
        case .none:
            return NSNull()
        }
    }

    package static func nativeSearchErrorCode(_ code: String) -> String {
        if code == "invalid_request" {
            return "invalid_tool_input"
        }
        let nativeCodes: Set<String> = [
            "invalid_tool_input",
            "unavailable",
            "max_uses_exceeded",
            "too_many_requests",
            "query_too_long",
            "request_too_large",
        ]
        return nativeCodes.contains(code) ? code : "unavailable"
    }

    package static func nativeResultContent(_ trace: WebSearchTrace) throws -> Any {
        switch trace.content {
        case .results(let results):
            try PortableWebSearchHistory.validateResults(results)
            return try results.enumerated().map { index, result in
                [
                    "type": "web_search_result",
                    "url": result.url,
                    "title": result.title,
                    "encrypted_content": try PortableWebSearchHistory.anthropicReplayToken(
                        toolUseID: trace.toolUseID,
                        resultIndex: index,
                        result: result
                    ),
                    "page_age": NSNull(),
                ] as [String: Any]
            }
        case .error(let code):
            return [
                "type": "web_search_tool_result_error",
                "error_code": nativeSearchErrorCode(code),
            ]
        }
    }
}
