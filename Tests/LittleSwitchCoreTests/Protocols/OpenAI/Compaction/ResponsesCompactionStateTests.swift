import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Compaction preserves foreign provider state")
struct ResponsesCompactionStateTests {
    @Test("Native reasoning survives custom compaction without entering the custom summary prompt")
    func nativeReasoning() throws {
        let provider = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let native: [String: Any] = [
            "type": "reasoning", "id": "rs_native_opaque", "encrypted_content": "native-ciphertext",
            "summary": [["type": "summary_text", "text": "Native private rationale"]],
        ]
        let plan = try #require(
            try ResponsesCompactionPlan.prepare(
                body: ResponsesCompactionFixture.request(items: [native, ResponsesCompactionFixture.message]),
                providerID: provider))
        let request = try plan.summaryRequest(model: "custom", stream: false)
        let text = try #require(String(bytes: request, encoding: .utf8))
        #expect(!text.contains("native-ciphertext"))
        #expect(!text.contains("Native private rationale"))
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response())
        let retained = try #require(try ResponsesCompactionFixture.payload(result)["retained"] as? [[String: Any]])
        #expect(try ResponsesCompactionFixture.data(retained) == ResponsesCompactionFixture.data([native]))
        let replay = try ResponsesCompactionFixture.data(["input": [ResponsesCompactionFixture.object(result.itemJSON)]]
        )
        let restored = try ResponsesCompactionFixture.object(
            ResponsesProviderState.normalize(body: replay, providerID: nil))
        let input = try #require(restored["input"] as? [[String: Any]])
        #expect(try ResponsesCompactionFixture.data(input.last as Any) == ResponsesCompactionFixture.data(native))
    }

    @Test("Tagged custom reasoning is retained for other providers and summarized only by its owner")
    func taggedReasoning() throws {
        let origin = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let other = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let taggedResponse = try ResponsesProviderState.tag(
            response: ResponsesCompactionFixture.data([
                "output": [
                    [
                        "type": "reasoning", "id": "rs_custom",
                        "summary": [["type": "summary_text", "text": "Owner-only rationale"]],
                    ]
                ]
            ]),
            providerID: origin)
        let tagged = try #require(try ResponsesCompactionFixture.object(taggedResponse)["output"] as? [[String: Any]])
        for provider in [nil, other] as [UUID?] {
            let plan = try #require(
                try ResponsesCompactionPlan.prepare(
                    body: ResponsesCompactionFixture.request(items: tagged), providerID: provider))
            let text = try #require(
                String(bytes: plan.summaryRequest(model: "foreign", stream: false), encoding: .utf8))
            #expect(!text.contains("Owner-only rationale"))
            let payload = try ResponsesCompactionFixture.payload(
                plan.complete(responseBody: ResponsesCompactionFixture.response()))
            #expect(
                try ResponsesCompactionFixture.data(payload["retained"] as Any)
                    == ResponsesCompactionFixture.data(tagged))
        }
        let own = try #require(
            try ResponsesCompactionPlan.prepare(
                body: ResponsesCompactionFixture.request(items: tagged), providerID: origin))
        #expect(
            try #require(String(bytes: own.summaryRequest(model: "owner", stream: false), encoding: .utf8)).contains(
                "Owner-only rationale"))
        let ownPayload = try ResponsesCompactionFixture.payload(
            own.complete(responseBody: ResponsesCompactionFixture.response()))
        #expect((ownPayload["retained"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("Preserved opaque checkpoints precede portable summaries and stay out of custom summary requests")
    func opaqueCheckpoint() throws {
        let opaque: [String: Any] = ["type": "compaction", "encrypted_content": "native-checkpoint"]
        let checkpoint = try ResponsesCompactionFixture.owned(retained: [ResponsesCompactionFixture.message, opaque])
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: checkpoint))
        #expect(try ResponsesCompactionFixture.data(expanded.first as Any) == ResponsesCompactionFixture.data(opaque))
        #expect(expanded[1]["role"] as? String == "assistant")
        #expect(
            try ResponsesCompactionFixture.data(expanded.last as Any)
                == ResponsesCompactionFixture.data(ResponsesCompactionFixture.message))
        let provider = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let plan = try #require(
            try ResponsesCompactionPlan.prepare(
                body: ResponsesCompactionFixture.request(items: [checkpoint]), providerID: provider))
        let text = try #require(String(bytes: plan.summaryRequest(model: "custom", stream: false), encoding: .utf8))
        #expect(!text.contains("native-checkpoint"))
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response())
        let retained = try #require(try ResponsesCompactionFixture.payload(result)["retained"] as? [[String: Any]])
        #expect(try ResponsesCompactionFixture.data(retained) == ResponsesCompactionFixture.data([opaque]))
    }

    @Test(
        "Portable checkpoints cannot recursively embed a recognized compaction payload",
        arguments: [
            "little_switch_compaction", "ollama_compaction",
        ])
    func rejectsNested(type: String) throws {
        let nested: [String: Any] = [
            "type": "compaction", "encrypted_content": try ResponsesCompactionFixture.text(["type": type]),
        ]
        #expect(throws: ResponsesCompactionError.invalidPayload) {
            try ResponsesCompactionPayload.expand(item: ResponsesCompactionFixture.owned(retained: [nested]))
        }
    }
}
