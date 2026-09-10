import Foundation

extension AnthropicPublicStreamSession {
    package mutating func finishSearch(_ trace: WebSearchTrace) throws -> [Data] {
        guard terminalState == .open,
            let pendingSearch,
            pendingSearch.toolUseID == trace.toolUseID,
            pendingSearch.query == trace.query
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        let resultContent = try AnthropicWebSearch.nativeResultContent(trace)
        if case .results = trace.content {
            successfulSearchCount += 1
        }

        let index = allocatePublicIndex()
        var frames = [
            try publicStreamFrame(
                name: "content_block_start",
                payload: [
                    "type": "content_block_start",
                    "index": index,
                    "content_block": [
                        "type": "web_search_tool_result",
                        "tool_use_id": trace.toolUseID,
                        "content": resultContent,
                        "caller": ["type": "direct"],
                    ],
                ]
            ),
            try contentStopFrame(index: index),
        ]
        frames += try flushPostSearchTurn()
        self.pendingSearch = nil
        return frames
    }

    package mutating func finish(
        turn: AnthropicModelTurn,
        usage: AnthropicUsage
    ) throws -> [Data] {
        guard terminalState == .open,
            started,
            !providerTurnActive,
            pendingSearch == nil,
            bufferedEvents.isEmpty,
            postSearchEvents.isEmpty
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        let stopReason = AnthropicWebSearch.normalizedStopReason(turn.stopReason)
        let stopSequence = try publicStreamFragment(turn.stopSequenceJSON)
        let frames = [
            try publicStreamFrame(
                name: "message_delta",
                payload: [
                    "type": "message_delta",
                    "delta": [
                        "stop_reason": stopReason,
                        "stop_sequence": stopSequence,
                    ],
                    "usage": publicUsage(
                        usage: usage,
                        webSearchRequests: successfulSearchCount
                    ),
                ]
            ),
            try publicStreamFrame(
                name: "message_stop",
                payload: ["type": "message_stop"]
            ),
        ]
        terminalState = .completed
        return frames
    }

    package mutating func fail(message: String) throws -> [Data] {
        _ = message
        guard terminalState == .open else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let frame = try publicStreamFrame(
            name: "error",
            payload: [
                "type": "error",
                "error": [
                    "type": "api_error",
                    "message": "Internal server error",
                ],
            ]
        )
        terminalState = .failed
        return [frame]
    }
}
