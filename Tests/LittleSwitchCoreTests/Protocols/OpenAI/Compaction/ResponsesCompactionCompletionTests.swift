import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses compaction model selection")
struct ResponsesCompactionCompletionTests {
    /// Selection rejections carry a reason for the one repair retry.
    private func expectInvalidSelection(_ body: () throws -> ResponsesCompactionResult) {
        do {
            _ = try body()
            Issue.record("An invalid selection unexpectedly completed")
        } catch let error as ResponsesCompactionError {
            guard case .invalidSelection = error else {
                Issue.record("Expected an invalid selection, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error type \(error)")
        }
    }

    @Test(
        "Empty, repeated and unknown item selections are rejected",
        arguments: [
            "not-json", "[]", #"{}"#,
            #"{"summary":" ","retain_item_ids":[]}"#,
            #"{"summary":"summary","retain_item_ids":null}"#,
            #"{"summary":"summary","retain_item_ids":[1]}"#,
            #"{"summary":"summary","retain_item_ids":["item_000001","item_000001"]}"#,
            #"{"summary":"summary","retain_item_ids":["item_999999"]}"#,
            #"{"summary":"summary","retain_item_ids":[],"extra":true}"#,
        ])
    func invalidArguments(arguments: String) throws {
        let plan = try ResponsesCompactionFixture.plan()
        let response = try ResponsesCompactionFixture.response(fields: [
            "output": [["type": "function_call", "name": "create_summary", "arguments": arguments]]
        ])
        expectInvalidSelection { try plan.complete(responseBody: response) }
    }

    @Test(
        "Only one completed summary function may authorize a payload",
        arguments: [
            #"[]"#,
            #"[{"type":"function_call","name":"other","arguments":"{}"}]"#,
            #"[{"type":"function_call","name":"create_summary","arguments":{}}]"#,
            #"[{"type":"function_call","namespace":"unrelated","name":"create_summary","arguments":"{}"}]"#,
            #"[{"type":"function_call","name":"create_summary","arguments":"{}"},{"type":"function_call","name":"other","arguments":"{}"}]"#,
        ])
    func invalidOutput(text: String) throws {
        let output = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let plan = try ResponsesCompactionFixture.plan()
        let response = try ResponsesCompactionFixture.response(fields: ["output": output])
        expectInvalidSelection { try plan.complete(responseBody: response) }
    }

    @Test(
        "Provider interruptions do not produce usable compaction", arguments: ["failed", "incomplete", "in_progress"])
    func interrupted(status: String) throws {
        let plan = try ResponsesCompactionFixture.plan()
        #expect(throws: ResponsesCompactionError.invalidResponse) {
            try plan.complete(responseBody: ResponsesCompactionFixture.response(fields: ["status": status]))
        }
    }

    @Test("Complete usage details survive summary projection")
    func usage() throws {
        let plan = try ResponsesCompactionFixture.plan()
        let result = try plan.complete(
            responseBody: ResponsesCompactionFixture.response(
                summary: "  Preserve work.  ",
                fields: [
                    "usage": [
                        "input_tokens": 20, "output_tokens": 5, "total_tokens": 25,
                        "input_tokens_details": ["cached_tokens": 10, "cache_write_tokens": 2],
                        "output_tokens_details": ["reasoning_tokens": 3],
                    ]
                ]))
        #expect(
            result.usage
                == ResponsesUsage(
                    inputTokens: 20,
                    outputTokens: 5,
                    cachedInputTokens: 10,
                    cacheWriteInputTokens: 2,
                    reasoningOutputTokens: 3))
        #expect(try ResponsesCompactionFixture.payload(result)["summary"] as? String == "Preserve work.")
        #expect(throws: ResponsesCompactionError.invalidResponse) {
            try plan.complete(responseBody: Data("invalid-json".utf8))
        }
        #expect(throws: ResponsesCompactionError.invalidResponse) {
            try plan.complete(
                responseBody: ResponsesCompactionFixture.response(fields: ["usage": ["input_tokens": -1]]))
        }
    }
}
