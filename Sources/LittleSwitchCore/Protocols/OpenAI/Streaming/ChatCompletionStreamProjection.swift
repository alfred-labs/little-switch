import Foundation
import LittleSwitchWire

/// Builds the buffered projection of a completed streamed chat turn.
enum ChatCompletionStreamProjection {
    static func project(
        metadata: ChatCompletionStreamMetadata,
        usage: ChatCompletionUsage,
        choices: [CompletedChatCompletionChoice],
        prepared: PreparedResponsesChatCompletionsRequest
    ) throws -> ResponsesModelTurn {
        let chat = try OpenAIChatCompletion(
            choices: choices.map { choice in
                try OpenAIChatCompletionChoice(
                    finishReason: OpenAIChatCompletionFinishReason(wireJSON: choice.finishReason.wireJSON()),
                    message: message(choice))
            },
            created: .value(JSONNumber(metadata.created)),
            id: .value(metadata.chatID),
            usage: .value(wireUsage(usage)))
        let buffered = PreparedResponsesChatCompletionsRequest(
            upstreamBody: prepared.upstreamBody,
            originalBody: prepared.originalBody,
            originalModel: prepared.originalModel,
            providerID: prepared.providerID,
            streaming: false,
            toolBindings: prepared.toolBindings,
            declaredToolBindings: prepared.declaredToolBindings,
            toolNameCatalog: prepared.toolNameCatalog,
            allowedToolIdentities: prepared.allowedToolIdentities
        )
        do {
            let response = try OpenAIResponsesChatCompletions.project(
                responseBody: WireCodec.encode(chat),
                prepared: buffered
            )
            return try OpenAIResponsesWebSearch.parseModelTurn(response)
        } catch {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
    }

    private static func message(_ choice: CompletedChatCompletionChoice) -> OpenAIChatMessage {
        OpenAIChatMessage(
            content: choice.messageText.map(JSONPresence.value) ?? .null,
            refusal: choice.refusal.map(JSONPresence.value) ?? .absent,
            toolCalls: choice.toolCalls.isEmpty ? .absent : .value(choice.toolCalls.map(toolCall)),
            additionalFields: choice.reasoning.mapValues(JSONValue.string))
    }

    private static func toolCall(_ call: ChatCompletionToolCallState) -> OpenAIChatMessageToolCall {
        let namespace = call.namespace.map(JSONPresence.value) ?? .absent
        switch call.kind {
        case .function:
            return .function(
                OpenAIChatFunctionCall(
                    function: OpenAIChatFunctionInput(
                        arguments: call.completedArguments, name: call.name, namespace: namespace),
                    id: call.callID,
                    type: .function))
        case .custom:
            return .custom(
                OpenAIChatCustomCall(
                    custom: OpenAIChatCustomInput(
                        input: call.completedArguments, name: call.name, namespace: namespace),
                    id: call.callID,
                    type: .custom))
        }
    }

    private static func wireUsage(_ usage: ChatCompletionUsage) -> OpenAIChatBufferedUsage {
        OpenAIChatBufferedUsage(
            completionTokens: JSONNumber(usage.completionTokens),
            completionTokensDetails: .value(
                OpenAIChatBufferedCompletionDetails(reasoningTokens: JSONNumber(usage.reasoningCompletionTokens))),
            promptTokens: JSONNumber(usage.promptTokens),
            promptTokensDetails: .value(
                OpenAIChatBufferedPromptDetails(
                    cacheWriteTokens: JSONNumber(usage.cacheWritePromptTokens),
                    cachedTokens: JSONNumber(usage.cachedPromptTokens))),
            totalTokens: .value(JSONNumber(usage.totalTokens)))
    }
}
