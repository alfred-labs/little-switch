import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses provider state")
struct ResponsesProviderStateTests {
    let providerID = UUID(uuid: (148, 189, 85, 158, 137, 64, 79, 176, 166, 35, 232, 67, 130, 209, 65, 137))

    @Test("OpenAI to custom to OpenAI keeps the original durable reasoning exactly")
    func nativeRoundTrip() throws {
        let durable = Data(
            #"{"model":"custom","input":[{"type":"reasoning","id":"rs_native","encrypted_content":"opaque","summary":[]},{"role":"user","content":"Continue"}]}"#
                .utf8)
        let customCopy = try ResponsesProviderState.normalize(body: durable, providerID: providerID)
        let custom = try responsesStreamObject(customCopy)
        #expect((custom["input"] as? [[String: Any]])?.count == 1)
        #expect(try ResponsesProviderState.normalize(body: durable, providerID: nil) == durable)
    }

    @Test("Only the origin provider receives the original custom state")
    func ownedRoundTrip() throws {
        let original = Data(
            #"{"output":[{"type":"reasoning","id":"rs_custom","summary":[],"encrypted_content":null}]}"#.utf8)
        let tagged = try responsesStreamObject(ResponsesProviderState.tag(response: original, providerID: providerID))
        let items = try #require(tagged["output"] as? [[String: Any]])
        let durable = try responsesStreamData(["input": items])
        let restored = try responsesStreamObject(
            ResponsesProviderState.normalize(body: durable, providerID: providerID))
        #expect(
            NSDictionary(dictionary: restored)
                == NSDictionary(dictionary: [
                    "input": [
                        [
                            "type": "reasoning", "id": "rs_custom", "summary": [], "encrypted_content": NSNull(),
                        ]
                    ]
                ]))
        for destination in [nil, UUID()] {
            let copy = try responsesStreamObject(
                ResponsesProviderState.normalize(body: durable, providerID: destination))
            #expect((copy["input"] as? [[String: Any]])?.isEmpty == true)
        }
    }

    @Test("Tagging visits response output fields, never nested tool arguments or input")
    func taggingBoundaries() throws {
        for text in [
            "not-json", "[]", #"{"input":[{"type":"reasoning"}]}"#,
            #"{"item":{"type":"function_call","arguments":"reasoning"}}"#,
        ] {
            let bytes = Data(text.utf8)
            #expect(try ResponsesProviderState.tag(response: bytes, providerID: providerID) == bytes)
        }
        let event = Data(#"{"item":{"type":"reasoning","id":"rs","summary":[]}}"#.utf8)
        let tagged = try responsesStreamObject(ResponsesProviderState.tag(response: event, providerID: providerID))
        #expect(
            ((tagged["item"] as? [String: Any])?["encrypted_content"] as? String)?.contains("little_switch_reasoning")
                == true)
    }

    @Test(
        "Malformed provenance cannot be silently accepted",
        arguments: [
            #"{"type":"little_switch_reasoning","version":2,"provider_id":"invalid","item":{}}"#,
            #"{"type":"little_switch_reasoning","version":true,"provider_id":"94BD559E-8940-4FB0-A623-E84382D14189","item":{"type":"reasoning"}}"#,
            #"{"type":"little_switch_reasoning","version":1,"provider_id":"invalid","item":{"type":"reasoning"}}"#,
            #"{"type":"little_switch_reasoning","version":1,"provider_id":"94BD559E-8940-4FB0-A623-E84382D14189","item":{"type":"message"}}"#,
        ])
    func malformedProvenance(payload: String) throws {
        let body = try responsesStreamData(["input": [["type": "reasoning", "encrypted_content": payload]]])
        #expect(throws: ResponsesProviderState.Error.invalidState) {
            try ResponsesProviderState.normalize(body: body, providerID: providerID)
        }
    }

    @Test(
        "The legacy Ollama ID filter remains narrow",
        arguments: [
            ("rs_1", true), ("rs_resp_000001", true), (" rs_123 ", true),
            ("rs_", false), ("rs_resp_", false), ("rs_1234567", false), ("rs_1x", false), ("other_1", false),
        ])
    func legacyIDs(id: String, foreign: Bool) throws {
        #expect(
            try ResponsesProviderState.isForeignReasoning(["type": "reasoning", "id": id], providerID: nil) == foreign)
    }

    @Test("A portable checkpoint keeps foreign state only for its native return")
    func normalizeDropsNestedForeignCheckpoint() throws {
        let foreign: [String: Any] = ["type": "compaction", "encrypted_content": "nested-foreign"]
        let owned = try ResponsesCompactionFixture.owned(
            summary: "Earlier work.", retained: [foreign, ResponsesCompactionFixture.message])
        let body = try ResponsesCompactionFixture.data(["model": "route", "input": [owned]])
        let normalized = try responsesStreamObject(
            ResponsesProviderState.normalize(body: body, providerID: providerID))
        let input = try #require(normalized["input"] as? [[String: Any]])
        let text = try ResponsesCompactionJSON.text(input)
        #expect(text.contains("Earlier work."))
        #expect(text.contains("Keep working."))
        #expect(!text.contains("nested-foreign"))
    }

    @Test("Native configuration controls are scoped to the native request")
    func configurationAndPlainInput() throws {
        let plain = Data(#"{"input":"Hello"}"#.utf8)
        #expect(try ResponsesProviderState.normalize(body: plain, providerID: providerID) == plain)
        let control = Data(#"{"input":[{"type":"configuration_update","reasoning":{"effort":"high"}}]}"#.utf8)
        #expect(try ResponsesProviderState.normalize(body: control, providerID: nil) == control)
        let filtered = try responsesStreamObject(
            ResponsesProviderState.normalize(body: control, providerID: providerID))
        #expect((filtered["input"] as? [[String: Any]])?.isEmpty == true)
        #expect(try !ResponsesProviderState.isForeignReasoning(["type": "message"], providerID: providerID))
        #expect(try ResponsesProviderState.degradedBody(plain) == plain)
        let foreign = Data(#"{"input":[{"type":"compaction","encrypted_content":"opaque"}]}"#.utf8)
        let degraded = try responsesStreamObject(try ResponsesProviderState.degradedBody(foreign))
        #expect(
            try ResponsesCompactionJSON.text(try #require(degraded["input"] as? [[String: Any]])).contains(
                ResponsesProviderState.degradationNotice))
    }
}
