import Foundation
import LittleSwitchCommon
import LittleSwitchWire

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
        let block = AnthropicWebSearchToolResultBlock(
            caller: .value(try AnthropicDirectCaller(type: .direct).wireJSON()),
            content: resultContent,
            toolUseId: trace.toolUseID,
            type: .webSearchToolResult
        )
        var frames =
            try publicContentStartFrames(.webSearchToolResult(block), index: index)
            + [contentStopFrame(index: index)]
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

        let frames = [
            try publicStreamFrame(
                name: AnthropicMessageDeltaEventType.messageDelta.rawValue,
                payload: publicMessageDelta(turn: turn, usage: usage, webSearchRequests: successfulSearchCount)
            ),
            try publicStreamFrame(
                name: AnthropicMessageStopEventType.messageStop.rawValue,
                payload: AnthropicMessageStopEvent(type: .messageStop).wireJSON()
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
