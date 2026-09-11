import Foundation

/// Builds the buffered projection of a completed streamed chat turn.
enum ChatCompletionStreamProjection {
    static func project(
        metadata: ChatCompletionStreamMetadata,
        usage: ChatCompletionUsage,
        choices: [CompletedChatCompletionChoice],
        prepared: PreparedResponsesChatCompletionsRequest
    ) throws -> ResponsesModelTurn {
        let chatChoices = choices.map { choice -> [String: Any] in
            var message: [String: Any] = [
                "role": "assistant",
                "content": choice.messageText ?? NSNull(),
            ]
            for (key, value) in choice.reasoning { message[key] = value }
            if let refusal = choice.refusal { message["refusal"] = refusal }
            if !choice.toolCalls.isEmpty {
                let toolCalls: [[String: Any]] = choice.toolCalls.map { call in
                    var input: [String: Any] = ["name": call.name, call.kind.inputKey: call.completedArguments]
                    if let namespace = call.namespace { input["namespace"] = namespace }
                    return [
                        "id": call.callID,
                        "type": call.kind.rawValue,
                        call.kind.rawValue: input,
                    ] as [String: Any]
                }
                message["tool_calls"] = toolCalls
            }
            return [
                "index": choice.index,
                "finish_reason": choice.finishReason,
                "message": message,
            ]
        }
        let chat: [String: Any] = [
            "id": metadata.chatID,
            "object": "chat.completion",
            "created": metadata.created,
            "model": metadata.model,
            "choices": chatChoices,
            "usage": [
                "prompt_tokens": usage.promptTokens,
                "prompt_tokens_details": [
                    "cached_tokens": usage.cachedPromptTokens,
                    "cache_write_tokens": usage.cacheWritePromptTokens,
                ],
                "completion_tokens": usage.completionTokens,
                "completion_tokens_details": [
                    "reasoning_tokens": usage.reasoningCompletionTokens
                ],
                "total_tokens": usage.totalTokens,
            ],
        ]
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
                responseBody: chatData(chat),
                prepared: buffered
            )
            return try OpenAIResponsesWebSearch.parseModelTurn(response)
        } catch {
            throw OpenAIResponsesChatCompletions.Error.invalidResponse
        }
    }
}
