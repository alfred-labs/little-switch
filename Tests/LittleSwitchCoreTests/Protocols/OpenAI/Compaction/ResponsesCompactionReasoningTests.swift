import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Compaction preserves reasoning dependencies")
struct ResponsesCompactionReasoningTests {
    @Test("Foreign reasoning keeps its following assistant message without retaining user turns")
    func followingMessage() throws {
        let source = [ResponsesCompactionFixture.message, Self.reasoning, Self.answer, Self.nextUser]
        let plan = try foreignPlan(items: source)
        let payload = try ResponsesCompactionFixture.payload(
            plan.complete(responseBody: ResponsesCompactionFixture.response()))
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data([Self.reasoning, Self.answer]))
    }

    @Test("A reasoning block and its tool result remain joined", arguments: [false, true])
    func reasoningToolBlock(selectedResult: Bool) throws {
        let preamble: [String: Any] = [
            "type": "message", "role": "assistant", "phase": "commentary", "content": "Reading.",
        ]
        let call: [String: Any] = [
            "type": "function_call", "call_id": "call", "namespace": "workspace", "name": "read", "arguments": "{}",
        ]
        let result: [String: Any] = ["type": "function_call_output", "call_id": "call", "output": "File content"]
        let block = [Self.reasoning, preamble, call, result]
        let source = [ResponsesCompactionFixture.message] + block + [Self.answer, Self.nextUser]
        let plan = try selectedResult ? ResponsesCompactionFixture.plan(items: source) : foreignPlan(items: source)
        let payload = try ResponsesCompactionFixture.payload(
            plan.complete(
                responseBody: ResponsesCompactionFixture.response(refs: selectedResult ? ["item_000005"] : [])))
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(block))
    }

    @Test("Selecting a result retains dependencies through its call and the other calls in the reasoning block")
    func transitiveDependencies() throws {
        let firstCall: [String: Any] = [
            "type": "function_call", "call_id": "first", "name": "read", "arguments": "{}",
        ]
        let secondCall: [String: Any] = [
            "type": "custom_tool_call", "call_id": "second", "name": "patch", "input": "Exact patch",
        ]
        let secondResult: [String: Any] = ["type": "custom_tool_call_output", "call_id": "second", "output": "Patched"]
        let firstResult: [String: Any] = ["type": "function_call_output", "call_id": "first", "output": "Read"]
        let block = [Self.reasoning, firstCall, secondCall, secondResult, firstResult]
        let source = [ResponsesCompactionFixture.message] + block + [Self.answer, Self.nextUser]
        let plan = try ResponsesCompactionFixture.plan(items: source)
        let payload = try ResponsesCompactionFixture.payload(
            plan.complete(responseBody: ResponsesCompactionFixture.response(refs: ["item_000006"])))
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(block))
    }

    @Test("Repeated compaction does not absorb the synthetic summary into a retained reasoning block")
    func excludesPreviousSummary() throws {
        let original = [Self.reasoning, Self.answer]
        let checkpoint = try ResponsesCompactionFixture.owned(summary: "Earlier synthetic summary", retained: original)
        let plan = try foreignPlan(items: [checkpoint, Self.nextUser])
        let payload = try ResponsesCompactionFixture.payload(
            plan.complete(responseBody: ResponsesCompactionFixture.response()))
        #expect(
            try ResponsesCompactionFixture.data(payload["retained"] as Any)
                == ResponsesCompactionFixture.data(original))
    }

    private func foreignPlan(items: [[String: Any]]) throws -> ResponsesCompactionPlan {
        let provider = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        return try #require(
            try ResponsesCompactionPlan.prepare(
                body: ResponsesCompactionFixture.request(items: items), providerID: provider))
    }

    private static var reasoning: [String: Any] {
        ["type": "reasoning", "id": "rs_original", "encrypted_content": "native-state", "summary": []]
    }

    private static var answer: [String: Any] {
        ["type": "message", "role": "assistant", "id": "msg_original", "phase": "final_answer", "content": "Finished."]
    }

    private static var nextUser: [String: Any] {
        ["type": "message", "role": "user", "content": "A different task."]
    }
}
