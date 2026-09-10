import Foundation
import Testing

@testable import LittleSwitchCore

struct ExceptionalFinishCase: Sendable {
    let finishReason: String
    let status: String
    let incompleteReason: String?
}

@Suite("OpenAI Responses Chat terminal projection")
struct ResponsesChatTerminalTests {
    @Test(
        "ZAI exceptional finish reasons map to explicit Responses terminals",
        arguments: [
            ExceptionalFinishCase(
                finishReason: "sensitive",
                status: "incomplete",
                incompleteReason: "content_filter"
            ),
            ExceptionalFinishCase(
                finishReason: "model_context_window_exceeded",
                status: "failed",
                incompleteReason: nil
            ),
            ExceptionalFinishCase(
                finishReason: "network_error",
                status: "failed",
                incompleteReason: nil
            ),
        ]
    )
    func exceptionalFinishReasons(testCase: ExceptionalFinishCase) throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try requestBody(streaming: false),
            targetModel: "glm-5.3"
        )
        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: try terminalBody(
                finishReason: testCase.finishReason,
                content: "partial"
            ),
            prepared: prepared
        )
        let response = try object(projected)

        #expect(response["status"] as? String == testCase.status)
        #expect(
            (response["incomplete_details"] as? [String: Any])?["reason"] as? String
                == testCase.incompleteReason
        )
        #expect((response["error"] is [String: Any]) == (testCase.status == "failed"))
        if testCase.finishReason == "model_context_window_exceeded" {
            #expect(
                (response["error"] as? [String: Any])?["code"] as? String
                    == "context_length_exceeded"
            )
        }
    }

    @Test("Streaming JSON fallback preserves Codex context exhaustion semantics")
    func streamingContextFailureUsesNativeCode() throws {
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: try requestBody(streaming: true),
            targetModel: "glm-5.3"
        )
        let projected = try OpenAIResponsesChatCompletions.project(
            responseBody: try terminalBody(
                finishReason: "model_context_window_exceeded",
                content: ""
            ),
            prepared: prepared
        )
        let events = try ResponsesStreamingTestSupport.events(projected)

        let error = try #require(events.first { $0.name == "error" })
        #expect(error.payload["code"] as? String == "context_length_exceeded")
        let failed = try #require(events.last?.payload["response"] as? [String: Any])
        #expect(
            (failed["error"] as? [String: Any])?["code"] as? String
                == "context_length_exceeded"
        )
    }

    private func requestBody(streaming: Bool) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": "route",
            "input": "Hello",
            "stream": streaming,
        ])
    }

    private func terminalBody(finishReason: String, content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl_terminal",
            "choices": [
                [
                    "finish_reason": finishReason,
                    "message": ["role": "assistant", "content": content],
                ]
            ],
            "usage": ["prompt_tokens": 2, "completion_tokens": 1],
        ])
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
