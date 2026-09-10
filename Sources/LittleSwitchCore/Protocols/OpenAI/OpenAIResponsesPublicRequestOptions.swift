import Foundation

extension OpenAIResponsesPublicSanitizer {
    static func clientResponseFields(
        originalBody: Data,
        originalModel: String
    ) throws -> [String: Any] {
        let request = try publicResponseObject(originalBody)
        guard request["model"] as? String == originalModel else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var fields = request.filter { publicResponseOptionKeys.contains($0.key) }
        fields["model"] = originalModel
        fields["tools"] = request["tools"] ?? []
        return fields
    }
}

private let publicResponseOptionKeys: Set<String> = [
    "background",
    "conversation",
    "instructions",
    "max_output_tokens",
    "max_tool_calls",
    "metadata",
    "parallel_tool_calls",
    "previous_response_id",
    "prompt",
    "prompt_cache_key",
    "reasoning",
    "safety_identifier",
    "service_tier",
    "store",
    "temperature",
    "text",
    "tool_choice",
    "top_logprobs",
    "top_p",
    "truncation",
    "user",
]
