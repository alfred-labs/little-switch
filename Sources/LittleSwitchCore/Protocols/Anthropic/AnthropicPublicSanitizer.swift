import Foundation

enum AnthropicPublicSanitizer {
    static func block(_ value: Any) throws -> [String: Any]? {
        guard let source = value as? [String: Any],
            let type = source["type"] as? String,
            !type.isEmpty
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        switch type {
        case "text":
            return try textBlock(source)
        case "thinking":
            return try thinkingBlock(source)
        case "redacted_thinking":
            guard let data = source["data"] as? String else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            return ["type": type, "data": data]
        case "tool_use", "server_tool_use":
            return try toolBlock(source, type: type)
        case "web_search_tool_result":
            return try webSearchResultBlock(source)
        default:
            return nil
        }
    }

    static func delta(_ value: Any) throws -> [String: Any]? {
        guard let source = value as? [String: Any],
            let type = source["type"] as? String,
            !type.isEmpty
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        let key: String
        switch type {
        case "text_delta":
            key = "text"
        case "thinking_delta":
            key = "thinking"
        case "signature_delta":
            key = "signature"
        case "input_json_delta":
            key = "partial_json"
        case "citations_delta":
            guard let citationValue = source["citation"],
                let citation = try citation(citationValue)
            else {
                return nil
            }
            return ["type": type, "citation": citation]
        default:
            return nil
        }
        guard let fragment = source[key] as? String else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        return ["type": type, key: fragment]
    }
}

extension AnthropicPublicSanitizer {
    private static func textBlock(_ source: [String: Any]) throws -> [String: Any] {
        guard let text = source["text"] as? String else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        var result: [String: Any] = ["type": "text", "text": text]
        if let citations = source["citations"] {
            if citations is NSNull {
                result["citations"] = NSNull()
            } else {
                guard let citations = citations as? [Any] else {
                    throw AnthropicWebSearch.Error.invalidMessage
                }
                result["citations"] = try citations.compactMap(citation)
            }
        }
        return result
    }

    private static func thinkingBlock(_ source: [String: Any]) throws -> [String: Any] {
        guard let thinking = source["thinking"] as? String else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        var result: [String: Any] = ["type": "thinking", "thinking": thinking]
        if let signature = source["signature"] {
            guard let signature = signature as? String else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            result["signature"] = signature
        }
        return result
    }

    private static func toolBlock(
        _ source: [String: Any],
        type: String
    ) throws -> [String: Any] {
        guard let id = nonemptyString(source["id"]),
            let name = nonemptyString(source["name"]),
            let input = source["input"] as? [String: Any],
            JSONSerialization.isValidJSONObject(input)
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        var result: [String: Any] = [
            "type": type,
            "id": id,
            "name": name,
            "input": input,
        ]
        if let caller = try caller(source["caller"]) {
            result["caller"] = caller
        }
        return result
    }

    private static func webSearchResultBlock(
        _ source: [String: Any]
    ) throws -> [String: Any] {
        guard let toolUseID = nonemptyString(source["tool_use_id"]),
            let content = source["content"]
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let publicContent: Any
        if let results = content as? [Any] {
            publicContent = try results.map(webSearchResult)
        } else if let error = content as? [String: Any] {
            publicContent = try webSearchError(error)
        } else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        var result: [String: Any] = [
            "type": "web_search_tool_result",
            "tool_use_id": toolUseID,
            "content": publicContent,
        ]
        if let caller = try caller(source["caller"]) {
            result["caller"] = caller
        }
        return result
    }

    private static func webSearchResult(_ value: Any) throws -> [String: Any] {
        guard let source = value as? [String: Any],
            source["type"] as? String == "web_search_result",
            let url = source["url"] as? String,
            let title = source["title"] as? String,
            let encryptedContent = source["encrypted_content"] as? String,
            let pageAge = source["page_age"],
            pageAge is String || pageAge is NSNull
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        return [
            "type": "web_search_result",
            "url": url,
            "title": title,
            "encrypted_content": encryptedContent,
            "page_age": pageAge,
        ]
    }

    private static func webSearchError(_ source: [String: Any]) throws -> [String: Any] {
        let codes: Set<String> = [
            "invalid_tool_input",
            "unavailable",
            "max_uses_exceeded",
            "too_many_requests",
            "query_too_long",
            "request_too_large",
        ]
        guard source["type"] as? String == "web_search_tool_result_error",
            let code = source["error_code"] as? String,
            codes.contains(code)
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        return [
            "type": "web_search_tool_result_error",
            "error_code": code,
        ]
    }
}

extension AnthropicPublicSanitizer {
    private static func caller(_ value: Any?) throws -> [String: Any]? {
        guard let value else {
            return nil
        }
        guard let source = value as? [String: Any],
            let type = source["type"] as? String
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        switch type {
        case "direct":
            return ["type": type]
        case "code_execution_20250825", "code_execution_20260120":
            guard let toolID = nonemptyString(source["tool_id"]) else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            return ["type": type, "tool_id": toolID]
        default:
            return nil
        }
    }

    private static func citation(_ value: Any) throws -> [String: Any]? {
        guard let source = value as? [String: Any],
            let type = source["type"] as? String
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        switch type {
        case "web_search_result_location":
            return try webCitation(source)
        case "char_location":
            return try documentCitation(
                source,
                type: type,
                indexKeys: ["start_char_index", "end_char_index"]
            )
        case "page_location":
            return try documentCitation(
                source,
                type: type,
                indexKeys: ["start_page_number", "end_page_number"]
            )
        case "content_block_location":
            return try documentCitation(
                source,
                type: type,
                indexKeys: ["start_block_index", "end_block_index"]
            )
        case "search_result_location":
            return try searchResultCitation(source)
        default:
            return nil
        }
    }

    private static func webCitation(_ source: [String: Any]) throws -> [String: Any] {
        guard let url = source["url"] as? String,
            let title = source["title"] as? String,
            let citedText = source["cited_text"] as? String,
            let encryptedIndex = source["encrypted_index"] as? String
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        return [
            "type": "web_search_result_location",
            "url": url,
            "title": title,
            "cited_text": citedText,
            "encrypted_index": encryptedIndex,
        ]
    }

    private static func documentCitation(
        _ source: [String: Any],
        type: String,
        indexKeys: [String]
    ) throws -> [String: Any] {
        guard let citedText = source["cited_text"] as? String,
            let documentIndex = nonnegativeIndex(source["document_index"])
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        var result: [String: Any] = [
            "type": type,
            "cited_text": citedText,
            "document_index": documentIndex,
        ]
        try copyNullableString("document_title", from: source, to: &result)
        try copyNullableString("file_id", from: source, to: &result)
        for key in indexKeys {
            guard let index = nonnegativeIndex(source[key]) else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            result[key] = index
        }
        return result
    }

    private static func searchResultCitation(
        _ source: [String: Any]
    ) throws -> [String: Any] {
        guard let citedText = source["cited_text"] as? String,
            let sourceText = source["source"] as? String,
            let resultIndex = nonnegativeIndex(source["search_result_index"]),
            let startIndex = nonnegativeIndex(source["start_block_index"]),
            let endIndex = nonnegativeIndex(source["end_block_index"])
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        var result: [String: Any] = [
            "type": "search_result_location",
            "cited_text": citedText,
            "source": sourceText,
            "search_result_index": resultIndex,
            "start_block_index": startIndex,
            "end_block_index": endIndex,
        ]
        try copyNullableString("title", from: source, to: &result)
        return result
    }

    private static func copyNullableString(
        _ key: String,
        from source: [String: Any],
        to result: inout [String: Any]
    ) throws {
        guard let value = source[key] else {
            return
        }
        guard value is String || value is NSNull else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        result[key] = value
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func nonnegativeIndex(_ value: Any?) -> Int? {
        guard let value = value as? Int, value >= 0 else {
            return nil
        }
        return value
    }
}
