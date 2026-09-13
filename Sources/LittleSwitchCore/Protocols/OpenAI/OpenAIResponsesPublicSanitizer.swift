import Foundation
import LittleSwitchWire

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

    // Legacy dictionary builders call these bounded public-value adapters.
    // Native provider Data is decoded by Wire before this sanitation boundary.
    static func item(_ item: [String: Any]) throws -> [String: Any] {
        try legacyPublicObject(wireItem(JSONValue.parse(responsesStreamData(item))))
    }

    static func contentPart(_ value: Any?) throws -> [String: Any] {
        guard let value else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        return try legacyPublicObject(wireContentPart(JSONValue.parse(responsesStreamData(value))))
    }

    static func summaryPart(_ value: Any?) throws -> [String: Any] {
        guard let value else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        var part = try responsesWireDecode(OpenAIResponsesSummaryPart.self, from: responsesStreamData(value))
        part.additionalFields = [:]
        return try legacyPublicObject(part.wireJSON())
    }

    static func annotation(_ value: Any?) throws -> [String: Any] {
        guard let value else { throw OpenAIResponsesWebSearch.Error.invalidResponse }
        let annotation = try responsesWireDecode(OpenAITextAnnotation.self, from: responsesStreamData(value))
        return try legacyPublicObject(wireAnnotation(annotation).wireJSON())
    }

    private static func legacyPublicObject(_ json: JSONValue) throws -> [String: Any] {
        try responsesStreamObject(json.serializedData())
    }
}

extension OpenAIResponsesPublicSanitizer {
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
