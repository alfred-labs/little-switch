import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Repeated tool history identity boundaries")
struct HistoryDeduplicationIdentityTests {
    @Test("Identical leaf names in different namespaces never share a recurrence run")
    func namespaceIdentity() throws {
        let input = (0..<6).flatMap { pair($0, namespace: $0.isMultiple(of: 2) ? "a" : "b") }
        #expect(try data(ResponsesHistoryDeduplication.collapsed(input)) == data(input))
    }

    @Test("Only matching call and output IDs form an exchange", arguments: [false, true])
    func matchingIDs(missing: Bool) throws {
        let input = (0..<6).flatMap { index in
            var items = pair(index)
            if missing {
                items[0].removeValue(forKey: "call_id")
                items[1].removeValue(forKey: "call_id")
            } else {
                items[1]["call_id"] = "other_\(index)"
            }
            return items
        }
        #expect(try data(ResponsesHistoryDeduplication.collapsed(input)) == data(input))
    }

    @Test("Different output metadata keeps exchanges distinct")
    func outputMetadata() throws {
        let input = (0..<6).flatMap { index in
            var items = pair(index)
            items[1]["status"] = index.isMultiple(of: 2) ? "completed" : "incomplete"
            return items
        }
        #expect(try data(ResponsesHistoryDeduplication.collapsed(input)) == data(input))
    }

    @Test("Both adapters cap custom history consistently", arguments: [false, true], [false, true])
    func customHistoryParity(chat: Bool, active: Bool) throws {
        let input = (0..<6).flatMap { index in
            [
                ["type": "custom_tool_call", "call_id": "call_\(index)", "name": "retired", "input": "same"],
                ["type": "custom_tool_call_output", "call_id": "call_\(index)", "output": "done"],
            ]
        }
        var request: [String: Any] = ["model": "route", "input": input]
        if active { request["tools"] = [["type": "custom", "name": "retired", "format": ["type": "text"]]] }
        let body = try data(request)
        let projected =
            if chat {
                try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "custom").upstreamBody
            } else {
                try OpenAIResponsesNativeNamespacing.normalize(body).body
            }
        let root = try #require(try JSONSerialization.jsonObject(with: projected) as? [String: Any])
        let ids: [String]
        if chat {
            ids = (root["messages"] as? [[String: Any]] ?? [])
                .flatMap { $0["tool_calls"] as? [[String: Any]] ?? [] }.compactMap { $0["id"] as? String }
        } else {
            ids = (root["input"] as? [[String: Any]] ?? [])
                .filter { ["function_call", "custom_tool_call"].contains($0["type"] as? String ?? "") }
                .compactMap { $0["call_id"] as? String }
        }
        #expect(ids == ["call_3", "call_4", "call_5"])
        #expect(try data(request) == body)
    }

    @Test("Unreadable agent mail separates repetition runs on both wires", arguments: [false, true])
    func droppedMailBoundary(chat: Bool) throws {
        let input = (0..<3).flatMap { pair($0) } + [["type": "agent_message"]] + (3..<6).flatMap { pair($0) }
        let body = try data(["model": "route", "input": input])
        if chat {
            let prepared = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "custom")
            let root = try #require(try JSONSerialization.jsonObject(with: prepared.upstreamBody) as? [String: Any])
            let messages = try #require(root["messages"] as? [[String: Any]])
            let ids = messages.flatMap { $0["tool_calls"] as? [[String: Any]] ?? [] }
                .compactMap { $0["id"] as? String }
            #expect(ids == (0..<6).map { "call_\($0)" })
            #expect(prepared.droppedMailCount == 1)
        } else {
            let prepared = try OpenAIResponsesNativeNamespacing.normalize(body)
            let root = try #require(try JSONSerialization.jsonObject(with: prepared.body) as? [String: Any])
            let items = try #require(root["input"] as? [[String: Any]])
            let ids = items.filter { $0["type"] as? String == "function_call" }.compactMap { $0["call_id"] as? String }
            #expect(ids == (0..<6).map { "call_\($0)" })
            #expect(prepared.droppedMailCount == 1)
        }
    }

    @Test("User and reasoning boundaries preserve separate runs", arguments: ["message", "reasoning"])
    func turnBoundaries(kind: String) throws {
        let input = (0..<3).flatMap { pair($0) } + [["type": kind]] + (3..<6).flatMap { pair($0) }
        #expect(try data(ResponsesHistoryDeduplication.collapsed(input)) == data(input))
    }

    private func pair(_ index: Int, namespace: String? = nil) -> [[String: Any]] {
        var call: [String: Any] = [
            "type": "function_call", "call_id": "call_\(index)", "name": "run", "arguments": "{}",
        ]
        if let namespace { call["namespace"] = namespace }
        return [call, ["type": "function_call_output", "call_id": "call_\(index)", "output": "done"]]
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
