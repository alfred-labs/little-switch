import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Chat reasoning carrier")
struct ChatReasoningCarrierTests {
    @Test("Absent and null fields do not invent a reasoning item")
    func absentFields() throws {
        let message: JSONObject = [
            "content": .string("Visible"), "reasoning": .null, "reasoning_content": .null,
        ]
        let fields = try ResponsesChatCompletionsReasoning.wireFields(in: message)
        #expect(fields.isEmpty)
        #expect(try ResponsesChatCompletionsReasoning.item(message: fields, responseID: "resp_none") == nil)
    }

    @Test("Carrier preserves empty and Unicode values without merging field spellings")
    func exactFields() throws {
        let fields = ["reasoning": "", "reasoning_content": "  SYNTHETIC α\nβ  "]
        let item = try #require(try ResponsesChatCompletionsReasoning.item(message: fields, responseID: "resp_exact"))
        #expect(try ResponsesChatCompletionsReasoning.fields(from: item) == fields)
        #expect(item["id"] as? String == "rs_resp_exact")
        #expect((item["summary"] as? [Any])?.isEmpty == true)
        #expect(try !chatReasoningText(chatJSONData(item)).contains("SYNTHETIC"))
    }

    @Test("Internal Chat turns reopen only their own newly tagged state")
    func taggedInternalReplay() throws {
        let origin = UUID()
        let fields = chatReasoningFields()
        let tagged = try #require(
            try ResponsesChatCompletionsReasoning.item(message: fields, responseID: "resp_internal", providerID: origin)
        )
        #expect(try ResponsesChatCompletionsReasoning.fields(from: tagged, providerID: origin) == fields)
        #expect(try ResponsesChatCompletionsReasoning.fields(from: tagged, providerID: UUID()) == nil)
        #expect(try ResponsesChatCompletionsReasoning.fields(from: tagged) == nil)
        let prepared = try OpenAIResponsesChatCompletions.prepare(
            body: chatReasoningHistory([
                tagged, ["type": "message", "role": "assistant", "content": "Visible"],
            ]),
            targetModel: "provider-model",
            providerID: origin
        )
        let messages = try chatReasoningMessages(prepared.upstreamBody)
        #expect(messages.first?["reasoning"] as? String == fields["reasoning"])
        #expect(messages.first?["reasoning_content"] as? String == fields["reasoning_content"])
    }

    @Test("Unrecognized ciphertext and nonreasoning objects remain opaque")
    func foreignState() throws {
        let items: [[String: Any]] = [
            ["type": "message", "encrypted_content": "opaque"],
            ["type": "reasoning"],
            ["type": "reasoning", "encrypted_content": "opaque"],
            ["type": "reasoning", "encrypted_content": "[]"],
            ["type": "reasoning", "encrypted_content": #"{"type":"another_provider"}"#],
        ]
        for item in items {
            #expect(try ResponsesChatCompletionsReasoning.fields(from: item) == nil)
        }
    }

    @Test("Malformed recognized carriers fail without forwarding their payload")
    func malformedCarrier() throws {
        let encoded = try chatJSONData(["reasoning": "synthetic"]).base64EncodedString()
        let payloads: [[String: Any]] = [
            ["data": encoded], ["version": true, "data": encoded], ["version": 2, "data": encoded],
            ["version": 1], ["version": 1, "data": 7], ["version": 1, "data": "not base64"],
            ["version": 1, "data": Data("not JSON".utf8).base64EncodedString()],
            ["version": 1, "data": try chatJSONData([:]).base64EncodedString()],
            ["version": 1, "data": try chatJSONData(["other": "value"]).base64EncodedString()],
            ["version": 1, "data": try chatJSONData(["reasoning": NSNull()]).base64EncodedString()],
        ]
        for payload in payloads {
            var carrier = payload
            carrier["type"] = "little_switch_chat_reasoning"
            let item: [String: Any] = [
                "type": "reasoning", "encrypted_content": try chatReasoningText(chatJSONData(carrier)),
            ]
            #expect(throws: OpenAIResponsesChatCompletions.Error.invalidRequest) {
                _ = try ResponsesChatCompletionsReasoning.fields(from: item)
            }
        }
    }

    @Test("Native egress restores only tagged native state and preserves previously admitted raw state")
    func nativeEgress() throws {
        let origin = UUID()
        let raw: [String: Any] = [
            "type": "reasoning", "id": "rs_native", "encrypted_content": "opaque-native", "summary": [],
        ]
        let own = try ResponsesProviderState.tagged(raw, providerID: origin)
        let foreign = try ResponsesProviderState.tagged(raw, providerID: UUID())
        let chat = try #require(
            try ResponsesChatCompletionsReasoning.item(message: chatReasoningFields(), responseID: "resp_chat"))
        let taggedChat = try ResponsesProviderState.tagged(chat, providerID: origin)
        let history = try chatReasoningHistory([raw, own, foreign, chat, taggedChat])
        let filtered = try ResponsesChatCompletionsReasoning.nativeRequestBody(history, providerID: origin)
        let expected = try chatReasoningHistory([raw, raw])
        #expect(try chatJSONObject(filtered) as NSDictionary == chatJSONObject(expected) as NSDictionary)
        #expect(
            try ResponsesChatCompletionsReasoning.fields(from: taggedChat, providerID: origin) == chatReasoningFields())
        let unchanged = try chatReasoningHistory([raw])
        #expect(try ResponsesChatCompletionsReasoning.nativeRequestBody(unchanged, providerID: origin) == unchanged)
        let textInput = Data(#"{ "model": "route", "input": "Hello" }"#.utf8)
        #expect(try ResponsesChatCompletionsReasoning.nativeRequestBody(textInput, providerID: origin) == textInput)
    }
}
