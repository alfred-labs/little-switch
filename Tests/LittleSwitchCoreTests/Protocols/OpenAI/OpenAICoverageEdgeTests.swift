import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI defensive coverage edges")
// These tests intentionally keep the fail-closed boundary matrix together.
// swiftlint:disable function_body_length
struct OpenAICoverageEdgeTests {
    @Test("JSON helpers reject malformed and non-object values")
    func jsonHelpers() throws {
        let absent = try WireCodec.decode(OpenAIChatChoice.self, from: Data(#"{"index":0,"delta":{}}"#.utf8)).value
        #expect(absent.finishReason == .absent)
        let null = try WireCodec.decode(
            OpenAIChatChoice.self, from: Data(#"{"index":0,"delta":{},"finish_reason":null}"#.utf8)
        ).value
        #expect(null.finishReason == .null)
        #expect(throws: WireCodingError.self) {
            try WireCodec.decode(OpenAIChatChoice.self, from: Data(#"{"index":0,"delta":{},"finish_reason":1}"#.utf8))
        }

        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try OpenAIResponsesChatCompletions.terminalStatus(responseBody: Data("[]".utf8))
        }
        #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
            _ = try OpenAIResponsesChatCompletions.terminalStatus(responseBody: Data("{".utf8))
        }
        for invalidJSON: Any in [Date(), Double.nan] {
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidResponse) {
                _ = try chatData(invalidJSON)
            }
        }

        let failedBase: [String: Any] = [
            "id": "resp_failed",
            "object": "response",
            "status": "failed",
            "error": ["code": "server_error", "message": "safe"],
        ]
        var invalidOutput = failedBase
        invalidOutput["output"] = "not-an-array"
        #expect(!validResponsesFailedResponse(invalidOutput))
        var invalidUsage = failedBase
        invalidUsage["usage"] = "not-an-object"
        #expect(!validResponsesFailedResponse(invalidUsage))
        #expect(!validResponsesFailedResponse(failedBase, expectedID: "other"))
        #expect(validResponsesFailedResponse(failedBase))

        // Providers may fail a response without filling the error object;
        // the terminal is still well formed and must stay parseable.
        var nullError = failedBase
        nullError["error"] = NSNull()
        #expect(validResponsesFailedResponse(nullError))
        var absentError = failedBase
        absentError.removeValue(forKey: "error")
        #expect(validResponsesFailedResponse(absentError))
        // A present but malformed error object is still a rejection.
        var codelessError = failedBase
        codelessError["error"] = ["message": "no code"]
        #expect(!validResponsesFailedResponse(codelessError))
        var messagelessError = failedBase
        messagelessError["error"] = ["code": "server_error"]
        #expect(!validResponsesFailedResponse(messagelessError))
        var scalarError = failedBase
        scalarError["error"] = "boom"
        #expect(!validResponsesFailedResponse(scalarError))

        #expect(ResponsesPublicStreamSession.providerFailureCode(NSNull()) == "server_error")
        #expect(
            ResponsesPublicStreamSession.providerFailureCode(
                ["code": "rate_limited", "message": "slow down"]
            ) == "server_error"
        )
        #expect(
            ResponsesPublicStreamSession.providerFailureCode(
                ["code": "context_length_exceeded", "message": "too long"]
            ) == "context_length_exceeded"
        )

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try responsesStreamObject(Data("[]".utf8))
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try responsesStreamObject(Data("{".utf8))
        }
        for invalidJSON: Any in [Date(), Double.nan] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try responsesStreamData(invalidJSON)
            }
        }
        #expect(try String(data: chatData("fragment"), encoding: .utf8) == #""fragment""#)
        #expect(try String(data: responsesStreamData("fragment"), encoding: .utf8) == #""fragment""#)
        #expect(try String(data: responsesStreamData(1), encoding: .utf8) == "1")

        var fragments = ChatCompletionFragmentBuffer()
        #expect(fragments.finalizeText(choiceIndex: 0).isEmpty)
        #expect(fragments.finalizeArguments(choiceIndex: 0, toolIndex: 0).isEmpty)
    }
}

extension OpenAICoverageEdgeTests {
    @Test("Provider transport sanitizer defaults missing output to an empty array")
    func providerTransportMissingOutput() throws {
        let response = try OpenAIResponsesPublicSanitizer.providerTransportResponse([
            "id": "resp_without_output",
            "object": "response",
            "status": "completed",
            "usage": [String: Int](),
        ])

        let output = try #require(response["output"] as? [[String: Any]])
        #expect(output.isEmpty)
    }

    @Test("Public sanitizer accepts every public family and rejects malformed variants")
    func sanitizerMatrix() throws {
        let shell = try OpenAIResponsesPublicSanitizer.responseShell(provider: [
            "id": "resp_shell",
            "object": "response",
            "created_at": 1,
            "completed_at": NSNull(),
            "incomplete_details": ["reason": "unknown-provider-reason"],
        ])
        #expect(shell["incomplete_details"] is NSNull)
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.responseShell(provider: [:])
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.responseShell(provider: [
                "id": "resp", "object": "chat.completion",
            ])
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.responseShell(provider: [
                "id": "resp", "created_at": -1,
            ])
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.responseShell(provider: [
                "id": "resp", "completed_at": "later",
            ])
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.responseShell(provider: [
                "id": "resp", "incomplete_details": "bad",
            ])
        }

        let usage: [String: Any] = [
            "input_tokens": 2,
            "output_tokens": 3,
            "total_tokens": 5,
            "input_tokens_details": NSNull(),
            "output_tokens_details": ["reasoning_tokens": 1, "private": 9],
        ]
        let completed = try OpenAIResponsesPublicSanitizer.providerTransportResponse([
            "id": "resp_completed",
            "object": "response",
            "status": "completed",
            "output": [],
            "usage": usage,
        ])
        #expect(completed["usage"] is [String: Any])
        for code in ["context_length_exceeded", "private_code"] {
            let failed = try OpenAIResponsesPublicSanitizer.providerTransportResponse([
                "id": "resp_failed_\(code)",
                "object": "response",
                "status": "failed",
                "output": [],
                "error": ["code": code, "message": "private"],
            ])
            let publicError = try #require(failed["error"] as? [String: String])
            #expect(publicError["message"] == "Internal server error")
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.providerTransportResponse([
                "id": "resp", "status": "queued",
            ])
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.providerTransportResponse([
                "id": "resp", "status": "completed", "output": "bad", "usage": usage,
            ])
        }

        let refusal = try OpenAIResponsesPublicSanitizer.contentPart([
            "type": "refusal", "refusal": "No",
        ])
        #expect(refusal["refusal"] as? String == "No")
        for malformed: Any in [
            ["type": "refusal"],
            ["type": "unknown"],
            ["type": "output_text", "text": 1],
            "bad",
        ] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesPublicSanitizer.contentPart(malformed)
            }
        }
        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.summaryPart(["type": "summary_text"])
        }

        let annotations: [[String: Any]] = [
            [
                "type": "url_citation", "title": "T", "url": "https://example.com",
                "start_index": 0, "end_index": 1,
            ],
            ["type": "file_citation", "file_id": "f", "filename": "a", "index": 0],
            [
                "type": "container_file_citation", "container_id": "c", "file_id": "f",
                "filename": "a", "start_index": 0, "end_index": 1,
            ],
            ["type": "file_path", "file_id": "f", "index": 0],
        ]
        for annotation in annotations {
            #expect(try OpenAIResponsesPublicSanitizer.annotation(annotation)["type"] != nil)
        }
        for malformed: Any in [
            ["type": "unknown"],
            ["type": "file_path", "file_id": 1],
            ["type": "file_path", "index": -1],
            "bad",
        ] {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesPublicSanitizer.annotation(malformed)
            }
        }

        let message: [String: Any] = [
            "id": "msg",
            "type": "message",
            "role": "assistant",
            "status": "completed",
            "phase": "commentary",
            "content": [
                [
                    "type": "output_text",
                    "text": "A",
                    "annotations": annotations,
                    "logprobs": [
                        [
                            "token": "A",
                            "logprob": -0.1,
                            "bytes": [65],
                            "top_logprobs": [["token": "B", "logprob": -1.0, "bytes": NSNull()]],
                        ]
                    ],
                ]
            ],
            "internal_chat_message_metadata_passthrough": ["turn_id": "turn"],
        ]
        #expect(try OpenAIResponsesPublicSanitizer.item(message)["id"] as? String == "msg")

        let reasoning: [String: Any] = [
            "id": "rs",
            "type": "reasoning",
            "summary": [["type": "summary_text", "text": "S"]],
            "content": [
                ["type": "reasoning_text", "text": "R"],
                ["type": "provider_private", "text": "drop"],
            ],
            "encrypted_content": NSNull(),
        ]
        #expect(try OpenAIResponsesPublicSanitizer.item(reasoning)["id"] as? String == "rs")
        let filteredReasoning = try OpenAIResponsesPublicSanitizer.item([
            "id": "rs_filtered",
            "type": "reasoning",
            "summary": [["type": "provider_private", "text": "drop"]],
        ])
        #expect((filteredReasoning["summary"] as? [[String: Any]])?.isEmpty == true)

        let function: [String: Any] = [
            "id": "fc", "type": "function_call", "call_id": "call", "name": "read",
            "arguments": "{}", "namespace": "tools",
        ]
        #expect(try OpenAIResponsesPublicSanitizer.item(function)["namespace"] as? String == "tools")

        for action: [String: Any] in [
            ["type": "search", "query": "q", "queries": ["q", "r"]],
            ["type": "open_page", "url": "https://example.com"],
            ["type": "find_in_page", "url": "https://example.com", "pattern": "x"],
        ] {
            let item: [String: Any] = [
                "id": "ws_\(action["type"] as? String ?? "")",
                "type": "web_search_call",
                "action": action,
            ]
            #expect(try OpenAIResponsesPublicSanitizer.item(item)["action"] != nil)
        }

        let malformedItems: [[String: Any]] = [
            [:],
            ["type": "unknown"],
            ["type": "message", "id": "msg", "role": "user", "content": []],
            [
                "type": "message", "id": "msg", "role": "assistant", "content": [],
                "phase": "private",
            ],
            [
                "type": "message", "id": "msg", "role": "assistant", "content": [],
                "internal_chat_message_metadata_passthrough": "bad",
            ],
            [
                "type": "message", "id": "msg", "role": "assistant", "content": [],
                "internal_chat_message_metadata_passthrough": ["turn_id": 1],
            ],
            ["type": "reasoning", "id": "", "summary": []],
            ["type": "reasoning", "id": "rs", "summary": "bad"],
            ["type": "reasoning", "id": "rs", "summary": [["type": "summary_text"]]],
            [
                "type": "reasoning", "id": "rs", "summary": [],
                "encrypted_content": 1,
            ],
            ["type": "function_call", "id": "fc"],
            [
                "type": "function_call", "id": "fc", "call_id": "call", "name": "read",
                "arguments": "{}", "namespace": 1,
            ],
            ["type": "web_search_call", "id": ""],
            ["type": "web_search_call", "id": "ws", "action": "bad"],
            [
                "type": "web_search_call", "id": "ws",
                "action": ["type": "search", "query": 1],
            ],
            [
                "type": "web_search_call", "id": "ws",
                "action": ["type": "search", "queries": [1]],
            ],
            [
                "type": "web_search_call", "id": "ws",
                "action": ["type": "open_page", "url": 1],
            ],
            [
                "type": "web_search_call", "id": "ws",
                "action": ["type": "find_in_page", "pattern": 1],
            ],
            [
                "type": "web_search_call", "id": "ws",
                "action": ["type": "private"],
            ],
            ["type": "message", "id": "msg", "role": "assistant", "content": [], "status": "bad"],
        ]
        for item in malformedItems {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesPublicSanitizer.item(item)
            }
        }

        let malformedTextParts: [[String: Any]] = [
            ["type": "output_text", "text": "A", "annotations": "bad"],
            ["type": "output_text", "text": "A", "logprobs": "bad"],
            [
                "type": "output_text", "text": "A",
                "logprobs": [["token": "A", "logprob": true]],
            ],
            [
                "type": "output_text", "text": "A",
                "logprobs": [["token": "A", "logprob": -0.1, "bytes": [256]]],
            ],
            [
                "type": "output_text", "text": "A",
                "logprobs": [["token": "A", "logprob": -0.1, "top_logprobs": "bad"]],
            ],
        ]
        for part in malformedTextParts {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesPublicSanitizer.contentPart(part)
            }
        }

        let malformedUsageValues: [Any] = [
            "bad",
            ["input_tokens": -1],
            ["input_tokens_details": "bad"],
            ["input_tokens_details": ["cached_tokens": -1]],
        ]
        for badUsage in malformedUsageValues {
            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesPublicSanitizer.providerTransportResponse([
                    "id": "resp", "status": "completed", "output": [], "usage": badUsage,
                ])
            }
        }
    }
}

// swiftlint:enable function_body_length
