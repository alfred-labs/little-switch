import Foundation
import LittleSwitchSearch

extension AnthropicWebSearch {
    static func followUpRequest(
        baseBody: Data,
        turn: AnthropicModelTurn,
        toolCall: WebSearchToolCall,
        resultText: String,
        mode: FollowUpMode,
        privateToolName: String? = toolName
    ) throws -> Data {
        var object = try object(from: baseBody)
        guard let privateToolName,
            var messages = object["messages"] as? [[String: Any]],
            let content = try fragmentObject(from: turn.contentJSON) as? [[String: Any]]
        else {
            throw Error.invalidMessage
        }

        let assistantContent = content.filter { block in
            guard block["type"] as? String == "tool_use" else {
                return true
            }
            return block["name"] as? String == privateToolName
                && block["id"] as? String == toolCall.id
        }
        guard
            assistantContent.contains(where: { block in
                block["type"] as? String == "tool_use"
                    && block["id"] as? String == toolCall.id
            })
        else {
            throw Error.invalidMessage
        }
        messages.append(["role": "assistant", "content": assistantContent])

        var result: [String: Any] = [
            "type": "tool_result",
            "tool_use_id": toolCall.id,
            "content": resultText,
        ]
        if mode == .terminalError {
            result["is_error"] = true
        }
        messages.append(["role": "user", "content": [result]])
        object["messages"] = messages

        if mode == .terminalError, let tools = object["tools"] as? [[String: Any]] {
            let remainingTools = tools.filter { $0["name"] as? String != privateToolName }
            if remainingTools.isEmpty {
                object.removeValue(forKey: "tools")
                object.removeValue(forKey: "tool_choice")
            } else {
                object["tools"] = remainingTools
                if let choice = object["tool_choice"] as? [String: Any] {
                    let isTool = choice["type"] as? String == "tool"
                    let namesSearch = choice["name"] as? String == privateToolName
                    let forcesSearch = isTool && namesSearch
                    if forcesSearch {
                        object["tool_choice"] = ["type": "auto"]
                    }
                }
            }
        }
        return try data(from: object)
    }

    static func formatResults(_ results: [WebSearchResult]) -> String {
        results
            .map { result in
                "Title: \(result.title)\nURL: \(result.url)\nContent: \(result.content)\n\n"
            }
            .joined()
    }

    static func nonStreamingResponse(
        originalModel: String,
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        usage: AnthropicUsage,
        privateToolName: String? = toolName
    ) throws -> Data {
        let response: [String: Any] = [
            "id": finalTurn.id,
            "type": "message",
            "role": "assistant",
            "model": originalModel,
            "content": try responseContent(traces: traces, finalTurn: finalTurn, privateToolName: privateToolName),
            "stop_reason": normalizedStopReason(finalTurn.stopReason),
            "stop_sequence": try fragmentObject(from: finalTurn.stopSequenceJSON),
            "usage": publicUsage(
                usage: usage,
                webSearchRequests: successfulSearchCount(traces)
            ),
        ]
        return try data(from: response)
    }

    static func streamingResponse(
        originalModel: String,
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        usage: AnthropicUsage,
        privateToolName: String? = toolName
    ) throws -> Data {
        var stream = Data()
        try appendEvent(
            name: "message_start",
            payload: [
                "type": "message_start",
                "message": [
                    "id": finalTurn.id,
                    "type": "message",
                    "role": "assistant",
                    "model": originalModel,
                    "content": [],
                    "stop_reason": NSNull(),
                    "stop_sequence": NSNull(),
                    "usage": publicUsage(
                        usage: usage,
                        outputTokens: 0,
                        webSearchRequests: 0
                    ),
                ],
            ],
            to: &stream
        )

        let content = try responseContent(traces: traces, finalTurn: finalTurn, privateToolName: privateToolName)
        for (index, block) in content.enumerated() {
            try appendStreamingBlock(block, index: index, to: &stream)
        }

        try appendEvent(
            name: "message_delta",
            payload: [
                "type": "message_delta",
                "delta": [
                    "stop_reason": normalizedStopReason(finalTurn.stopReason),
                    "stop_sequence": try fragmentObject(from: finalTurn.stopSequenceJSON),
                ],
                "usage": publicUsage(
                    usage: usage,
                    webSearchRequests: successfulSearchCount(traces)
                ),
            ],
            to: &stream
        )
        try appendEvent(
            name: "message_stop",
            payload: ["type": "message_stop"],
            to: &stream
        )
        return stream
    }
}
