import Foundation

enum OpenAIResponsesPublicSanitizer {
    static func responseShell(
        provider: [String: Any],
        identity: [String: Any]? = nil
    ) throws -> [String: Any] {
        let identity = identity ?? provider
        guard let id = nonemptyResponsesString(identity["id"]) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if let object = identity["object"] as? String, object != "response" {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }

        var response: [String: Any] = [
            "id": id,
            "object": "response",
        ]
        if let createdAtValue = identity["created_at"] {
            guard let createdAt = nonnegativeResponsesIndex(createdAtValue) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            response["created_at"] = createdAt
        }
        if let completedAt = try publicNullableIndex(provider["completed_at"]) {
            response["completed_at"] = completedAt
        }
        if let incompleteDetails = try publicIncompleteDetails(provider["incomplete_details"]) {
            response["incomplete_details"] = incompleteDetails
        }
        return response
    }

    static func providerTransportResponse(_ provider: [String: Any]) throws -> [String: Any] {
        guard let status = provider["status"] as? String,
            let terminal = ResponsesStreamTerminal(rawValue: status)
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var response = try responseShell(provider: provider)
        response["status"] = terminal.rawValue
        response["output"] = try output(provider["output"] ?? [])
        if terminal == .failed {
            let code = (provider["error"] as? [String: Any])?["code"] as? String
            response["error"] = [
                "code": code == "context_length_exceeded"
                    ? "context_length_exceeded" : "server_error",
                "message": "Internal server error",
            ]
            response["usage"] = NSNull()
        } else {
            response["usage"] = try providerUsage(provider["usage"])
        }
        return response
    }

    static func output(_ value: Any) throws -> [[String: Any]] {
        guard let items = value as? [[String: Any]] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return try items.map(item)
    }

    static func item(_ item: [String: Any]) throws -> [String: Any] {
        guard let type = nonemptyResponsesString(item["type"]) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        switch type {
        case "message":
            return try message(item)
        case "reasoning":
            return try reasoning(item)
        case "function_call", "custom_tool_call":
            return try functionCall(item)
        case "web_search_call":
            return try webSearchCall(item)
        case "tool_search_call":
            return try clientToolSearchCall(item)
        default:
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
    }

    static func contentPart(_ value: Any?) throws -> [String: Any] {
        guard let part = value as? [String: Any],
            let type = nonemptyResponsesString(part["type"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        switch type {
        case "output_text":
            guard let text = part["text"] as? String else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            return [
                "type": type,
                "text": text,
                "annotations": try annotations(part["annotations"]),
                "logprobs": try logprobs(part["logprobs"]),
            ]
        case "refusal":
            guard let refusal = part["refusal"] as? String else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            return ["type": type, "refusal": refusal]
        default:
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
    }

    static func summaryPart(_ value: Any?) throws -> [String: Any] {
        guard let part = value as? [String: Any],
            part["type"] as? String == "summary_text",
            let text = part["text"] as? String
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return ["type": "summary_text", "text": text]
    }

    static func annotation(_ value: Any?) throws -> [String: Any] {
        guard let annotation = value as? [String: Any],
            let type = nonemptyResponsesString(annotation["type"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let stringKeys: Set<String>
        let indexKeys: Set<String>
        switch type {
        case "url_citation":
            stringKeys = ["title", "url"]
            indexKeys = ["start_index", "end_index"]
        case "file_citation":
            stringKeys = ["file_id", "filename"]
            indexKeys = ["index"]
        case "container_file_citation":
            stringKeys = ["container_id", "file_id", "filename"]
            indexKeys = ["start_index", "end_index"]
        case "file_path":
            stringKeys = ["file_id"]
            indexKeys = ["index"]
        default:
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }

        var result: [String: Any] = ["type": type]
        for key in stringKeys where annotation[key] != nil {
            guard let value = annotation[key] as? String else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result[key] = value
        }
        for key in indexKeys where annotation[key] != nil {
            guard let index = nonnegativeResponsesIndex(annotation[key]) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result[key] = index
        }
        return result
    }
}

extension OpenAIResponsesPublicSanitizer {
    private static func message(_ item: [String: Any]) throws -> [String: Any] {
        guard let id = nonemptyResponsesString(item["id"]),
            item["role"] as? String == "assistant",
            let content = item["content"] as? [[String: Any]]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var result: [String: Any] = [
            "id": id,
            "type": "message",
            "role": "assistant",
            "content": try content.map(contentPart),
        ]
        try copyStatus(from: item, to: &result)
        if let phase = item["phase"], !(phase is NSNull) {
            guard let phase = phase as? String,
                ["commentary", "final_answer"].contains(phase)
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result["phase"] = phase
        }
        try copyInternalMetadata(from: item, to: &result)
        return result
    }

    private static func reasoning(_ item: [String: Any]) throws -> [String: Any] {
        guard let id = nonemptyResponsesString(item["id"]) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let summary = try reasoningParts(
            item["summary"],
            allowedTypes: ["summary_text"]
        )
        var result: [String: Any] = [
            "id": id,
            "type": "reasoning",
            "summary": summary,
        ]
        // vLLM stamps reasoning items with an explicit "content": null; a
        // null reads as absent, like everywhere else in the sanitizer.
        if let contentValue = item["content"], !(contentValue is NSNull) {
            result["content"] = try reasoningParts(
                contentValue,
                allowedTypes: ["reasoning_text", "text"]
            )
        }
        if let encryptedContent = item["encrypted_content"] {
            guard encryptedContent is NSNull || encryptedContent is String else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result["encrypted_content"] = encryptedContent
        }
        try copyStatus(from: item, to: &result)
        try copyInternalMetadata(from: item, to: &result)
        return result
    }

    private static func webSearchCall(_ item: [String: Any]) throws -> [String: Any] {
        guard let id = nonemptyResponsesString(item["id"]) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var result: [String: Any] = [
            "id": id,
            "type": "web_search_call",
        ]
        try copyStatus(from: item, to: &result)
        if let action = item["action"] {
            result["action"] = try webSearchAction(action)
        }
        try copyInternalMetadata(from: item, to: &result)
        return result
    }

    private static func reasoningParts(
        _ value: Any?,
        allowedTypes: Set<String>
    ) throws -> [[String: Any]] {
        guard let value else {
            return []
        }
        guard let parts = value as? [[String: Any]] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return try parts.compactMap { part in
            guard let type = nonemptyResponsesString(part["type"]),
                allowedTypes.contains(type)
            else {
                return nil
            }
            guard let text = part["text"] as? String else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            return ["type": type, "text": text]
        }
    }

    private static func webSearchAction(_ value: Any) throws -> [String: Any] {
        guard let action = value as? [String: Any],
            let type = nonemptyResponsesString(action["type"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var result: [String: Any] = ["type": type]
        switch type {
        case "search":
            if let query = action["query"] {
                guard query is String else {
                    throw OpenAIResponsesWebSearch.Error.invalidResponse
                }
                result["query"] = query
            }
            if let queries = action["queries"] {
                guard queries is [String] else {
                    throw OpenAIResponsesWebSearch.Error.invalidResponse
                }
                result["queries"] = queries
            }
            if let sources = action["sources"] {
                result["sources"] = try webSearchSources(sources)
            }
        case "open_page":
            if let url = action["url"] {
                guard url is String else {
                    throw OpenAIResponsesWebSearch.Error.invalidResponse
                }
                result["url"] = url
            }
        case "find_in_page":
            for key in ["url", "pattern"] where action[key] != nil {
                guard action[key] is String else {
                    throw OpenAIResponsesWebSearch.Error.invalidResponse
                }
                result[key] = action[key]
            }
        default:
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return result
    }
}

extension OpenAIResponsesPublicSanitizer {
    private static func annotations(_ value: Any?) throws -> [[String: Any]] {
        guard let value, !(value is NSNull) else {
            return []
        }
        guard let annotations = value as? [[String: Any]] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return try annotations.map(annotation)
    }

    private static func logprobs(_ value: Any?) throws -> [[String: Any]] {
        guard let value, !(value is NSNull) else {
            return []
        }
        guard let entries = value as? [[String: Any]] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return try entries.map { try logprob($0, allowTopLogprobs: true) }
    }

    private static func logprob(
        _ entry: [String: Any],
        allowTopLogprobs: Bool
    ) throws -> [String: Any] {
        guard let token = entry["token"] as? String,
            let score = publicNumber(entry["logprob"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var result: [String: Any] = [
            "token": token,
            "logprob": score,
        ]
        if let bytes = entry["bytes"] {
            guard
                bytes is NSNull
                    || (bytes as? [Int])?.allSatisfy({ (0...255).contains($0) }) == true
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result["bytes"] = bytes
        }
        if allowTopLogprobs, let top = entry["top_logprobs"] {
            guard let top = top as? [[String: Any]] else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result["top_logprobs"] = try top.map {
                try logprob($0, allowTopLogprobs: false)
            }
        }
        return result
    }

    private static func publicNumber(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        return number
    }

    static func copyStatus(
        from source: [String: Any],
        to result: inout [String: Any]
    ) throws {
        guard let value = source["status"], !(value is NSNull) else {
            return
        }
        guard let status = value as? String,
            ["queued", "in_progress", "searching", "completed", "incomplete", "failed"]
                .contains(status)
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        result["status"] = status
    }

    static func copyInternalMetadata(
        from source: [String: Any],
        to result: inout [String: Any]
    ) throws {
        guard let value = source["internal_chat_message_metadata_passthrough"] else {
            return
        }
        guard let metadata = value as? [String: Any] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if let turnID = metadata["turn_id"] {
            guard turnID is String else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result["internal_chat_message_metadata_passthrough"] = ["turn_id": turnID]
        }
    }

    private static func publicNullableIndex(_ value: Any?) throws -> Any? {
        guard let value else {
            return nil
        }
        if value is NSNull {
            return NSNull()
        }
        guard let index = nonnegativeResponsesIndex(value) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return index
    }

    private static func publicIncompleteDetails(_ value: Any?) throws -> Any? {
        guard let value else {
            return nil
        }
        if value is NSNull {
            return NSNull()
        }
        guard let details = value as? [String: Any] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        guard let reason = details["reason"] as? String,
            ["content_filter", "max_output_tokens"].contains(reason)
        else {
            return NSNull()
        }
        return ["reason": reason]
    }

    private static func providerUsage(_ value: Any?) throws -> [String: Any] {
        guard let usage = value as? [String: Any] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var result: [String: Any] = [:]
        for key in ["input_tokens", "output_tokens", "total_tokens"] where usage[key] != nil {
            guard let count = nonnegativeResponsesIndex(usage[key]) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            result[key] = count
        }
        let detailKeys: [(String, Set<String>)] = [
            ("input_tokens_details", ["cached_tokens", "cache_write_tokens"]),
            ("output_tokens_details", ["reasoning_tokens"]),
        ]
        for (key, allowedKeys) in detailKeys where usage[key] != nil {
            if usage[key] is NSNull {
                result[key] = NSNull()
                continue
            }
            guard let details = usage[key] as? [String: Any] else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            var publicDetails: [String: Any] = [:]
            for detailKey in allowedKeys where details[detailKey] != nil {
                guard let count = nonnegativeResponsesIndex(details[detailKey]) else {
                    throw OpenAIResponsesWebSearch.Error.invalidResponse
                }
                publicDetails[detailKey] = count
            }
            result[key] = publicDetails
        }
        return result
    }
}
