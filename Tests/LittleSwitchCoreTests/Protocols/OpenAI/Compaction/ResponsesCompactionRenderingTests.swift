import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Compaction reasoning rendering")
struct ResponsesCompactionRenderingTests {
    @Test("Readable reasoning is quoted without opaque state")
    func reasoningRendering() throws {
        let provider = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let original: [String: Any] = [
            "type": "reasoning", "id": "rs_native", "encrypted_content": "opaque-provider-state",
            "summary": [["type": "summary_text", "text": "Visible reasoning summary"]],
            "content": [["type": "reasoning_text", "text": "Visible reasoning content"]],
        ]
        let taggedResponse = try ResponsesProviderState.tag(
            response: ResponsesCompactionFixture.data(["output": [original]]), providerID: provider)
        let tagged = try #require(
            (try ResponsesCompactionFixture.object(taggedResponse)["output"] as? [[String: Any]])?.first)
        let inputs: [(UUID?, [String: Any])] = [(nil, original), (provider, tagged)]
        for (providerID, item) in inputs {
            let plan = try #require(
                try ResponsesCompactionPlan.prepare(
                    body: ResponsesCompactionFixture.request(items: [item]), providerID: providerID))
            let request = try plan.summaryRequest(model: "owner", stream: false)
            let text = try #require(String(bytes: request, encoding: .utf8))
            #expect(text.contains("Visible reasoning summary"))
            #expect(text.contains("Visible reasoning content"))
            #expect(!text.contains("opaque-provider-state"))
            #expect(!text.contains("little_switch_reasoning"))
            #expect(!text.contains("encrypted_content"))
            let result = try plan.complete(
                responseBody: ResponsesCompactionFixture.response(refs: ["item_000001"]))
            let payload = try ResponsesCompactionFixture.payload(result)
            #expect(
                try ResponsesCompactionFixture.data(payload["retained"] as Any)
                    == ResponsesCompactionFixture.data([item]))
        }
    }

    @Test("Custom compaction retains native configuration while hiding it from the summary model")
    func nativeConfiguration() throws {
        let provider = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let configuration: [String: Any] = [
            "type": "configuration_update", "reasoning": ["effort": "high"], "metadata": "native-setting",
        ]
        let plan = try #require(
            try ResponsesCompactionPlan.prepare(
                body: ResponsesCompactionFixture.request(items: [configuration, ResponsesCompactionFixture.message]),
                providerID: provider))
        let request = try plan.summaryRequest(model: "custom", stream: false)
        let text = try #require(String(bytes: request, encoding: .utf8))
        #expect(!text.contains("configuration_update"))
        #expect(!text.contains("native-setting"))
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response())
        let payload = try ResponsesCompactionFixture.payload(result)
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data([configuration]))
        let checkpoint = try ResponsesCompactionFixture.object(result.itemJSON)
        let replay = try ResponsesCompactionFixture.data(["input": [checkpoint]])
        let native = try ResponsesCompactionFixture.object(
            ResponsesProviderState.normalize(body: replay, providerID: nil))
        let nativeInput = try #require(native["input"] as? [[String: Any]])
        #expect(
            try ResponsesCompactionFixture.data(nativeInput.last as Any)
                == ResponsesCompactionFixture.data(configuration))
        let custom = try ResponsesProviderState.normalize(body: replay, providerID: provider)
        let customText = try #require(String(bytes: custom, encoding: .utf8))
        #expect(!customText.contains("native-setting"))
    }
}
