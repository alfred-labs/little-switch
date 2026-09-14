import Foundation
import LittleSwitchCommon
import LittleSwitchWire

extension OpenAIResponsesWebSearch {
    static func streamingResponse(
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
        return try OpenAIResponsesStreaming.encode(completed: projection.object)
    }
}

package enum OpenAIResponsesStreaming {
    static func encode(providerFallback: [String: Any]) throws -> Data {
        try encode(
            completed: OpenAIResponsesPublicSanitizer.providerTransportResponse(
                providerFallback
            )
        )
    }

    static func encode(completed: [String: Any]) throws -> Data {
        guard let status = completed["status"] as? String,
            let output = completed["output"] as? [[String: Any]]
        else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        let terminalEvent = try terminalEvent(for: status)
        var inProgress = completed
        inProgress["completed_at"] = NSNull()
        inProgress["output"] = []
        inProgress["status"] = "in_progress"
        inProgress["usage"] = NSNull()
        if status == "failed" {
            inProgress["error"] = NSNull()
        }

        var encoder = ResponsesSSEEncoder()
        try encoder.append("response.created", payload: ["response": inProgress])
        try encoder.append("response.in_progress", payload: ["response": inProgress])
        for (index, item) in output.enumerated() {
            try encoder.append(item: item, outputIndex: index)
        }
        if status == "failed" {
            let failureCode = safeFailureCode(completed["error"])
            try encoder.append(
                "error",
                payload: [
                    "code": failureCode,
                    "message": "Internal server error",
                    "param": NSNull(),
                ]
            )
            var failed = completed
            failed["error"] = [
                "code": failureCode,
                "message": "Internal server error",
            ]
            try encoder.append(terminalEvent, payload: ["response": failed])
        } else {
            try encoder.append(terminalEvent, payload: ["response": completed])
        }
        return encoder.body
    }

    private static func safeFailureCode(_ value: Any?) -> String {
        guard let error = value as? [String: Any],
            error["code"] as? String == "context_length_exceeded"
        else {
            return "server_error"
        }
        return "context_length_exceeded"
    }

    private static func terminalEvent(for status: String) throws -> String {
        switch status {
        case "completed":
            "response.completed"
        case "incomplete":
            "response.incomplete"
        case "failed":
            "response.failed"
        default:
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
    }
}

private struct ResponsesSSEEncoder {
    private(set) var body = Data()
    private var sequenceNumber = 0

    mutating func append(
        _ name: String,
        payload: [String: Any]
    ) throws {
        var event = payload
        event["type"] = name
        event["sequence_number"] = sequenceNumber
        sequenceNumber += 1
        let wire = try responsesWireDecode(OpenAIResponseStreamEvent.self, json: WireJSONCompatibility.value(event))
        let data = try WireCodec.encode(wire)
        body.append(contentsOf: "event: \(name)\ndata: ".utf8)
        body.append(data)
        body.append(contentsOf: "\n\n".utf8)
    }

    mutating func append(item: [String: Any], outputIndex: Int) throws {
        switch item["type"] as? String {
        case "tool_search_call":
            let completed = try OpenAIResponsesPublicSanitizer.item(item)
            var pending = completed
            pending["status"] = "in_progress"
            pending["arguments"] = [:] as [String: Any]
            try append("response.output_item.added", payload: ["output_index": outputIndex, "item": pending])
            try append("response.output_item.done", payload: ["output_index": outputIndex, "item": completed])
        case "web_search_call":
            let itemID = try requiredString("id", in: item)
            try appendWebSearch(
                try OpenAIResponsesPublicSanitizer.item(item),
                itemID: itemID,
                outputIndex: outputIndex
            )
        case "reasoning":
            let itemID = try requiredString("id", in: item)
            let summaries = item["summary"] as? [[String: Any]] ?? []
            try appendReasoning(
                try OpenAIResponsesPublicSanitizer.item(item),
                summaries: summaries,
                itemID: itemID,
                outputIndex: outputIndex
            )
        case "message":
            let itemID = try requiredString("id", in: item)
            guard let content = item["content"] as? [[String: Any]] else {
                throw OpenAIResponsesWebSearch.Error.invalidResponse
            }
            try appendMessage(
                try OpenAIResponsesPublicSanitizer.item(item),
                content: content,
                itemID: itemID,
                outputIndex: outputIndex
            )
        case "function_call", "custom_tool_call":
            try appendToolCall(item, outputIndex: outputIndex)
        case .some, nil:
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
    }

    private mutating func appendWebSearch(
        _ item: [String: Any],
        itemID: String,
        outputIndex: Int
    ) throws {
        let pending: [String: Any] = [
            "id": itemID,
            "type": "web_search_call",
            "status": "in_progress",
        ]
        try append(
            "response.output_item.added",
            payload: ["output_index": outputIndex, "item": pending]
        )
        let reference: [String: Any] = ["item_id": itemID, "output_index": outputIndex]
        try append("response.web_search_call.in_progress", payload: reference)
        try append("response.web_search_call.searching", payload: reference)
        if item["status"] as? String != "failed" {
            try append("response.web_search_call.completed", payload: reference)
        }
        try append(
            "response.output_item.done",
            payload: ["output_index": outputIndex, "item": item]
        )
    }

    private mutating func appendReasoning(
        _ item: [String: Any],
        summaries: [[String: Any]],
        itemID: String,
        outputIndex: Int
    ) throws {
        var pending = item
        pending["summary"] = []
        try append(
            "response.output_item.added",
            payload: ["output_index": outputIndex, "item": pending]
        )

        for (summaryIndex, summary) in summaries.enumerated() {
            let summary = try OpenAIResponsesPublicSanitizer.summaryPart(summary)
            let text = try requiredString("text", in: summary, allowEmpty: true)
            let reference: [String: Any] = [
                "item_id": itemID,
                "output_index": outputIndex,
                "summary_index": summaryIndex,
            ]
            var addedPart = reference
            addedPart["part"] = ["type": "summary_text", "text": ""]
            try append("response.reasoning_summary_part.added", payload: addedPart)
            if !text.isEmpty {
                try append(
                    "response.reasoning_summary_text.delta",
                    payload: adding(["delta": text], to: reference)
                )
            }
            try append(
                "response.reasoning_summary_text.done",
                payload: adding(["text": text], to: reference)
            )
            try append(
                "response.reasoning_summary_part.done",
                payload: adding(["part": summary], to: reference)
            )
        }
        try append(
            "response.output_item.done",
            payload: ["output_index": outputIndex, "item": item]
        )
    }

    private mutating func appendMessage(
        _ item: [String: Any],
        content: [[String: Any]],
        itemID: String,
        outputIndex: Int
    ) throws {
        var pending = item
        pending["content"] = []
        pending["status"] = "in_progress"
        try append(
            "response.output_item.added",
            payload: ["output_index": outputIndex, "item": pending]
        )
        for (contentIndex, part) in content.enumerated() {
            try appendContentPart(
                part,
                itemID: itemID,
                outputIndex: outputIndex,
                contentIndex: contentIndex
            )
        }
        try append(
            "response.output_item.done",
            payload: ["output_index": outputIndex, "item": item]
        )
    }

    private mutating func appendContentPart(
        _ providerPart: [String: Any],
        itemID: String,
        outputIndex: Int,
        contentIndex: Int
    ) throws {
        let part = try OpenAIResponsesPublicSanitizer.contentPart(providerPart)
        let reference: [String: Any] = [
            "item_id": itemID,
            "output_index": outputIndex,
            "content_index": contentIndex,
        ]
        var pending = part
        if part["type"] as? String == "output_text" {
            pending["text"] = ""
        }
        try append(
            "response.content_part.added",
            payload: adding(["part": pending], to: reference)
        )
        if part["type"] as? String == "output_text" {
            let text = try requiredString("text", in: part, allowEmpty: true)
            if !text.isEmpty {
                try append(
                    "response.output_text.delta",
                    payload: adding(["delta": text, "logprobs": []], to: reference)
                )
            }
            try append(
                "response.output_text.done",
                payload: adding(["text": text, "logprobs": []], to: reference)
            )
        }
        try append(
            "response.content_part.done",
            payload: adding(["part": part], to: reference)
        )
    }

    private mutating func appendToolCall(
        _ providerItem: [String: Any],
        outputIndex: Int
    ) throws {
        let custom = providerItem["type"] as? String == "custom_tool_call"
        let inputKey = custom ? "input" : "arguments"
        let eventName = custom ? "response.custom_tool_call_input" : "response.function_call_arguments"
        let itemID = try requiredString("id", in: providerItem)
        let name = try requiredString("name", in: providerItem)
        let input = try requiredString(inputKey, in: providerItem, allowEmpty: true)
        let item = try OpenAIResponsesPublicSanitizer.item(providerItem)
        var pending = item
        pending[inputKey] = ""
        pending["status"] = "in_progress"
        try append(
            "response.output_item.added",
            payload: ["output_index": outputIndex, "item": pending]
        )
        let reference: [String: Any] = ["item_id": itemID, "output_index": outputIndex]
        if !input.isEmpty {
            try append(
                eventName + ".delta",
                payload: adding(["delta": input], to: reference)
            )
        }
        var done = [inputKey: input]
        if !custom { done["name"] = name }
        try append(eventName + ".done", payload: adding(done, to: reference))
        try append(
            "response.output_item.done",
            payload: ["output_index": outputIndex, "item": item]
        )
    }

    private func requiredString(
        _ key: String,
        in object: [String: Any],
        allowEmpty: Bool = false
    ) throws -> String {
        guard let value = object[key] as? String, allowEmpty || !value.isEmpty else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        return value
    }

    private func adding(
        _ additions: [String: Any],
        to base: [String: Any]
    ) -> [String: Any] {
        var result = base
        for (key, value) in additions {
            result[key] = value
        }
        return result
    }
}
