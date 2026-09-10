import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("OpenAI Responses sanitizer null fields")
struct ResponsesSanitizerNullFieldTests {
    @Test("A reasoning item keeps its shape when the provider sends a null status")
    func nullReasoningStatus() throws {
        let item: [String: Any] = [
            "id": "rs_1",
            "type": "reasoning",
            "summary": [],
            "content": [["type": "reasoning_text", "text": "thinking"]],
            "encrypted_content": NSNull(),
            "status": NSNull(),
        ]

        let sanitized = try OpenAIResponsesPublicSanitizer.item(item)

        #expect(sanitized["type"] as? String == "reasoning")
        #expect(sanitized["status"] == nil)
        #expect((sanitized["content"] as? [[String: Any]])?.count == 1)
    }

    @Test("A message item keeps its shape when the provider sends a null phase")
    func nullMessagePhase() throws {
        let item: [String: Any] = [
            "id": "msg_1",
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": "hi"]],
            "status": "completed",
            "phase": NSNull(),
        ]

        let sanitized = try OpenAIResponsesPublicSanitizer.item(item)

        #expect(sanitized["type"] as? String == "message")
        #expect(sanitized["phase"] == nil)
        #expect(sanitized["status"] as? String == "completed")
    }

    @Test("An output text part with null annotations and logprobs is accepted")
    func nullContentPartCollections() throws {
        let item: [String: Any] = [
            "id": "msg_3",
            "type": "message",
            "role": "assistant",
            "content": [
                [
                    "type": "output_text",
                    "text": "hi",
                    "annotations": NSNull(),
                    "logprobs": NSNull(),
                ]
            ],
        ]

        let sanitized = try OpenAIResponsesPublicSanitizer.item(item)
        let parts = sanitized["content"] as? [[String: Any]]

        #expect(parts?.count == 1)
        #expect((parts?.first?["annotations"] as? [[String: Any]])?.isEmpty == true)
        #expect((parts?.first?["logprobs"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("Malformed annotations and logprobs are still rejected")
    func malformedContentPartCollectionsRejected() {
        for key in ["annotations", "logprobs"] {
            var part: [String: Any] = ["type": "output_text", "text": "hi"]
            part[key] = "not-a-list"
            let item: [String: Any] = [
                "id": "msg_4",
                "type": "message",
                "role": "assistant",
                "content": [part],
            ]

            #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
                _ = try OpenAIResponsesPublicSanitizer.item(item)
            }
        }
    }

    @Test("A non-null invalid status is still rejected")
    func invalidStatusStillRejected() {
        let item: [String: Any] = [
            "id": "rs_2",
            "type": "reasoning",
            "summary": [],
            "status": "bogus",
        ]

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.item(item)
        }
    }

    @Test("A non-null invalid phase is still rejected")
    func invalidPhaseStillRejected() {
        let item: [String: Any] = [
            "id": "msg_2",
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": "hi"]],
            "phase": "bogus",
        ]

        #expect(throws: OpenAIResponsesWebSearch.Error.invalidResponse) {
            _ = try OpenAIResponsesPublicSanitizer.item(item)
        }
    }
}
