import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Compaction recovery preserves source positions")
struct ResponsesCompactionRecoveryStateTests {
    @Test("Recovery keeps the selected occurrence and every provider-state position")
    func originalPositions() throws {
        let duplicate = ResponsesCompactionFixture.message
        let high: [String: Any] = ["type": "configuration_update", "reasoning": ["effort": "high"]]
        let low: [String: Any] = ["type": "configuration_update", "reasoning": ["effort": "low"]]
        let original = [duplicate, Self.opaque, Self.reasoning, duplicate, high] + Self.pair + [low, high]
        let plan = try ResponsesCompactionFixture.plan(items: original)
        let recovered = plan.retainingProviderState()
        let result = try recovered.complete(
            responseBody: ResponsesCompactionFixture.response(refs: ["item_000004"]))
        let payload = try ResponsesCompactionFixture.payload(result)
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(Array(original.dropFirst())))
        #expect(
            try plan.summaryRequest(model: "native", stream: true, mode: .nativeContinuation)
                == recovered.summaryRequest(model: "native", stream: true, mode: .nativeContinuation))
        let unchanged = try ResponsesCompactionFixture.payload(
            plan.complete(responseBody: ResponsesCompactionFixture.response()))
        #expect(
            try ResponsesCompactionFixture.data(unchanged["retained"] as Any)
                == ResponsesCompactionFixture.data(Self.pair))
    }

    @Test("Recovery preserves configuration transitions that return to an earlier value")
    func configurationOccurrences() throws {
        let high: [String: Any] = ["type": "configuration_update", "reasoning": ["effort": "high"]]
        let low: [String: Any] = ["type": "configuration_update", "reasoning": ["effort": "low"]]
        let original = [high, low, high]
        let plan = try ResponsesCompactionFixture.plan(items: original).retainingProviderState()
        let payload = try ResponsesCompactionFixture.payload(
            plan.complete(responseBody: ResponsesCompactionFixture.response()))
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(original))
    }

    @Test("Recovery followed by native or custom compaction keeps the unread tool pair", arguments: [false, true])
    func recoveredPair(nativeTarget: Bool) throws {
        let source = [Self.opaque, Self.reasoning] + Self.pair
        let recovered = try ResponsesCompactionFixture.plan(items: source).retainingProviderState()
        let result = try recovered.complete(responseBody: ResponsesCompactionFixture.response())
        let checkpoint = try ResponsesCompactionFixture.object(result.itemJSON)
        let payload = try ResponsesCompactionFixture.payload(result)
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(source))
        let provider = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let next = try #require(
            try ResponsesCompactionPlan.prepare(
                body: ResponsesCompactionFixture.request(items: [checkpoint]),
                providerID: nativeTarget ? nil : provider))
        let nextResult = try next.complete(responseBody: ResponsesCompactionFixture.response())
        let nextPayload = try ResponsesCompactionFixture.payload(nextResult)
        #expect(
            try ResponsesCompactionFixture.data(nextPayload["retained"] as Any)
                == ResponsesCompactionFixture.data(nativeTarget ? [Self.reasoning] + Self.pair : source))
    }

    @Test("Foreign reasoning cannot acknowledge an unread tool result", arguments: [false, true])
    func latentReasoning(nativeTarget: Bool) throws {
        let provider = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let taggedResponse = try ResponsesProviderState.tag(
            response: ResponsesCompactionFixture.data(["output": [Self.reasoning]]), providerID: provider)
        let tagged = try #require(
            (try ResponsesCompactionFixture.object(taggedResponse)["output"] as? [[String: Any]])?.first)
        let foreign = nativeTarget ? tagged : Self.reasoning
        let retained = Self.pair + [foreign]
        let checkpoint = try ResponsesCompactionFixture.owned(retained: retained)
        let plan = try #require(
            try ResponsesCompactionPlan.prepare(
                body: ResponsesCompactionFixture.request(items: [checkpoint]),
                providerID: nativeTarget ? nil : provider))
        let payload = try ResponsesCompactionFixture.payload(
            plan.complete(responseBody: ResponsesCompactionFixture.response()))
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(retained))
        let request = try plan.summaryRequest(
            model: "target", stream: false, mode: nativeTarget ? .nativeContinuation : .transcript)
        let text = try #require(String(bytes: request, encoding: .utf8))
        #expect(!text.contains("latent-provider-state"))
    }

    private static var opaque: [String: Any] {
        ["type": "compaction", "encrypted_content": "native-checkpoint"]
    }

    private static var reasoning: [String: Any] {
        ["type": "reasoning", "id": "rs_original", "encrypted_content": "latent-provider-state", "summary": []]
    }

    private static var pair: [[String: Any]] {
        [
            ["type": "function_call", "call_id": "active", "name": "read", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "active", "output": "Unread result"],
        ]
    }
}
