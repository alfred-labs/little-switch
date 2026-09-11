import Foundation
import Testing

@testable import LittleSwitchCore

enum ResponsesCompactionFixture {
    static var message: [String: Any] { ["type": "message", "role": "user", "content": "Keep working."] }

    static func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func object(_ value: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: value) as? [String: Any])
    }

    static func text(_ value: Any) throws -> String {
        try #require(String(bytes: data(value), encoding: .utf8))
    }

    static func request(
        items: [[String: Any]] = [message], fields: [String: Any] = [:]
    ) throws -> Data {
        var request: [String: Any] = [
            "model": "original-model", "stream": true,
            "input": items + [["type": "compaction_trigger"]],
        ]
        request.merge(fields) { _, replacement in replacement }
        return try data(request)
    }

    static func plan(
        items: [[String: Any]] = [message], fields: [String: Any] = [:]
    ) throws -> ResponsesCompactionPlan {
        try #require(try ResponsesCompactionPlan.prepare(body: request(items: items, fields: fields)))
    }

    static func response(
        summary: String = "Continue the task.", refs: [String] = [], fields: [String: Any] = [:]
    ) throws -> Data {
        var response: [String: Any] = [
            "id": "resp_summary", "status": "completed",
            "output": [
                [
                    "type": "function_call", "name": "create_summary", "call_id": "summary_call",
                    "arguments": try text(["summary": summary, "retain_item_ids": refs]),
                ]
            ],
            "usage": ["input_tokens": 12, "output_tokens": 3],
        ]
        response.merge(fields) { _, replacement in replacement }
        return try data(response)
    }

    static func payload(_ result: ResponsesCompactionResult) throws -> [String: Any] {
        let item = try object(result.itemJSON)
        let text = try #require(item["encrypted_content"] as? String)
        return try object(Data(text.utf8))
    }

    static func owned(summary: String = "Earlier work.", retained: [[String: Any]] = []) throws -> [String: Any] {
        [
            "type": "compaction",
            "encrypted_content": try text([
                "type": "little_switch_compaction", "version": 1, "summary": summary, "retained": retained,
            ]),
        ]
    }
}
