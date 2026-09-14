import Foundation
import LittleSwitchCommon
import LittleSwitchSearch
import LittleSwitchWire

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
            let priorMessages = object[AnthropicCountTokensProjection.Key.messages.rawValue]?.anthropicObjects,
            let content = try fragmentObject(from: turn.contentJSON).anthropicObjects
        else { throw Error.invalidMessage }
        let assistantContent = content.filter { block in
            guard block[AnthropicToolUseParam.Key.type.rawValue]?.string == AnthropicToolUseParamType.toolUse.rawValue
            else { return true }
            return block[AnthropicToolUseParam.Key.name.rawValue]?.string == privateToolName
                && block[AnthropicToolUseParam.Key.id.rawValue]?.string == toolCall.id
        }
        guard
            assistantContent.contains(where: {
                $0[AnthropicToolUseParam.Key.type.rawValue]?.string == AnthropicToolUseParamType.toolUse.rawValue
                    && $0[AnthropicToolUseParam.Key.id.rawValue]?.string == toolCall.id
            })
        else { throw Error.invalidMessage }
        let assistant = AnthropicMessageParam(
            content: .variant2(
                try assistantContent.map {
                    try anthropicDecode(AnthropicContentBlockParam.self, from: anthropicJSON($0))
                }),
            role: .assistant
        )
        let result = AnthropicToolResultParam(
            content: .value(.string(resultText)),
            isError: mode == .terminalError ? true : nil,
            toolUseId: toolCall.id,
            type: .toolResult
        )
        let user = AnthropicMessageParam(content: .variant2([.toolResult(result)]), role: .user)
        object[AnthropicCountTokensProjection.Key.messages.rawValue] = .array(
            priorMessages.map(anthropicJSON) + [try assistant.wireJSON(), try user.wireJSON()]
        )
        let declarations = object[AnthropicCountTokensProjection.Key.tools.rawValue]?.anthropicObjects
        if mode == .terminalError, let tools = declarations {
            let remainingTools = tools.filter {
                $0[AnthropicToolDefinition.Key.name.rawValue]?.string != privateToolName
            }
            if remainingTools.isEmpty {
                object.removeValue(forKey: AnthropicCountTokensProjection.Key.tools.rawValue)
                object.removeValue(forKey: AnthropicCountTokensProjection.Key.toolChoice.rawValue)
            } else {
                object[AnthropicCountTokensProjection.Key.tools.rawValue] = .array(remainingTools.map(anthropicJSON))
                let choice = object[AnthropicCountTokensProjection.Key.toolChoice.rawValue].flatMap {
                    try? AnthropicNamedToolChoice(wireJSON: $0)
                }
                if choice?.name == privateToolName {
                    object[AnthropicCountTokensProjection.Key.toolChoice.rawValue] = try AnthropicAutomaticToolChoice(
                        type: .auto
                    ).wireJSON()
                }
            }
        }
        return try data(from: object)
    }

    static func formatResults(_ results: [WebSearchResult]) -> String {
        let passages = results.map { result in
            "Title: \(result.title)\nURL: \(result.url)\nContent: \(result.content)\n\n"
        }
        return passages.joined()
    }

    static func nonStreamingResponse(
        originalModel: String,
        traces: [WebSearchTrace],
        finalTurn: AnthropicModelTurn,
        usage: AnthropicUsage,
        privateToolName: String? = toolName
    ) throws -> Data {
        let content = try responseContent(traces: traces, finalTurn: finalTurn, privateToolName: privateToolName)
        let stopSequence = try fragmentObject(from: finalTurn.stopSequenceJSON)
        let message = try AnthropicMessage(
            content: content.map(anthropicJSON),
            id: finalTurn.id,
            stopReason: normalizedStopReason(finalTurn.stopReason).string.map {
                .value(OpenWireValue(rawValue: $0))
            } ?? .null,
            stopSequence: stopSequence.isNull ? .null : .value(stopSequence),
            usage: publicUsage(usage: usage, webSearchRequests: successfulSearchCount(traces))
        )
        return try publicMessage(message, model: originalModel).serializedData()
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
            name: AnthropicMessageStartEventType.messageStart.rawValue,
            payload: AnthropicMessageStartEvent(
                message: publicMessage(
                    AnthropicMessage(
                        content: [],
                        id: finalTurn.id,
                        stopReason: .null,
                        stopSequence: .null,
                        usage: publicUsage(usage: usage, outputTokens: 0, webSearchRequests: 0)
                    ),
                    model: originalModel
                ),
                type: .messageStart
            ).wireJSON(),
            to: &stream
        )
        let content = try responseContent(traces: traces, finalTurn: finalTurn, privateToolName: privateToolName)
        for (index, block) in content.enumerated() {
            try appendStreamingBlock(block, index: index, to: &stream)
        }
        try appendEvent(
            name: AnthropicMessageDeltaEventType.messageDelta.rawValue,
            payload: publicMessageDelta(
                turn: finalTurn, usage: usage, webSearchRequests: successfulSearchCount(traces)),
            to: &stream
        )
        try appendEvent(
            name: AnthropicMessageStopEventType.messageStop.rawValue,
            payload: AnthropicMessageStopEvent(type: .messageStop).wireJSON(),
            to: &stream
        )
        return stream
    }
}

func publicMessage(_ message: AnthropicMessage, model: String) throws -> JSONValue {
    try AnthropicMessageMetadata(
        model: model,
        role: .assistant,
        type: .message,
        additionalFields: WireObject(message.wireJSON()).additionalFields(excluding: [])
    ).wireJSON()
}

func publicMessageDelta(turn: AnthropicModelTurn, usage: AnthropicUsage, webSearchRequests: Int) throws -> JSONValue {
    // Public stop_sequence historically accepts an opaque fragment. Preserve it
    // in the emitted delta while the incoming terminal codec remains string/null.
    let fields = AnthropicMessageDelta(
        stopReason: AnthropicWebSearch.normalizedStopReason(turn.stopReason).string.map {
            .value(OpenWireValue(rawValue: $0))
        } ?? .null,
        stopSequence: .absent
    )
    var delta = try WireObject(fields.wireJSON()).additionalFields(excluding: [])
    delta[AnthropicMessageDelta.Key.stopSequence.rawValue] = try AnthropicWebSearch.fragmentObject(
        from: turn.stopSequenceJSON)
    return try AnthropicPublicMessageDeltaEvent(
        delta: anthropicJSON(delta),
        type: .messageDelta,
        usage: publicUsage(usage: usage, webSearchRequests: webSearchRequests)
    ).wireJSON()
}
