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
            if !choice.toolCalls.isEmpty {
                let toolCalls: [[String: Any]] = choice.toolCalls.map { call in
                    [
                        "id": call.callID,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.completedArguments],
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
            streaming: false,
            toolBindings: prepared.toolBindings
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
