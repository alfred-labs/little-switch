import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses compaction planning")
struct ResponsesCompactionPlanTests {
    @Test(
        "Ordinary requests remain outside the compaction adapter",
        arguments: [
            #"{"input":"Hello"}"#, #"{"input":[]}"#, #"{"input":[{"role":"user","content":"Hello"}]}"#, #"{}"#,
        ])
    func ordinary(body: String) throws {
        #expect(try ResponsesCompactionPlan.prepare(body: Data(body.utf8)) == nil)
    }

    @Test(
        "Malformed control requests fail before a model call",
        arguments: [
            "invalid-json", "[]",
            #"{"model":"m","input":[{"role":"user","content":"x"},{"type":"compaction_trigger"}]}"#,
            #"{"model":"m","stream":false,"input":[{"role":"user","content":"x"},{"type":"compaction_trigger"}]}"#,
            #"{"model":"m","stream":1,"input":[{"role":"user","content":"x"},{"type":"compaction_trigger"}]}"#,
            #"{"model":"m","stream":true,"input":[{"type":"compaction_trigger"}]}"#,
            #"{"model":"m","stream":true,"input":[{"type":"compaction_trigger"},{"role":"user","content":"x"}]}"#,
            #"{"model":"m","stream":true,"input":[{"type":"compaction_trigger"},{"type":"compaction_trigger"}]}"#,
            #"{"model":"","stream":true,"input":[{"role":"user","content":"x"},{"type":"compaction_trigger"}]}"#,
            #"{"stream":true,"input":[{"role":"user","content":"x"},{"type":"compaction_trigger"}]}"#,
            #"{"model":"m","stream":true,"input":[null,{"type":"compaction_trigger"}]}"#,
            #"{"model":"m","stream":true,"input":[{},{"type":"compaction_trigger"}]}"#,
            #"{"model":"m","stream":true,"input":[{"type":"item_reference","id":"old"},{"type":"compaction_trigger"}]}"#,
        ])
    func malformedControl(body: String) {
        #expect(throws: ResponsesCompactionError.invalidRequest) {
            try ResponsesCompactionPlan.prepare(body: Data(body.utf8))
        }
    }

    @Test(
        "Opaque checkpoints require usable encrypted content before compaction",
        arguments: [
            #"{"type":"compaction"}"#,
            #"{"type":"compaction","encrypted_content":""}"#,
            #"{"type":"compaction","encrypted_content":" "}"#,
            #"{"type":"compaction","encrypted_content":null}"#,
            #"{"type":"compaction","encrypted_content":7}"#,
        ])
    func malformedOpaque(json: String) throws {
        let item = try ResponsesCompactionFixture.object(Data(json.utf8))
        #expect(throws: ResponsesCompactionError.invalidRequest) {
            try ResponsesCompactionFixture.plan(items: [item])
        }
    }

    @Test("Server conversation state cannot be reconstructed", arguments: ["previous_response_id", "conversation"])
    func serverState(key: String) throws {
        #expect(throws: ResponsesCompactionError.invalidRequest) {
            try ResponsesCompactionFixture.plan(fields: [key: "server-state"])
        }
        #expect(try ResponsesCompactionFixture.plan(fields: [key: NSNull()]).originalModel == "original-model")
    }

    @Test("The summary request constrains one function and preserves context as quoted input")
    func summaryRequest() throws {
        let plan = try ResponsesCompactionFixture.plan(fields: [
            "instructions": "Original constraints: keep the test fixtures.",
            "reasoning": ["effort": "high"], "temperature": 0.2, "top_p": 0.9, "max_output_tokens": 500,
            "tools": [["type": "function", "name": "read", "parameters": ["type": "object"]]],
            "text": ["format": ["type": "json_object"]], "store": true,
        ])
        #expect(plan.originalModel == "original-model")
        let request = try ResponsesCompactionFixture.object(plan.summaryRequest(model: "summary-model", stream: false))
        #expect(request["model"] as? String == "summary-model")
        #expect(request["stream"] as? Bool == false)
        #expect(request["store"] as? Bool == false)
        #expect(request["parallel_tool_calls"] as? Bool == false)
        #expect(request["text"] == nil)
        #expect((request["reasoning"] as? [String: String]) == nil)
        #expect(request["temperature"] as? Double == 0.2)
        #expect(request["top_p"] as? Double == 0.9)
        #expect(request["max_output_tokens"] as? Int == 4_000)
        #expect((request["tool_choice"] as? [String: String]) == ["type": "function", "name": "create_summary"])
        let tools = try #require(request["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools.first?["name"] as? String == "create_summary")
        #expect(tools.first?["strict"] as? Bool == true)
        let schema = try #require(tools.first?["parameters"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(schema["required"] as? [String] == ["summary", "retain_item_ids"])
        let input = try #require(request["input"] as? [[String: Any]])
        #expect(input.allSatisfy { $0["role"] as? String == "user" })
        let text = try ResponsesCompactionFixture.text(input)
        #expect(text.contains("Original constraints"))
        #expect(text.contains("item_000001"))
        #expect(!(request["instructions"] as? String ?? "").contains("Original constraints"))
        #expect(
            try ResponsesCompactionFixture.object(plan.summaryRequest(model: "m", stream: true))["stream"] as? Bool
                == true)
        #expect(throws: ResponsesCompactionError.invalidRequest) { try plan.summaryRequest(model: " ", stream: false) }
    }

    @Test("Summary turns carry their own bounded output budget and compactness contract")
    func summaryOutputBudget() throws {
        // The summary is an internal turn, not the conversation: a compacting
        // model without its own budget streamed 20k-character summaries whose
        // exchange died mid-flight, so the budget never inherits the
        // conversation's setting and always stays bounded. The native
        // chatgpt.com backend rejects the parameter outright, so only managed
        // providers receive it.
        let plans = try [
            ResponsesCompactionFixture.plan(fields: [:]),
            ResponsesCompactionFixture.plan(fields: ["max_output_tokens": 100_000]),
        ]
        for plan in plans {
            let managed = try ResponsesCompactionFixture.object(plan.summaryRequest(model: "m", stream: false))
            #expect(managed["max_output_tokens"] as? Int == 4_000)
            let native = try ResponsesCompactionFixture.object(
                plan.summaryRequest(model: "m", stream: true, mode: .nativeContinuation))
            #expect(native["max_output_tokens"] == nil)
            for request in [managed, native] {
                let instructions = try #require(request["instructions"] as? String)
                #expect(instructions.contains("800 words"))
            }
        }
    }

    @Test("Context overflow trims the oldest removable items and marks the summary")
    func contextTrim() throws {
        var history: [[String: Any]] = (0..<10).map { index in
            [
                "type": "message", "role": "assistant",
                "content": [["type": "output_text", "text": "Step \(index) detail."]],
            ]
        }
        history.append(ResponsesCompactionFixture.message)
        var plan = try ResponsesCompactionFixture.plan(items: history)
        #expect(try plan.trimForContextLimit() > 0)
        let request = try ResponsesCompactionFixture.object(plan.summaryRequest(model: "m", stream: false))
        let text = try ResponsesCompactionFixture.text(request["input"] as Any)
        #expect(!text.contains("Step 0"))
        #expect(text.contains("Step 9"))
        #expect(text.contains("Keep working."))
        #expect(
            (request["instructions"] as? String ?? "").contains("Compaction warning:"))
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response(refs: ["item_000010"]))
        let payload = try ResponsesCompactionFixture.payload(result)
        #expect((payload["summary"] as? String)?.hasPrefix("Compaction warning:") == true)
        do {
            _ = try plan.complete(responseBody: ResponsesCompactionFixture.response(refs: ["item_000000"]))
            Issue.record("An omitted reference was accepted")
        } catch let error as ResponsesCompactionError {
            guard case .invalidSelection = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
        }
    }

    @Test("Images remain image input blocks and do not inflate the JSON transcript")
    func images() throws {
        let picture: [String: Any] = [
            "type": "input_image", "image_url": "data:image/png;base64,aW1hZ2U=", "detail": "high",
        ]
        let source: [String: Any] = [
            "role": "user", "content": [["type": "input_text", "text": "Inspect this"], picture],
        ]
        let plan = try ResponsesCompactionFixture.plan(items: [source])
        let request = try ResponsesCompactionFixture.object(plan.summaryRequest(model: "vision", stream: false))
        let messages = try #require(request["input"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(try ResponsesCompactionFixture.data(parts[1]) == ResponsesCompactionFixture.data(picture))
        #expect(!(parts[0]["text"] as? String ?? "").contains("aW1hZ2U="))
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response(refs: ["item_000001"]))
        let payload = try ResponsesCompactionFixture.payload(result)
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any) == ResponsesCompactionFixture.data([source])
        )
    }

    @Test("Tool output images keep their provider image reference")
    func outputImages() throws {
        let image: [String: Any] = ["type": "input_image", "file_id": "file_image"]
        let plan = try ResponsesCompactionFixture.plan(items: [
            ["type": "function_call_output", "name": "task", "output": [image]]
        ])
        let request = try ResponsesCompactionFixture.object(plan.summaryRequest(model: "m", stream: false))
        let messages = try #require(request["input"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(try ResponsesCompactionFixture.data(parts[1]) == ResponsesCompactionFixture.data(image))
        let malformed = try ResponsesCompactionFixture.plan(items: [
            [
                "type": "message", "role": "user", "content": [["type": "input_image"]],
            ]
        ])
        #expect(throws: ResponsesCompactionError.invalidRequest) {
            try malformed.summaryRequest(model: "m", stream: false)
        }
    }

    @Test("Owned continuations expand into summary and unchanged original items")
    func ownedContinuation() throws {
        let prior = try ResponsesCompactionFixture.owned(retained: [ResponsesCompactionFixture.message])
        let plan = try ResponsesCompactionFixture.plan(items: [prior])
        let request = try ResponsesCompactionFixture.object(plan.summaryRequest(model: "m", stream: false))
        let text = try ResponsesCompactionFixture.text(request["input"] as Any)
        #expect(text.contains("Earlier work."))
        #expect(text.contains("item_000002"))
        #expect(!text.contains("little_switch_compaction"))
    }

    @Test("Opaque checkpoints are degraded on custom models but continue natively")
    func rejectsOpaqueContinuations() throws {
        let foreign: [String: Any] = ["type": "compaction", "encrypted_content": "opaque-provider-ciphertext"]
        let plan = try ResponsesCompactionFixture.plan(items: [foreign, ResponsesCompactionFixture.message])
        #expect(throws: ResponsesCompactionError.unsupportedCompaction) {
            try plan.summaryRequest(model: "m", stream: false)
        }
        let native = try ResponsesCompactionFixture.object(
            plan.summaryRequest(model: "m", stream: true, mode: .nativeContinuation))
        let items = try #require(native["input"] as? [[String: Any]])
        #expect(try ResponsesCompactionFixture.data(items[0]) == ResponsesCompactionFixture.data(foreign))
        do {
            _ = try plan.complete(responseBody: ResponsesCompactionFixture.response(refs: ["item_000001"]))
            Issue.record("Retaining an opaque checkpoint unexpectedly completed")
        } catch let error as ResponsesCompactionError {
            guard case .invalidSelection = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
        }
    }
}
