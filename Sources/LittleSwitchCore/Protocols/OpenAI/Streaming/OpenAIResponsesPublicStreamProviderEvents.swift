import Foundation

extension ResponsesPublicStreamSession {
    mutating func beginProviderTurn(_ responseJSON: Data) throws -> [Data] {
        guard !providerTurnActive,
            providerOutput.isEmpty,
            let responseID = nonemptyResponsesString(
                try publicResponseObject(responseJSON)["id"]
            )
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        _ = responseID
        providerTurnActive = true
        lastProviderTerminal = nil
        return []
    }

    mutating func consumeOutputItemAdded(
        outputIndex: Int,
        itemJSON: Data
    ) throws -> [Data] {
        guard providerTurnActive,
            outputIndex >= 0,
            providerOutput[outputIndex] == nil
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let providerItem = try publicResponseObject(itemJSON)
        guard let id = nonemptyResponsesString(providerItem["id"]),
            let type = nonemptyResponsesString(providerItem["type"])
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var item = try OpenAIResponsesPublicSanitizer.item(providerItem)
        let function = try responsesFunctionMetadata(item, required: type == "function_call")
        let privateSearch = OpenAIResponsesWebSearch.isPrivateSearchCall(
            item, privateToolName: configuration.privateSearchToolName
        )
        let toolSearchContract = configuration.toolSearchContract.flatMap { $0.owns(item) ? $0 : nil }
        let publicIndex: Int?
        if privateSearch {
            publicIndex = nil
        } else {
            guard !usedPublicItemIDs.contains(id) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            publicIndex = try allocateOutputIndex()
            usedPublicItemIDs.insert(id)
        }

        if ["message", "function_call"].contains(type) {
            item["status"] = "in_progress"
        }
        let mapping = OutputMapping(
            id: id,
            type: type,
            name: function?.name,
            callID: function?.callID,
            publicIndex: publicIndex,
            isPrivateSearch: privateSearch,
            toolSearchContract: toolSearchContract
        )
        providerOutput[outputIndex] = mapping
        guard let publicIndex else {
            return []
        }
        item = try toolSearchContract?.projectItem(item, starting: true) ?? item
        return [
            try frame(
                "response.output_item.added",
                payload: ["output_index": publicIndex, "item": item]
            )
        ]
    }

    mutating func consumeOutputItemDone(
        outputIndex: Int,
        itemJSON: Data
    ) throws -> [Data] {
        guard providerTurnActive,
            let mapping = providerOutput[outputIndex],
            mapping.content.isEmpty
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let item = try OpenAIResponsesPublicSanitizer.item(
            try publicResponseObject(itemJSON)
        )
        guard nonemptyResponsesString(item["id"]) == mapping.id,
            nonemptyResponsesString(item["type"]) == mapping.type
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if mapping.type == "function_call" {
            let function = try responsesFunctionMetadata(item, required: true)
            guard function?.name == mapping.name,
                function?.callID == mapping.callID
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
        }
        providerOutput.removeValue(forKey: outputIndex)
        guard !mapping.isPrivateSearch, let publicIndex = mapping.publicIndex else {
            return []
        }
        let publicItem = try mapping.toolSearchContract?.projectItem(item) ?? item
        let data = try responsesStreamData(publicItem)
        completedOutput[publicIndex] = data
        return [
            try frame(
                "response.output_item.done",
                payload: ["output_index": publicIndex, "item": publicItem]
            )
        ]
    }

    mutating func consumeContentPartAdded(
        outputIndex: Int,
        contentIndex: Int,
        itemID: String,
        partJSON: Data
    ) throws -> [Data] {
        guard providerTurnActive,
            outputIndex >= 0,
            contentIndex >= 0,
            !itemID.isEmpty,
            var mapping = providerOutput[outputIndex],
            mapping.id == itemID,
            mapping.content[contentIndex] == nil
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let providerPart = try publicResponseObject(partJSON)
        guard let type = nonemptyResponsesString(providerPart["type"]) else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let part = try OpenAIResponsesPublicSanitizer.contentPart(providerPart)
        let publicContentIndex = mapping.nextContentIndex
        let next = publicContentIndex.addingReportingOverflow(1)
        guard !next.overflow else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        mapping.nextContentIndex = next.partialValue
        mapping.content[contentIndex] = ContentMapping(
            publicIndex: publicContentIndex,
            type: type
        )
        providerOutput[outputIndex] = mapping
        guard !mapping.isPrivateSearch, let publicIndex = mapping.publicIndex else {
            return []
        }
        return [
            try frame(
                "response.content_part.added",
                payload: [
                    "output_index": publicIndex,
                    "content_index": publicContentIndex,
                    "item_id": itemID,
                    "part": part,
                ]
            )
        ]
    }

    mutating func consumeOutputTextDelta(
        outputIndex: Int,
        contentIndex: Int,
        itemID: String,
        delta: String
    ) throws -> [Data] {
        let mapping = try publicContentReference(
            outputIndex: outputIndex,
            contentIndex: contentIndex,
            itemID: itemID,
            requiredType: "output_text"
        )
        guard !mapping.output.isPrivateSearch,
            let publicIndex = mapping.output.publicIndex
        else {
            return []
        }
        return [
            try frame(
                "response.output_text.delta",
                payload: [
                    "output_index": publicIndex,
                    "content_index": mapping.content.publicIndex,
                    "item_id": itemID,
                    "delta": delta,
                    "logprobs": [],
                ]
            )
        ]
    }

    mutating func consumeOutputTextDone(
        outputIndex: Int,
        contentIndex: Int,
        itemID: String,
        text: String
    ) throws -> [Data] {
        let mapping = try publicContentReference(
            outputIndex: outputIndex,
            contentIndex: contentIndex,
            itemID: itemID,
            requiredType: "output_text"
        )
        guard !mapping.output.isPrivateSearch,
            let publicIndex = mapping.output.publicIndex
        else {
            return []
        }
        return [
            try frame(
                "response.output_text.done",
                payload: [
                    "output_index": publicIndex,
                    "content_index": mapping.content.publicIndex,
                    "item_id": itemID,
                    "text": text,
                    "logprobs": [],
                ]
            )
        ]
    }

    mutating func consumeFunctionArgumentsDelta(
        outputIndex: Int,
        itemID: String,
        callID: String,
        name: String,
        delta: String
    ) throws -> [Data] {
        let mapping = try publicFunctionReference(
            outputIndex: outputIndex,
            itemID: itemID,
            callID: callID,
            name: name
        )
        guard !mapping.isPrivateSearch, mapping.toolSearchContract == nil, let publicIndex = mapping.publicIndex else {
            return []
        }
        return [
            try frame(
                "response.function_call_arguments.delta",
                payload: [
                    "output_index": publicIndex,
                    "item_id": itemID,
                    "delta": delta,
                ]
            )
        ]
    }

    mutating func consumeFunctionArgumentsDone(
        outputIndex: Int,
        itemID: String,
        callID: String,
        name: String,
        arguments: String
    ) throws -> [Data] {
        let mapping = try publicFunctionReference(
            outputIndex: outputIndex,
            itemID: itemID,
            callID: callID,
            name: name
        )
        guard !mapping.isPrivateSearch, mapping.toolSearchContract == nil, let publicIndex = mapping.publicIndex else {
            return []
        }
        return [
            try frame(
                "response.function_call_arguments.done",
                payload: [
                    "output_index": publicIndex,
                    "item_id": itemID,
                    "name": name,
                    "arguments": arguments,
                ]
            )
        ]
    }

    mutating func consumePassthrough(
        type: String,
        payloadJSON: Data
    ) throws -> [Data] {
        guard providerTurnActive else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        var payload = try publicResponseObject(payloadJSON)
        guard nonemptyResponsesString(payload["type"]) == type else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        guard let publicKeys = try publicPassthroughKeys(for: type) else {
            return []
        }

        payload = payload.filter { publicKeys.contains($0.key) }
        guard let providerIndexValue = payload["output_index"] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        guard let providerIndex = nonnegativeResponsesIndex(providerIndexValue),
            var mapping = providerOutput[providerIndex]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        guard nonemptyResponsesString(payload["item_id"]) == mapping.id else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        if let providerContentValue = payload["content_index"] {
            guard let providerContentIndex = nonnegativeResponsesIndex(providerContentValue),
                let content = mapping.content[providerContentIndex]
            else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            payload = try publicContentEventPayload(
                type,
                payload: payload,
                content: content
            )
            payload["content_index"] = content.publicIndex
            if type == "response.content_part.done" {
                guard let part = payload["part"] as? [String: Any],
                    nonemptyResponsesString(part["type"]) == content.type
                else {
                    throw OpenAIResponsesWebSearch.Error.invalidResponse
                }
                mapping.content.removeValue(forKey: providerContentIndex)
                providerOutput[providerIndex] = mapping
            }
        } else {
            payload = try publicReasoningEventPayload(
                type,
                payload: payload,
                output: mapping
            )
        }
        guard !mapping.isPrivateSearch, let publicIndex = mapping.publicIndex else {
            return []
        }
        payload["output_index"] = publicIndex
        return [try frame(type, payload: payload)]
    }

    mutating func consumeProviderTerminal(
        status: ResponsesStreamTerminal,
        responseJSON: Data
    ) throws -> [Data] {
        guard providerTurnActive,
            providerOutput.isEmpty
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let response = try publicResponseObject(responseJSON)
        if status == .failed {
            guard validResponsesFailedResponse(response) else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            providerTurnActive = false
            lastProviderTerminal = .failed
            let providerCode = (response["error"] as? [String: Any])?["code"] as? String
            let publicCode =
                providerCode == "context_length_exceeded"
                ? "context_length_exceeded"
                : "server_error"
            return try fail(code: publicCode, message: "Internal server error")
        }
        guard nonemptyResponsesString(response["id"]) != nil,
            response["object"] as? String == "response",
            response["status"] as? String == status.rawValue,
            response["output"] is [Any],
            response["usage"] is [String: Any]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        providerTurnActive = false
        lastProviderTerminal = status
        return []
    }

}

private func publicPassthroughKeys(for type: String) throws -> Set<String>? {
    switch type {
    case "response.in_progress", "response.queued":
        return nil
    case "error", "response.created", "response.completed", "response.incomplete",
        "response.failed":
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    case "response.content_part.done":
        return ["output_index", "content_index", "item_id", "part"]
    case "response.reasoning_summary_part.added",
        "response.reasoning_summary_part.done":
        return ["output_index", "item_id", "summary_index", "part"]
    case "response.reasoning_summary_text.delta":
        return ["output_index", "item_id", "summary_index", "delta"]
    case "response.reasoning_summary_text.done":
        return ["output_index", "item_id", "summary_index", "text"]
    case "response.output_text.annotation.added":
        return [
            "output_index",
            "content_index",
            "item_id",
            "annotation_index",
            "annotation",
        ]
    default:
        return nil
    }
}

private func publicContentEventPayload(
    _ type: String,
    payload: [String: Any],
    content: ResponsesPublicStreamSession.ContentMapping
) throws -> [String: Any] {
    var payload = payload
    if type == "response.content_part.done" {
        payload["part"] = try OpenAIResponsesPublicSanitizer.contentPart(payload["part"])
        return payload
    }
    guard content.type == "output_text",
        nonnegativeResponsesIndex(payload["annotation_index"]) != nil
    else {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
    payload["annotation"] = try OpenAIResponsesPublicSanitizer.annotation(
        payload["annotation"]
    )
    return payload
}

private func publicReasoningEventPayload(
    _ type: String,
    payload: [String: Any],
    output: ResponsesPublicStreamSession.OutputMapping
) throws -> [String: Any] {
    var payload = payload
    guard output.type == "reasoning",
        nonnegativeResponsesIndex(payload["summary_index"]) != nil
    else {
        throw OpenAIResponsesWebSearch.Error.invalidResponse
    }
    if [
        "response.reasoning_summary_part.added",
        "response.reasoning_summary_part.done",
    ].contains(type) {
        payload["part"] = try OpenAIResponsesPublicSanitizer.summaryPart(payload["part"])
    } else if type == "response.reasoning_summary_text.delta" {
        guard payload["delta"] is String else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
    } else {
        guard payload["text"] is String else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
    }
    return payload
}
