import Foundation

package enum ResponsesCompactionStream {
    package static func encode(
        _ result: ResponsesCompactionResult,
        model: String,
        id: String = "resp_" + UUID().uuidString.lowercased(),
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) throws -> Data {
        let item = try responsesStreamObject(result.itemJSON)
        let started: [String: Any] = [
            "id": id, "object": "response", "created_at": createdAt,
            "status": "in_progress", "model": model, "output": [], "usage": NSNull(),
        ]
        var completed = started
        completed["status"] = "completed"
        completed["output"] = [item]
        completed["usage"] = responsesPublicUsage(result.usage)
        let events: [(String, [String: Any])] = [
            ("response.created", ["response": started]),
            ("response.in_progress", ["response": started]),
            ("response.output_item.added", ["output_index": 0, "item": item]),
            ("response.output_item.done", ["output_index": 0, "item": item]),
            ("response.completed", ["response": completed]),
        ]
        var bytes = Data()
        for (sequence, event) in events.enumerated() {
            var payload = event.1
            payload["type"] = event.0
            payload["sequence_number"] = sequence
            bytes.append(contentsOf: "event: \(event.0)\ndata: ".utf8)
            bytes.append(try responsesStreamData(payload))
            bytes.append(contentsOf: "\n\n".utf8)
        }
        return bytes
    }
}
