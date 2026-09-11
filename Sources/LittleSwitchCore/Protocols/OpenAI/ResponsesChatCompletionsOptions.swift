import Foundation

/// Options shared by the two APIs keep their values; only their wire shape changes.
enum ResponsesChatCompletionsOptions {
    static func copy(from source: [String: Any], to request: inout [String: Any]) throws {
        for key in [
            "parallel_tool_calls", "temperature", "top_p", "store", "metadata", "user",
            "service_tier", "safety_identifier", "prompt_cache_key", "prompt_cache_retention", "prompt_cache_options",
        ] {
            request[key] = source[key]
        }
        request["max_tokens"] = source["max_output_tokens"]
        if let reasoning = source["reasoning"] as? [String: Any] {
            request["reasoning_effort"] = reasoning["effort"]
        }
        if let text = source["text"] as? [String: Any] {
            request["verbosity"] = text["verbosity"]
            if let format = text["format"] { request["response_format"] = try responseFormat(format) }
        }
    }

    private static func responseFormat(_ value: Any) throws -> [String: Any] {
        guard var format = value as? [String: Any], let type = format["type"] as? String else {
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
        switch type {
        case "text", "json_object":
            return format
        case "json_schema":
            guard nonemptyResponsesString(format["name"]) != nil, format["schema"] is [String: Any] else {
                throw OpenAIResponsesChatCompletions.Error.invalidRequest
            }
            format.removeValue(forKey: "type")
            return ["type": type, "json_schema": format]
        default:
            throw OpenAIResponsesChatCompletions.Error.invalidRequest
        }
    }
}
