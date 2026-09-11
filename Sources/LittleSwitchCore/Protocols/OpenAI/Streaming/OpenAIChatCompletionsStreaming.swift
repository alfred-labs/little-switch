import Foundation
import LittleSwitchTransport

package struct OpenAIChatCompletionsAccumulator: Sendable {
    private static let defaultMaximumTurnBytes = 8 * 1_024 * 1_024

    private let prepared: PreparedResponsesChatCompletionsRequest
    private let maximumTurnBytes: Int
    private let resolver: ProviderToolNamespaceResolver
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
        self.resolver = ProviderToolNamespaceResolver(
            declaredBindings: prepared.declaredToolBindings,
            nameCatalog: prepared.toolNameCatalog
        )
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
    ) throws -> (
        started: Bool,
        metadata: ChatCompletionStreamMetadata
    ) {
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
        let reasoning = try ResponsesChatCompletionsReasoning.fields(in: delta)
        if !reasoning.isEmpty {
            if state.reasoningIndex == nil {
                guard state.message == nil, state.toolOutputOffset == nil else {
                    throw OpenAIResponsesChatCompletions.Error.invalidResponse
                }
                state.reasoningIndex = 0
                let item = try ResponsesChatCompletionsReasoning.item(
                    message: reasoning,
                    responseID: metadata.responseID,
                    providerID: prepared.providerID)
                if let item {
                    events.append(
                        .outputItemAdded(
                            outputIndex: 0,
                            itemJSON: try chatData(item)))
                }
            }
            for (key, value) in reasoning {
                state.reasoning[key, default: []].append(value)
            }
        }
        if let content = delta["content"], !(content is NSNull) {
            guard let fragment = content as? String else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            if !fragment.isEmpty {
                events += try consumeContent(
                    fragment,
                    state: &state,
                    metadata: metadata)
            }
        }
        if let refusal = delta["refusal"], !(refusal is NSNull) {
            guard let refusal = refusal as? String else { throw OpenAIResponsesChatCompletions.Error.invalidResponse }
            events += try consumeRefusal(
                refusal,
                state: &state,
                metadata: metadata)
        }
        if let toolCalls = delta["tool_calls"], !(toolCalls is NSNull) {
            guard let toolCalls = toolCalls as? [[String: Any]] else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            for toolCall in toolCalls {
                events += try consumeToolCall(
                    toolCall,
                    state: &state,
                    metadata: metadata)
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
        guard state.message != nil || state.toolOutputOffset == nil else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        var events: [ResponsesProviderStreamEvent] = []
        var message: ChatCompletionMessageState
        if let existing = state.message {
            message = existing
            if !message.textStarted {
                // Only a refusal can start the message before its text.
                message.textIndex = 1
                events.append(
                    .contentPartAdded(
                        outputIndex: message.outputIndex,
                        contentIndex: message.textIndex,
                        itemID: message.id,
                        partJSON: try chatData(["type": "output_text", "text": "", "annotations": [], "logprobs": []])))
            }
        } else {
            let started = ChatCompletionMessageState(
                id: "msg_\(metadata.responseID)",
                outputIndex: state.leadingOutputCount,
                completedText: nil
            )
            events += try chatMessageStartEvents(
                id: started.id,
                outputIndex: started.outputIndex
            )
            message = started
        }
        message.textStarted = true
        state.message = message
        if !fragment.isEmpty {
            fragments.appendText(
                fragment,
                choiceIndex: state.index)
            events.append(
                .outputTextDelta(
                    outputIndex: message.outputIndex,
                    contentIndex: message.textIndex,
                    itemID: message.id,
                    delta: fragment
                )
            )
        }
        return events
    }

    private func consumeRefusal(
        _ fragment: String,
        state: inout ChatCompletionChoiceState,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        var events: [ResponsesProviderStreamEvent] = []
        var message: ChatCompletionMessageState
        if let existing = state.message {
            message = existing
        } else {
            guard state.toolOutputOffset == nil else { throw OpenAIResponsesChatCompletions.Error.invalidResponse }
            message = ChatCompletionMessageState(
                id: "msg_\(metadata.responseID)",
                outputIndex: state.leadingOutputCount,
                completedText: nil)
            events.append(
                .outputItemAdded(
                    outputIndex: state.leadingOutputCount,
                    itemJSON: try chatData([
                        "id": "msg_\(metadata.responseID)", "type": "message", "status": "in_progress",
                        "role": "assistant", "content": [],
                    ])))
        }
        let refusalIndex = message.refusalIndex ?? (message.textStarted ? 1 : 0)
        if message.refusalIndex == nil {
            message.refusalIndex = refusalIndex
            events.append(
                .contentPartAdded(
                    outputIndex: message.outputIndex,
                    contentIndex: refusalIndex,
                    itemID: message.id,
                    partJSON: try chatData(["type": "refusal", "refusal": ""])))
        }
        message.refusal.append(fragment)
        events.append(
            .passthrough(
                type: "response.refusal.delta",
                payloadJSON: try chatData([
                    "type": "response.refusal.delta", "output_index": message.outputIndex,
                    "content_index": refusalIndex, "item_id": message.id, "delta": fragment,
                ])))
        state.message = message
        return events
    }

    private mutating func consumeToolCall(
        _ rawCall: [String: Any],
        state: inout ChatCompletionChoiceState,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        try ChatCompletionToolStream(
            prepared: prepared,
            resolver: resolver,
            metadata: metadata
        )
        .consume(
            rawCall,
            state: &state,
            fragments: &fragments)
    }
}

extension OpenAIChatCompletionsAccumulator {
    private mutating func completeChoice(
        _ state: inout ChatCompletionChoiceState,
        finishReason: String,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        switch finishReason {
        case "length", "sensitive", "content_filter", "stop":
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
        if let index = state.reasoningIndex {
            let item = try ResponsesChatCompletionsReasoning.item(
                message: state.reasoning.mapValues { $0.joined() },
                responseID: metadata.responseID,
                providerID: prepared.providerID)
            if let item {
                events.append(
                    .outputItemDone(
                        outputIndex: index,
                        itemJSON: try chatData(item)))
            }
        }
        if state.message == nil, state.toolCalls.isEmpty, state.reasoning.isEmpty {
            events += try consumeContent(
                "",
                state: &state,
                metadata: metadata)
        }
        if var message = state.message {
            let text = fragments.finalizeText(choiceIndex: state.index)
            message.completedText = message.textStarted ? text : nil
            state.message = message
            events += try chatMessageDoneEvents(message)
        }
        events += try ChatCompletionToolStream(
            prepared: prepared,
            resolver: resolver,
            metadata: metadata
        )
        .complete(
            &state,
            fragments: &fragments)
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
                toolCalls: sortedToolCalls.map(\.value),
                reasoning: state.reasoning.mapValues { $0.joined() },
                refusal: state.message.flatMap { $0.refusalIndex == nil ? nil : $0.refusal.joined() }
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
                ["length", "sensitive", "content_filter"].contains($0.finishReason)
            } ? .incomplete : .completed
        completedTurn = turn
        phase = .terminal
        return [
            .terminal(
                status: status,
                responseJSON: turn.rootJSON)
        ]
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
