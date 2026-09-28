import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Single-provider Responses provenance")
struct ResponsesSingleProviderProvenanceTests {
    @Test("New reasoning provenance has no account identity")
    func providerOnly() throws {
        let providerID = UUID()
        let reasoning: [String: Any] = ["type": "reasoning", "id": "r", "encrypted_content": "opaque"]
        let item = try ResponsesProviderState.tagged(reasoning, providerID: providerID)
        let encoded = try #require(item["encrypted_content"] as? String)
        let payload = try responsesStreamObject(Data(encoded.utf8))
        #expect(nonnegativeResponsesIndex(payload["version"]) == 1)
        #expect(payload["provider_id"] as? String == providerID.uuidString)
        #expect(payload["account_id"] == nil)
        let restored = try ResponsesProviderState.restoreTaggedReasoning(item, providerID: providerID)
        #expect(NSDictionary(dictionary: try #require(restored)) == NSDictionary(dictionary: reasoning))
    }

    @Test("Experimental reasoning restores only the historical primary identity", arguments: [false, true])
    func legacyPrimary(foreign: Bool) throws {
        let providerID = UUID()
        let accountID = foreign ? UUID() : providerID
        let reasoning: [String: Any] = ["type": "reasoning", "id": "r", "encrypted_content": "opaque"]
        let payload = try responsesStreamData([
            "type": "little_switch_reasoning", "version": 2, "provider_id": providerID.uuidString,
            "account_id": accountID.uuidString, "item": reasoning,
        ])
        let item: [String: Any] = [
            "type": "reasoning", "encrypted_content": try #require(String(data: payload, encoding: .utf8)),
        ]
        let restored = try ResponsesProviderState.restoreTaggedReasoning(item, providerID: providerID)
        if foreign {
            #expect(restored == nil)
        } else {
            #expect(NSDictionary(dictionary: try #require(restored)) == NSDictionary(dictionary: reasoning))
        }
    }
}
