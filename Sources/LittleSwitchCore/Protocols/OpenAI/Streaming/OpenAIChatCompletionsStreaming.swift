import Foundation
import LittleSwitchTransport
import LittleSwitchWire

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
        let chunk: OpenAIChatChunk
        do {
            chunk = try WireCodec.decode(OpenAIChatChunk.self, from: frame.data).value
        } catch {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let metadataResult = try consumeMetadata(chunk)

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
        for rawChoice in chunk.choices {
            let index = try chatWireIndex(rawChoice.index)
            guard frameChoiceIndices.insert(index).inserted
            else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
            events += try consumeChoice(
                rawChoice,
                index: index,
                metadata: metadataResult.metadata
            )
        }
        try consumeUsage(chunk.usage.value)
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
        _ chunk: OpenAIChatChunk
    ) throws -> (
        started: Bool,
        metadata: ChatCompletionStreamMetadata
    ) {
        guard !chunk.id.isEmpty, !chunk.model.isEmpty
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let chatID = chunk.id
        let model = chunk.model
        let created = try chatWireIndex(chunk.created)
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
        _ rawChoice: OpenAIChatChoice,
        index: Int,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        guard choices.isEmpty || choices[index] != nil
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let delta = rawChoice.delta
        var state = choices[index] ?? ChatCompletionChoiceState(index: index)
        guard state.finishReason == nil else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        if let role = delta.role.value {
            guard role == .assistant else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
        }

        var events: [ResponsesProviderStreamEvent] = []
        let reasoning = try ResponsesChatCompletionsReasoning.wireFields(in: delta.additionalFields)
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
        if let fragment = delta.content.value {
            if !fragment.isEmpty {
                events += try consumeContent(
                    fragment,
                    state: &state,
                    metadata: metadata)
            }
        }
        if let refusal = delta.refusal.value {
            events += try consumeRefusal(
                refusal,
                state: &state,
                metadata: metadata)
        }
        if let toolCalls = delta.toolCalls.value {
            for toolCall in toolCalls {
                events += try consumeToolCall(
                    toolCall,
                    state: &state,
                    metadata: metadata)
            }
        }

        if let finishReason = rawChoice.finishReason.value {
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
                        partJSON: try WireCodec.encode(
                            OpenAIResponsesOutputText(
                                annotations: .value([]), logprobs: .value([]), text: "", type: .outputText))))
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
                    itemJSON: try WireCodec.encode(
                        OpenAIResponsesMessage(
                            content: [],
                            id: "msg_\(metadata.responseID)",
                            role: .assistant,
                            status: .value(.inProgress),
                            type: .message))))
        }
        let refusalIndex = message.refusalIndex ?? (message.textStarted ? 1 : 0)
        if message.refusalIndex == nil {
            message.refusalIndex = refusalIndex
            events.append(
                .contentPartAdded(
                    outputIndex: message.outputIndex,
                    contentIndex: refusalIndex,
                    itemID: message.id,
                    partJSON: try WireCodec.encode(OpenAIResponsesRefusal(refusal: "", type: .refusal))))
        }
        message.refusal.append(fragment)
        events.append(
            .passthrough(
                type: OpenAIResponsesRefusalDeltaEventType.responseRefusalDelta.rawValue,
                payloadJSON: try WireCodec.encode(
                    OpenAIResponsesRefusalDeltaEvent(
                        contentIndex: JSONNumber(refusalIndex),
                        delta: fragment,
                        itemId: message.id,
                        outputIndex: JSONNumber(message.outputIndex),
                        type: .responseRefusalDelta))))
        state.message = message
        return events
    }

    private mutating func consumeToolCall(
        _ rawCall: OpenAIChatToolDelta,
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
        finishReason: OpenAIChatFinishReason,
        metadata: ChatCompletionStreamMetadata
    ) throws -> [ResponsesProviderStreamEvent] {
        switch finishReason {
        case .length, .sensitive, .contentFilter, .stop:
            break
        case .toolCalls:
            guard !state.toolCalls.isEmpty else {
                throw OpenAIResponsesChatCompletions.Error.invalidResponse
            }
        case .modelContextWindowExceeded:
            throw OpenAIResponsesChatCompletions.Error.contextLengthExceeded
        case .networkError, .functionCall:
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

    private mutating func consumeUsage(_ value: OpenAIChatStreamUsage?) throws {
        guard let value else {
            return
        }
        guard !choices.isEmpty,
            choices.values.allSatisfy({ $0.finishReason != nil })
        else {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
        let parsed = try chatWireUsage(value)
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
                [.length, .sensitive, .contentFilter].contains($0.finishReason)
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
