import Foundation

/// Codex's remote compaction v2 ends its transcript with a terminal
/// `compaction_trigger` input item and requires the response to carry
/// exactly one structured `compaction` output item — a shape only the
/// OpenAI backend emits. Providers answer with a plain summary message, so
/// the gateway rewraps that message into the compaction stream Codex's
/// collector accepts, carrying the summary in a versioned plaintext
/// payload Codex passes through opaquely (the Ollama launcher ships the
/// same design). Replayed compaction items expand back into readable
/// history; foreign ones Codex alone can read are omitted.
package enum OpenAIResponsesRemoteCompaction {
    package static let payloadType = "little_switch_compaction"
    private static let triggerType = "compaction_trigger"

    // MARK: - request

    package static func isCompactionRequest(_ body: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let items = object["input"] as? [[String: Any]]
        else {
            return false
        }
        return items.last?["type"] as? String == triggerType
    }

    /// Forces buffered upstream execution so the summary can be rewrapped
    /// before anything reaches the client. The input comes normalized from
    /// `OpenAIResponsesNativeNamespacing`, which guarantees a JSON object.
    package static func bufferedObject(_ body: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw OpenAIResponsesWebSearch.Error.invalidResponse
        }
        object["stream"] = false
        return try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    // MARK: - provider response

    /// The summary text of the provider's buffered response: the first
    /// output message carrying non-empty text.
    package static func summary(fromProviderBody: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: fromProviderBody)
                as? [String: Any],
            let outputs = object["output"] as? [[String: Any]]
        else {
            return nil
        }
        for output in outputs where output["type"] as? String == "message" {
            guard let parts = output["content"] as? [[String: Any]] else {
                continue
            }
            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    // MARK: - payload

    package static func payload(summary: String) throws -> String {
        let object: [String: Any] = [
            "type": payloadType,
            "version": 1,
            "summary": summary,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }

    package static func summary(fromPayload encryptedContent: String?) -> String? {
        guard
            let encryptedContent,
            let object = try? JSONSerialization.jsonObject(
                with: Data(encryptedContent.utf8)
            ) as? [String: Any],
            object["type"] as? String == payloadType,
            let summary = object["summary"] as? String,
            !summary.isEmpty
        else {
            return nil
        }
        return summary
    }

    // MARK: - stream

    /// The v2 collector accepts exactly this shape: created, in_progress,
    /// one compaction item through added/done, then completed.
    package static func streamBody(
        responseID: String,
        model: String,
        summary: String,
        createdAt: Int
    ) throws -> Data {
        let item: [String: Any] = [
            "type": "compaction",
            "encrypted_content": try payload(summary: summary),
        ]
        let base: [String: Any] = [
            "id": responseID,
            "object": "response",
            "created_at": createdAt,
            "model": model,
            "status": "in_progress",
            "output": [] as [Any],
            "usage": NSNull(),
        ]
        var completed = base
        completed["status"] = "completed"
        completed["completed_at"] = createdAt
        completed["output"] = [item]
        var body = Data()
        try append(&body, event: "response.created", payload: ["response": base])
        try append(&body, event: "response.in_progress", payload: ["response": base])
        try append(&body, event: "response.output_item.added", payload: ["output_index": 0, "item": item])
        try append(&body, event: "response.output_item.done", payload: ["output_index": 0, "item": item])
        try append(&body, event: "response.completed", payload: ["response": completed])
        body.append(Data("\n".utf8))
        return body
    }

    private static func append(
        _ body: inout Data,
        event: String,
        payload: [String: Any]
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        body.append(Data("event: \(event)\n".utf8))
        body.append(Data("data: ".utf8))
        body.append(data)
        body.append(Data("\n\n".utf8))
    }
}
