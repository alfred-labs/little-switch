import Foundation

extension ResponsesPublicStreamSession {
    func publicContentReference(
        outputIndex: Int,
        contentIndex: Int,
        itemID: String,
        requiredType: String
    ) throws -> (output: OutputMapping, content: ContentMapping) {
        guard providerTurnActive,
            outputIndex >= 0,
            contentIndex >= 0,
            let output = providerOutput[outputIndex],
            output.id == itemID,
            let content = output.content[contentIndex],
            content.type == requiredType
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return (output, content)
    }

    func publicFunctionReference(
        outputIndex: Int,
        itemID: String,
        callID: String,
        name: String
    ) throws -> OutputMapping {
        guard providerTurnActive,
            outputIndex >= 0,
            let output = providerOutput[outputIndex],
            output.type == "function_call",
            output.id == itemID,
            output.callID == callID,
            output.name == name
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return output
    }

    mutating func allocateOutputIndex() throws -> Int {
        let index = nextOutputIndex
        let next = index.addingReportingOverflow(1)
        guard !next.overflow else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        nextOutputIndex = next.partialValue
        return index
    }

    mutating func frame(
        _ name: String,
        payload: [String: Any]
    ) throws -> Data {
        let sequenceNumber = nextSequenceNumber
        let next = sequenceNumber.addingReportingOverflow(1)
        guard !next.overflow else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var object = payload
        object["type"] = name
        object["sequence_number"] = sequenceNumber
        var data = Data("event: \(name)\ndata: ".utf8)
        data.append(try responsesStreamData(object))
        data.append(Data("\n\n".utf8))
        nextSequenceNumber = next.partialValue
        return data
    }

    func completedOutputItems(requireComplete: Bool) throws -> [[String: Any]] {
        if requireComplete, completedOutput.count != nextOutputIndex {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let sortedEntries = completedOutput.sorted { lhs, rhs in
            lhs.key < rhs.key
        }
        return try sortedEntries.map { entry in
            try publicResponseObject(entry.value)
        }
    }

    func finalResponse(
        sourceJSON: Data,
        terminal: ResponsesStreamTerminal,
        usage: ResponsesUsage
    ) throws -> [String: Any] {
        guard let firstResponseJSON,
            let publicResponseID,
            let publicCreatedAt
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let output = try completedOutputItems(requireComplete: true)
        switch configuration {
        case .webSearch(let prepared):
            let turn = try OpenAIResponsesWebSearch.parseModelTurn(sourceJSON)
            let projection = try OpenAIResponsesWebSearch.projectedResponse(
                prepared: prepared,
                traces: [],
                finalTurn: turn,
                usage: usage,
                responseMetadataJSON: firstResponseJSON,
                publicOutputJSON: try responsesStreamData(output),
                terminalStatus: terminal
            )
            return projection.object
        case .chatCompletions:
            let source = try publicResponseObject(sourceJSON)
            let identity = try publicResponseObject(firstResponseJSON)
            guard source["object"] as? String == "response" else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            var response = try OpenAIResponsesPublicSanitizer.responseShell(
                provider: source,
                identity: identity
            )
            response["id"] = publicResponseID
            response["created_at"] = publicCreatedAt
            response["output"] = output
            response["status"] = terminal.rawValue
            response["usage"] = responsesPublicUsage(usage)
            try applyClientMetadata(to: &response)
            return response
        }
    }

    func failedResponse(code: String, message: String) throws -> [String: Any] {
        var response: [String: Any]
        if let firstResponseJSON {
            response = try publicResponseObject(firstResponseJSON)
            response["output"] = try completedOutputItems(requireComplete: false)
        } else {
            let timestamp = max(0, Int(Date().timeIntervalSince1970))
            let identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            response = [
                "id": "resp_\(identifier)",
                "object": "response",
                "created_at": timestamp,
                "model": configuration.originalModel,
                "output": [],
            ]
            try applyClientMetadata(to: &response)
        }
        response["status"] = "failed"
        response["completed_at"] = NSNull()
        response["usage"] = NSNull()
        response["error"] = [
            "code": code,
            "message": message,
        ]
        return response
    }

    func applyClientMetadata(to response: inout [String: Any]) throws {
        let fields = try OpenAIResponsesPublicSanitizer.clientResponseFields(
            originalBody: configuration.originalBody,
            originalModel: configuration.originalModel
        )
        for (key, value) in fields {
            response[key] = value
        }
    }
}

func publicResponseObject(_ data: Data) throws -> [String: Any] {
    try responsesStreamObject(data)
}

func responsesPublicUsage(_ usage: ResponsesUsage) -> [String: Any] {
    [
        "input_tokens": usage.inputTokens,
        "input_tokens_details": [
            "cached_tokens": usage.cachedInputTokens,
            "cache_write_tokens": usage.cacheWriteInputTokens,
        ],
        "output_tokens": usage.outputTokens,
        "output_tokens_details": [
            "reasoning_tokens": usage.reasoningOutputTokens
        ],
        "total_tokens": usage.totalTokens,
    ]
}
