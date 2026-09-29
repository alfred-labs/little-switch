import Foundation
import LittleSwitchCommon
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses portable provenance")
struct ResponsesPortableProvenanceTests {
    @Test("Two providers never share private reasoning")
    func exactProvider() throws {
        let provider = UUID()
        let origin = provider
        let sibling = UUID()
        let original: [String: Any] = [
            "type": "reasoning", "id": "rs_private", "encrypted_content": "synthetic-opaque",
            "summary": [["type": "summary_text", "text": "private"]],
            "future_number": try JSONValue.parse(Data("9007199254740993".utf8)),
        ]
        let wrapped = try ResponsesProviderState.tagged(original, providerID: origin)
        let encoded = try #require(wrapped["encrypted_content"] as? String)
        let payload = try responsesStreamObject(Data(encoded.utf8))
        #expect(nonnegativeResponsesIndex(payload["version"]) == 1)
        #expect(payload["provider_id"] as? String == provider.uuidString)
        #expect(payload["account_id"] == nil)
        let durable = try responsesStreamData(["input": [wrapped]])
        let own = try ResponsesProviderState.normalize(body: durable, providerID: origin)
        #expect(try own == responsesStreamData(["input": [original]]))
        for destination in [nil, sibling] {
            let filtered = try ResponsesProviderState.normalize(body: durable, providerID: destination)
            #expect(try filtered == responsesStreamData(["input": []]))
        }
        #expect(try ResponsesProviderState.normalize(body: durable, providerID: origin) == own)
    }

    @Test("Version one belongs only to the original provider")
    func legacy() throws {
        let provider = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let original: [String: Any] = ["type": "reasoning", "id": "rs_legacy", "encrypted_content": "private"]
        var wrapped = original
        wrapped["encrypted_content"] =
            #"{"type":"little_switch_reasoning","version":1,"provider_id":"11111111-2222-3333-4444-555555555555","item":"#
            + #"{"type":"reasoning","id":"rs_legacy","encrypted_content":"private"}}"#
        let body = try responsesStreamData(["input": [wrapped]])
        let legacy = provider
        #expect(
            try ResponsesProviderState.normalize(body: body, providerID: legacy)
                == responsesStreamData(["input": [original]]))
        let replacement = UUID()
        #expect(
            try ResponsesProviderState.normalize(body: body, providerID: replacement)
                == responsesStreamData(["input": []]))
    }

    @Test("Malformed legacy envelopes fail closed")
    func malformed() throws {
        let identifier = UUID().uuidString
        let valid: [String: Any] = [
            "type": "little_switch_reasoning", "version": 2, "provider_id": identifier,
            "account_id": identifier, "item": ["type": "reasoning", "id": "rs_x"],
        ]
        var missing = valid
        missing.removeValue(forKey: "account_id")
        var boolean = valid
        boolean["version"] = true
        var unsupported = valid
        unsupported["version"] = 3
        var invalid = valid
        invalid["account_id"] = "invalid"
        var actionable = valid
        actionable["item"] = ["type": "function_call", "name": "run"]
        for payload in [missing, boolean, unsupported, invalid, actionable] {
            let envelope = try #require(String(data: responsesStreamData(payload), encoding: .utf8))
            let body = try responsesStreamData(["input": [["type": "reasoning", "encrypted_content": envelope]]])
            #expect(throws: ResponsesProviderState.Error.invalidState) {
                try ResponsesProviderState.normalize(body: body, providerID: nil)
            }
        }
    }

    @Test("Portable expansion admits only the selected provider's private state")
    func portableExpansion() throws {
        let provider = UUID()
        let original: [String: Any] = ["type": "reasoning", "id": "rs_a", "encrypted_content": "private"]
        let wrapped = try ResponsesProviderState.tagged(original, providerID: provider)
        let opaque: [String: Any] = ["type": "compaction", "encrypted_content": "native-checkpoint"]
        let checkpoint = try ResponsesCompactionFixture.owned(retained: [opaque, wrapped])
        let body = try responsesStreamData(["model": "route", "input": [checkpoint], "metadata": ["keep": "yes"]])
        let summary: [String: Any] = [
            "type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Earlier work."]],
        ]
        for destination in [nil, provider, UUID()] {
            let input =
                if destination == nil { [opaque, summary] } else if destination == provider {
                    [summary, original]
                } else { [summary] }
            let expected = try responsesStreamData(["model": "route", "input": input, "metadata": ["keep": "yes"]])
            #expect(try ResponsesProviderState.normalize(body: body, providerID: destination) == expected)
        }
    }

    @Test("A different provider compacts portable context while retaining the owner's exact state")
    func compactionReturn() throws {
        let provider = UUID()
        let owner = provider
        let sibling = UUID()
        let original: [String: Any] = [
            "type": "reasoning", "id": "rs_owner", "encrypted_content": "private-ciphertext",
            "summary": [["type": "summary_text", "text": "owner-only-summary"]],
        ]
        let wrapped = try ResponsesProviderState.tagged(original, providerID: owner)
        let plan = try #require(
            try ResponsesCompactionPlan.prepare(
                body: ResponsesCompactionFixture.request(items: [wrapped, ResponsesCompactionFixture.message]),
                providerID: sibling))
        let sent = try #require(String(data: plan.summaryRequest(model: "sibling", stream: false), encoding: .utf8))
        #expect(!sent.contains("private-ciphertext"))
        #expect(!sent.contains("owner-only-summary"))
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response())
        let payload = try ResponsesCompactionFixture.payload(result)
        #expect(try responsesStreamData(payload["retained"] as Any) == responsesStreamData([wrapped]))
        let replay = try responsesStreamData(["input": [ResponsesCompactionFixture.object(result.itemJSON)]])
        let restored = try responsesStreamObject(ResponsesProviderState.normalize(body: replay, providerID: owner))
        let items = try #require(restored["input"] as? [[String: Any]])
        #expect(items.contains { NSDictionary(dictionary: $0) == NSDictionary(dictionary: original) })
    }
}
