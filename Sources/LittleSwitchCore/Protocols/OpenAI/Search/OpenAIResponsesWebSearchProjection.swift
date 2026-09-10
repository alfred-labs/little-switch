import Foundation

package struct ResponsesWebSearchTrace: Equatable, Sendable {
    let id: String
    let callID: String
    let query: String
    let outputJSON: Data
    var sources: [String] = []
    var failed = false
}

struct ProjectedResponsesWebSearchResponse {
    let object: [String: Any]
    let output: [[String: Any]]
}

extension OpenAIResponsesWebSearch {
    static func nonStreamingResponse(
        prepared: PreparedResponsesWebSearchRequest,
        traces: [ResponsesWebSearchTrace],
        finalTurn: ResponsesModelTurn,
        usage: ResponsesUsage
    ) throws -> Data {
        let projection = try projectedResponse(
            prepared: prepared,
            traces: traces,
            finalTurn: finalTurn,
            usage: usage
        )
        return try projectionData(from: projection.object)
    }

    static func projectedResponse(
        prepared: PreparedResponsesWebSearchRequest,
        traces: [ResponsesWebSearchTrace],
        finalTurn: ResponsesModelTurn,
        usage: ResponsesUsage,
        responseMetadataJSON: Data? = nil,
        publicOutputJSON: Data? = nil,
        terminalStatus: ResponsesStreamTerminal? = nil
    ) throws -> ProjectedResponsesWebSearchResponse {
        let providerResponse = try projectionObject(from: finalTurn.rootJSON)
        let terminal = try terminalStatus ?? modelTerminalStatus(from: providerResponse)
        let identity: [String: Any]
        if let responseMetadataJSON {
            identity = try projectionObject(from: responseMetadataJSON)
        } else {
            identity = providerResponse
        }
        var response = try OpenAIResponsesPublicSanitizer.responseShell(
            provider: providerResponse,
            identity: identity
        )
        let output: [[String: Any]]
        if let publicOutputJSON {
            output = try publicOutput(
                from: publicOutputJSON,
                prepared: prepared
            )
        } else {
            var projected: [[String: Any]] = []
            for trace in traces {
                projected.append(contentsOf: try projectedOutput(for: trace, prepared: prepared))
            }
            projected.append(
                contentsOf: try publicOutput(
                    from: finalTurn.outputJSON,
                    prepared: prepared
                )
            )
            output = projected
        }

        let clientFields = try OpenAIResponsesPublicSanitizer.clientResponseFields(
            originalBody: prepared.originalBody,
            originalModel: prepared.originalModel
        )
        for (key, value) in clientFields {
            response[key] = value
        }
        let originalTools = try projectionFragment(from: prepared.originalToolsJSON)
        guard originalTools is [Any] else {
            throw Error.invalidResponse
        }
        response["tools"] = originalTools
        response["output"] = output
        response["status"] = terminal.rawValue
        if terminal == .failed {
            let code = (providerResponse["error"] as? [String: Any])?["code"] as? String
            response["error"] = [
                "code": code == "context_length_exceeded" ? "context_length_exceeded" : "server_error",
                "message": "Internal server error",
            ]
        }
        response["usage"] = responsesPublicUsage(usage)
        return ProjectedResponsesWebSearchResponse(object: response, output: output)
    }

    private static func projectedOutput(
        for trace: ResponsesWebSearchTrace,
        prepared: PreparedResponsesWebSearchRequest
    ) throws -> [[String: Any]] {
        let items = try projectionOutput(from: trace.outputJSON)
        var result: [[String: Any]] = []
        var replacedSearch = false
        for item in items {
            guard isPrivateSearchCall(item, privateToolName: prepared.privateToolName) else {
                result.append(try projectedPublicItem(item, prepared: prepared))
                continue
            }
            guard item["call_id"] as? String == trace.callID, !replacedSearch else {
                continue
            }
            result.append(try nativeSearchItem(for: trace))
            replacedSearch = true
        }
        guard replacedSearch else {
            throw Error.invalidResponse
        }
        return result
    }

    /// Buffered native turns carry flattened provider names; the pair Codex
    /// resolves against is restored here. Live and chat-adapted items may
    /// already carry their namespace and must retain that identity.
    private static func publicOutput(
        from data: Data,
        prepared: PreparedResponsesWebSearchRequest
    ) throws -> [[String: Any]] {
        try projectionOutput(from: data)
            .filter { !isPrivateSearchCall($0, privateToolName: prepared.privateToolName) }
            .map { try projectedPublicItem($0, prepared: prepared) }
    }

    private static func projectedPublicItem(
        _ item: [String: Any],
        prepared: PreparedResponsesWebSearchRequest
    ) throws -> [String: Any] {
        var restored = item
        if item["type"] as? String == "function_call", item["namespace"] as? String == nil {
            if let flatName = item["name"] as? String, let binding = prepared.toolBindings[flatName] {
                restored["name"] = binding.name
                restored["namespace"] = binding.namespace
            }
        }
        restored = try prepared.toolSearchContract?.projectItem(restored) ?? restored
        return try OpenAIResponsesPublicSanitizer.item(restored)
    }

    static func nativeSearchItem(
        id: String,
        query: String,
        sources: [String],
        failed: Bool
    ) throws -> [String: Any] {
        var action: [String: Any] = ["type": "search", "query": query]
        if !sources.isEmpty {
            action["sources"] = try OpenAIResponsesPublicSanitizer.webSearchSources(
                sources.map { ["type": "url", "url": $0] }
            )
        }
        return [
            "id": id,
            "type": "web_search_call",
            "status": failed ? "failed" : "completed",
            "action": action,
        ]
    }

    private static func nativeSearchItem(for trace: ResponsesWebSearchTrace) throws -> [String: Any] {
        try nativeSearchItem(
            id: trace.id,
            query: trace.query,
            sources: trace.sources,
            failed: trace.failed
        )
    }

    private static func projectionOutput(from data: Data) throws -> [[String: Any]] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw Error.invalidResponse
        }
        guard let output = value as? [[String: Any]] else {
            throw Error.invalidResponse
        }
        return output
    }

    private static func projectionObject(from data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Error.invalidResponse
        }
        guard let object = value as? [String: Any] else {
            throw Error.invalidResponse
        }
        return object
    }

    private static func projectionFragment(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw Error.invalidResponse
        }
    }

    private static func projectionData(from object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }
}
