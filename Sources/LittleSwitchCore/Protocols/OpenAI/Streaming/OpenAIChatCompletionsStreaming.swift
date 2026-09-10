import Foundation
import LittleSwitchTransport

package struct OpenAIChatCompletionsAccumulator: Sendable {
    private static let defaultMaximumTurnBytes = 8 * 1_024 * 1_024

    private let prepared: PreparedResponsesChatCompletionsRequest
    private let maximumTurnBytes: Int
    private var phase: ChatCompletionAccumulatorPhase = .open
    private var consumedBytes = 0
    private var metadata: ChatCompletionStreamMetadata?
    private var choices: [Int: ChatCompletionChoiceState] = [:]
    private var fragments = ChatCompletionFragmentBuffer()
    private var usage: ChatCompletionUsage?
    private var completedTurn: ResponsesModelTurn?

    package init(
        prepared: PreparedResponsesChatCompletionsRequest,
        maximumTurnBytes: Int = Self.defaultMaximumTurnBytes
    ) {
        self.prepared = prepared
        self.maximumTurnBytes = max(0, maximumTurnBytes)
    }

    package mutating func consume(
        _ frame: ServerSentEventFrame
    ) throws -> [ResponsesProviderStreamEvent] {
        guard phase == .open else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        if frame.terminal {
            return try completeStream()
        }
        try charge(frame.data.count)
        guard usage == nil else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let chunk = try chatObject(frame.data)
        let metadataResult = try consumeMetadata(chunk)
        guard let rawChoices = chunk["choices"] as? [[String: Any]] else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }

        var events: [ResponsesProviderStreamEvent] = []
        if metadataResult.started {
            events.append(
                .responseStarted(
                    responseJSON: try chatStartedResponseJSON(
                        responseID: metadataResult.metadata.responseID,
                        created: metadataResult.metadata.created,
                        originalModel: prepared.originalModel
                    )
                )
            )
        }
        var frameChoiceIndices: Set<Int> = []
        for rawChoice in rawChoices {
            guard let index = nonnegativeChatIndex(rawChoice["index"]),
                frameChoiceIndices.insert(index).inserted
            else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            events += try consumeChoice(
                rawChoice,
                index: index,
                metadata: metadataResult.metadata
            )
        }
        try consumeUsage(chunk["usage"])
        return events
    }

    package mutating func finish() throws -> ResponsesModelTurn {
        guard phase == .terminal, let completedTurn else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        phase = .finished
        return completedTurn
    }
}

extension OpenAIChatCompletionsAccumulator {
    private mutating func consumeMetadata(
        _ chunk: [String: Any]
    ) throws -> (started: Bool, metadata: ChatCompletionStreamMetadata) {
        guard let chatID = nonemptyChatString(chunk["id"]),
            chunk["object"] as? String == "chat.completion.chunk",
            let created = nonnegativeChatIndex(chunk["created"]),
            let model = nonemptyChatString(chunk["model"])
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        if let metadata {
            // `created` moves with SGLang's per-chunk clock; only ID and model identify the response.
            guard metadata.chatID == chatID,
                metadata.model == model
            else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            return (false, metadata)
        }
        let responseID = chatID.hasPrefix("resp_") ? chatID : "resp_\(chatID)"
        let metadata = ChatCompletionStreamMetadata(
            chatID: chatID,
            responseID: responseID,
            created: created,
            model: model
        )
        self.metadata = metadata
        return (true, metadata)
    }

    private mutating func consumeChoice(
        _ rawChoice: [String: Any],
        index: Int,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        guard choices.isEmpty || choices[index] != nil,
            let delta = rawChoice["delta"] as? [String: Any]
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        var state = choices[index] ?? ChatCompletionChoiceState(index: index)
        guard state.finishReason == nil else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        if let role = delta["role"], !(role is NSNull) {
            guard role as? String == "assistant" else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
        }

        var events: [ResponsesProviderStreamEvent] = []
        if let content = delta["content"], !(content is NSNull) {
            guard let fragment = content as? String else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            events += try consumeContent(fragment, state: &state, metadata: metadata)
        }
        if let toolCalls = delta["tool_calls"], !(toolCalls is NSNull) {
            guard let toolCalls = toolCalls as? [[String: Any]] else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            for toolCall in toolCalls {
                events += try consumeToolCall(toolCall, state: &state, metadata: metadata)
            }
        }

        let finishReason = try chatFinishReason(rawChoice["finish_reason"])
        if let finishReason {
            events += try completeChoice(
                &state,
                finishReason: finishReason,
                metadata: metadata
            )
        }
        choices[index] = state
        return events
    }

    private mutating func consumeContent(
        _ fragment: String,
        state: inout ChatCompletionChoiceState,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        if state.message == nil, state.toolOutputOffset != nil {
            guard fragment.isEmpty else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            return []
        }
        var events: [ResponsesProviderStreamEvent] = []
        let message: ChatCompletionMessageState
        if let existing = state.message {
            message = existing
        } else {
            let started = ChatCompletionMessageState(
                id: "msg_\(metadata.responseID)",
                outputIndex: 0,
                completedText: nil
            )
            state.message = started
            events += try chatMessageStartEvents(
                id: started.id,
                outputIndex: started.outputIndex
            )
            message = started
        }
        if !fragment.isEmpty {
            fragments.appendText(fragment, choiceIndex: state.index)
            events.append(
                .outputTextDelta(
                    outputIndex: message.outputIndex,
                    contentIndex: 0,
                    itemID: message.id,
                    delta: fragment
                )
            )
        }
        return events
    }

    private mutating func consumeToolCall(
        _ rawCall: [String: Any],
        state: inout ChatCompletionChoiceState,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        guard let toolIndex = nonnegativeChatIndex(rawCall["index"]) else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        if let type = rawCall["type"], type as? String != "function" {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let function = rawCall["function"] as? [String: Any]
        if rawCall["function"] != nil, function == nil {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }

        var events: [ResponsesProviderStreamEvent] = []
        let call: ChatCompletionToolCallState
        if let existing = state.toolCalls[toolIndex] {
            // Continuation nulls mean "unchanged", not "a different id".
            if let id = rawCall["id"] as? String, id != existing.callID {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            if let name = function?["name"] as? String, name != existing.name {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            call = existing
        } else {
            guard let callID = nonemptyChatString(rawCall["id"]),
                let name = nonemptyChatString(function?["name"])
            else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            let toolOutputOffset = state.toolOutputOffset ?? (state.message == nil ? 0 : 1)
            let outputIndex = toolOutputOffset.addingReportingOverflow(toolIndex)
            guard !outputIndex.overflow else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            state.toolOutputOffset = toolOutputOffset
            call = ChatCompletionToolCallState(
                itemID: "fc_\(metadata.responseID)_\(toolIndex)",
                callID: callID,
                name: name,
                outputIndex: outputIndex.partialValue,
                completedArguments: ""
            )
            state.toolCalls[toolIndex] = call
            events.append(
                .outputItemAdded(
                    outputIndex: call.outputIndex,
                    itemJSON: try chatData(
                        chatFunctionItem(
                            itemID: call.itemID,
                            callID: call.callID,
                            name: call.name,
                            arguments: "",
                            status: "in_progress",
                            binding: prepared.toolBindings[name]
                        )
                    )
                )
            )
        }
        if let value = function?["arguments"] {
            guard let fragment = value as? String else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            if !fragment.isEmpty {
                fragments.appendArguments(
                    fragment,
                    choiceIndex: state.index,
                    toolIndex: toolIndex
                )
                events.append(
                    .functionArgumentsDelta(
                        outputIndex: call.outputIndex,
                        itemID: call.itemID,
                        callID: call.callID,
                        name: restoredToolName(call.name),
                        delta: fragment
                    )
                )
            }
        }
        return events
    }

    private func restoredToolName(_ wireName: String) -> String {
        prepared.toolBindings[wireName]?.name ?? wireName
    }
}

extension OpenAIChatCompletionsAccumulator {
    private mutating func completeChoice(
        _ state: inout ChatCompletionChoiceState,
        finishReason: String,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        switch finishReason {
        case "length", "sensitive", "stop":
            break
        case "tool_calls":
            guard !state.toolCalls.isEmpty else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
        case "model_context_window_exceeded":
            throw OpenAIResponsesChatCompletions.Error.contextLengthExceeded
        case "network_error":
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        default:
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        guard state.toolCalls.keys.sorted() == Array(0..<state.toolCalls.count) else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        var events: [ResponsesProviderStreamEvent] = []
        if state.message == nil, state.toolCalls.isEmpty {
            events += try consumeContent("", state: &state, metadata: metadata)
        }
        if var message = state.message {
            let text = fragments.finalizeText(choiceIndex: state.index)
            message.completedText = text
            state.message = message
            events += try chatMessageDoneEvents(
                id: message.id,
                outputIndex: message.outputIndex,
                text: text
            )
        }
        for (index, value) in state.toolCalls.sorted(by: { $0.key < $1.key }) {
            var call = value
            let arguments = fragments.finalizeArguments(
                choiceIndex: state.index,
                toolIndex: index
            )
            call.completedArguments = arguments
            state.toolCalls[index] = call
            events.append(
                .functionArgumentsDone(
                    outputIndex: call.outputIndex,
                    itemID: call.itemID,
                    callID: call.callID,
                    name: restoredToolName(call.name),
                    arguments: arguments
                )
            )
            events.append(
                .outputItemDone(
                    outputIndex: call.outputIndex,
                    itemJSON: try chatData(
                        chatFunctionItem(
                            itemID: call.itemID,
                            callID: call.callID,
                            name: call.name,
                            arguments: arguments,
                            status: "completed",
                            binding: prepared.toolBindings[call.name]
                        )
                    )
                )
            )
        }
        state.finishReason = finishReason
        return events
    }

    private mutating func consumeUsage(_ value: Any?) throws {
        guard let value, !(value is NSNull) else {
            return
        }
        guard !choices.isEmpty,
            choices.values.allSatisfy({ $0.finishReason != nil }),
            let object = value as? [String: Any],
            object["prompt_tokens"] != nil,
            object["completion_tokens"] != nil
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let parsed = try OpenAIResponsesChatCompletions.responsesUsage(object)
        usage = ChatCompletionUsage(
            promptTokens: parsed.inputTokens,
            cachedPromptTokens: parsed.cachedInputTokens,
            cacheWritePromptTokens: parsed.cacheWriteInputTokens,
            completionTokens: parsed.outputTokens,
            reasoningCompletionTokens: parsed.reasoningOutputTokens,
            totalTokens: parsed.totalTokens
        )
    }

    private mutating func completeStream() throws -> [ResponsesProviderStreamEvent] {
        guard let metadata,
            choices.count == 1,
            let state = choices.values.first
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        guard let finishReason = state.finishReason else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let sortedToolCalls = state.toolCalls.sorted { $0.key < $1.key }
        let completedChoices = [
            CompletedChatCompletionChoice(
                index: state.index,
                finishReason: finishReason,
                messageText: state.message?.completedText,
                toolCalls: sortedToolCalls.map(\.value)
            )
        ]
        guard let usage else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let turn = try ChatCompletionStreamProjection.project(
            metadata: metadata,
            usage: usage,
            choices: completedChoices,
            prepared: prepared
        )
        let status: ResponsesStreamTerminal =
            completedChoices.contains {
                ["length", "sensitive"].contains($0.finishReason)
            } ? .incomplete : .completed
        completedTurn = turn
        phase = .terminal
        return [.terminal(status: status, responseJSON: turn.rootJSON)]
    }

}

extension OpenAIChatCompletionsAccumulator {
    private mutating func charge(_ count: Int) throws {
        guard consumedBytes <= maximumTurnBytes,
            count <= maximumTurnBytes - consumedBytes
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        consumedBytes += count
    }
}
