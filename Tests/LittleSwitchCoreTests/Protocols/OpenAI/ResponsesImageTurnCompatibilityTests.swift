import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses image turn compatibility")
struct ResponsesImageTurnCompatibilityTests {
    private let image = "data:image/png;base64,iVBORw0KGgo="

    private func imageInput() -> [Any] {
        [
            [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": "What is this?"],
                    ["type": "input_image", "image_url": image],
                ],
            ]
        ]
    }

    private func textInput() -> [Any] {
        [
            [
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": "Hello."]],
            ]
        ]
    }

    @Test("An image turn loses reasoning effort and gains a budget")
    func reshapesImageTurn() throws {
        let reshaped = try #require(
            ResponsesImageTurnCompatibility.rewritten([
                "input": imageInput(),
                "reasoning": ["effort": "max", "summary": "detailed"],
            ])
        )
        let reasoning = try #require(reshaped["reasoning"] as? [String: Any])
        #expect(reasoning["effort"] == nil)
        #expect(reasoning["summary"] as? String == "detailed")
        #expect(
            reshaped["max_output_tokens"] as? Int
                == ResponsesImageTurnCompatibility.maximumOutputTokens
        )
    }

    @Test("A declared budget survives, and effort alone is enough to reshape")
    func respectsDeclaredBudget() throws {
        let reshaped = try #require(
            ResponsesImageTurnCompatibility.rewritten([
                "input": imageInput(),
                "reasoning": ["effort": "low"],
                "max_output_tokens": 512,
            ])
        )
        #expect(reshaped["max_output_tokens"] as? Int == 512)
        #expect((reshaped["reasoning"] as? [String: Any])?["effort"] == nil)

        let nullBudget = try #require(
            ResponsesImageTurnCompatibility.rewritten([
                "input": imageInput(),
                "max_output_tokens": NSNull(),
            ])
        )
        #expect(
            nullBudget["max_output_tokens"] as? Int
                == ResponsesImageTurnCompatibility.maximumOutputTokens
        )
    }

    @Test("Reasoning without an effort field is left as it is")
    func keepsEffortlessReasoning() throws {
        let reshaped = try #require(
            ResponsesImageTurnCompatibility.rewritten([
                "input": imageInput(),
                "reasoning": ["summary": "detailed"],
            ])
        )
        #expect(reshaped["reasoning"] as? [String: String] == ["summary": "detailed"])
        #expect(reshaped["max_output_tokens"] is Int)
    }

    @Test("Nothing to do leaves the request alone")
    func leavesOtherTurnsAlone() {
        #expect(ResponsesImageTurnCompatibility.rewritten(["input": textInput()]) == nil)
        #expect(ResponsesImageTurnCompatibility.rewritten(["input": "plain"]) == nil)
        #expect(
            ResponsesImageTurnCompatibility.rewritten([
                "input": [["type": "message", "role": "user", "content": "text"]]
            ]) == nil
        )
        #expect(ResponsesImageTurnCompatibility.rewritten([:]) == nil)
        // An image turn that already answers both conditions needs no rewrite.
        #expect(
            ResponsesImageTurnCompatibility.rewritten([
                "input": imageInput(),
                "reasoning": ["summary": "detailed"],
                "max_output_tokens": 256,
            ]) == nil
        )
    }

    @Test("Native normalization applies the reshape only to image turns")
    func appliesOnNativeNormalization() throws {
        let body = try responseData([
            "model": "m", "stream": true, "input": imageInput(),
            "reasoning": ["effort": "max"],
        ])
        let normalized = try OpenAIResponsesNativeNamespacing.normalize(body)
        let viaNormalize = try #require(
            try JSONSerialization.jsonObject(with: normalized.body) as? [String: Any]
        )
        #expect((viaNormalize["reasoning"] as? [String: Any])?["effort"] == nil)
        #expect(viaNormalize["max_output_tokens"] is Int)

        let plain = try responseData(["model": "m", "stream": true, "input": textInput()])
        #expect(try OpenAIResponsesNativeNamespacing.normalize(plain).body == plain)
    }
}
