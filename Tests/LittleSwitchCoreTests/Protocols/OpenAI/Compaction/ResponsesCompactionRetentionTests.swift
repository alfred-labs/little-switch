import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Responses compaction retained execution state")
struct ResponsesCompactionRetentionTests {
    @Test("Selecting either half retains the exact pair in original order", arguments: ["item_000002", "item_000003"])
    func selectedPair(reference: String) throws {
        let items: [[String: Any]] = [
            ResponsesCompactionFixture.message,
            ["type": "function_call", "call_id": "pair", "namespace": "a.b", "name": "c", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "pair", "output": "result", "extra": ["preserve": true]],
            ["type": "message", "role": "assistant", "content": "The earlier result was handled."],
        ]
        let plan = try ResponsesCompactionFixture.plan(items: items)
        let result = try plan.complete(
            responseBody: ResponsesCompactionFixture.response(refs: [reference, "item_000001"]))
        let payload = try ResponsesCompactionFixture.payload(result)
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(Array(items.prefix(3))))
    }

    @Test("Pending calls, unread results, discovery state and standalone tasking are forced")
    func forcedState() throws {
        let items: [[String: Any]] = [
            ["type": "function_call", "call_id": "old", "name": "read", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "old", "output": "handled"],
            ["type": "tool_search_call", "call_id": "search", "arguments": ["query": "read"], "execution": "client"],
            [
                "type": "tool_search_output", "call_id": "search",
                "tools": [["type": "namespace", "name": "a", "tools": []]],
            ],
            ["type": "message", "role": "assistant", "content": "Search results processed."],
            ["type": "custom_tool_call", "call_id": "pending", "name": "patch", "input": "exact patch"],
            ["type": "function_call_output", "namespace": "a", "name": "b.c", "output": "Task assignment"],
            ["type": "function_call", "call_id": "active", "name": "read", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "active", "output": "unread result"],
            ResponsesCompactionFixture.message,
        ]
        let plan = try ResponsesCompactionFixture.plan(items: items)
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response())
        let payload = try ResponsesCompactionFixture.payload(result)
        let expected = [2, 3, 5, 6, 7, 8].map { items[$0] }
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any) == ResponsesCompactionFixture.data(expected)
        )
        #expect(result.usage == ResponsesUsage(inputTokens: 12, outputTokens: 3))
    }

    @Test("Completed custom pairs become optional after assistant reasoning")
    func customPair() throws {
        let items: [[String: Any]] = [
            ["type": "custom_tool_call", "call_id": "custom", "name": "patch", "input": "patch"],
            ["type": "custom_tool_call_output", "call_id": "custom", "output": "done"],
            ["type": "reasoning", "summary": [["type": "summary_text", "text": "Processed"]]],
        ]
        let plan = try ResponsesCompactionFixture.plan(items: items)
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response())
        #expect((try ResponsesCompactionFixture.payload(result)["retained"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test(
        "Invalid execution histories cannot be hidden by a summary",
        arguments: [
            #"[{"type":"function_call","name":"read"}]"#,
            #"[{"type":"function_call_output","output":"missing identity"}]"#,
            #"[{"type":"function_call_output","name":" ","output":"empty identity"}]"#,
            #"[{"type":"function_call_output","call_id":"orphan","output":"orphan"}]"#,
            #"[{"type":"function_call","call_id":"duplicate","name":"a"},{"type":"function_call","call_id":"duplicate","name":"b"}]"#,
            #"[{"type":"function_call","call_id":"pair","name":"a"},{"type":"function_call_output","call_id":"pair","output":"one"},{"type":"function_call_output","call_id":"pair","output":"two"}]"#,
            #"[{"type":"function_call","call_id":"pair","name":"a"},{"type":"custom_tool_call_output","call_id":"pair","output":"wrong family"}]"#,
        ])
    func invalidState(text: String) throws {
        let items = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        #expect(throws: ResponsesCompactionError.invalidRequest) { try ResponsesCompactionFixture.plan(items: items) }
    }
}
