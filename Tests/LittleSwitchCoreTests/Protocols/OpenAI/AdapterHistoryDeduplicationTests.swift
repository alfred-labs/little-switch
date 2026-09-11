import Foundation
import LittleSwitchSearch
import Testing

@testable import LittleSwitchCore

extension OpenAIResponsesNativeNamespacingTests {
    private func dedupRequestBody(input: [Any]) throws -> Data {
        try responseData([
            "model": "little-switch-route",
            "input": input,
            "stream": true,
        ])
    }

    @Test("Repeated identical tool exchanges collapse to the recurrence cap")
    func collapsesRepeatedToolExchanges() throws {
        func goalPair(_ id: Int) -> [[String: Any]] {
            [
                [
                    "type": "function_call", "call_id": "call_\(id)", "name": "get_goal",
                    "arguments": "{}",
                ],
                [
                    "type": "function_call_output", "call_id": "call_\(id)",
                    "output": #"{"goal":null}"#,
                ],
            ]
        }
        let goalPairs = (0..<6).flatMap(goalPair)
        let execPair: [[String: Any]] = [
            [
                "type": "function_call", "call_id": "call_exec",
                "name": "exec_command", "arguments": #"{"cmd":"ls"}"#,
            ],
            [
                "type": "function_call_output", "call_id": "call_exec", "output": "ok",
            ],
        ]
        let task: [[String: Any]] = [
            [
                "type": "message", "role": "user",
                "content": [["type": "input_text", "text": "Review it."]],
            ]
        ]
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            try dedupRequestBody(input: task + goalPairs + execPair)
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        let items = try #require(object["input"] as? [[String: Any]])
        let callIDs = items.compactMap { item -> String? in
            guard item["type"] as? String == "function_call" else { return nil }
            return item["call_id"] as? String
        }
        // Providers pattern-complete on their own replayed history: five
        // identical exchanges lock the model into re-issuing the call, while
        // three stay healthy and preserve the goal protocol's own
        // three-consecutive-turns recurrence signal.
        #expect(
            callIDs == ["call_3", "call_4", "call_5", "call_exec"]
        )
    }

    @Test("Compaction markers drop from provider history")
    func dropsCompactionMarkers() throws {
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(
            try dedupRequestBody(input: [
                [
                    "type": "message", "role": "user",
                    "content": [["type": "input_text", "text": "Hello."]],
                ],
                ["type": "compaction_trigger"],
            ])
        )

        let object = try #require(
            try JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        let items = try #require(object["input"] as? [[String: Any]])
        #expect(items.count == 1)
        #expect(items[0]["type"] as? String == "message")
    }

    @Test("Exchange keys are stable for identical exchanges and unique otherwise")
    func exchangeKeys() throws {
        let call: [String: Any] = [
            "name": "get_goal", "arguments": "{}",
        ]
        let output: [String: Any] = ["output": #"{"goal":null}"#]
        let firstKey = ResponsesHistoryDeduplication.exchangeKey(call: call, output: output)
        let secondKey = ResponsesHistoryDeduplication.exchangeKey(call: call, output: output)
        #expect(firstKey == secondKey)
        // A value JSON cannot represent yields a unique key, so the exchange
        // never collapses with anything — including itself.
        let unencodable: [String: Any] = ["name": Date()]
        let unencodableFirst = ResponsesHistoryDeduplication.exchangeKey(
            call: unencodable, output: output
        )
        let unencodableSecond = ResponsesHistoryDeduplication.exchangeKey(
            call: unencodable, output: output
        )
        #expect(unencodableFirst != unencodableSecond)
    }
}
