import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses compaction summary requests")
struct ResponsesCompactionSummaryRequestTests {
    @Test("Managed summaries do not inherit native reasoning context or effort")
    func managedReasoningContext() throws {
        let plan = try ResponsesCompactionFixture.plan(fields: [
            "reasoning": ["context": "all_turns", "effort": "max", "summary": "detailed"]
        ])
        let managed = try ResponsesCompactionFixture.object(plan.summaryRequest(model: "custom", stream: false))
        #expect(managed["reasoning"] == nil)
    }

    @Test(
        "Managed summaries do not invent reasoning context when none was supplied",
        arguments: ["null", "{}", #"{"effort":"max","summary":"detailed"}"#, #"{"context":null}"#]
    )
    func absentReasoningContext(reasoning: String) throws {
        let plan = try ResponsesCompactionFixture.plan(fields: [
            "reasoning": JSONSerialization.jsonObject(with: Data(reasoning.utf8), options: [.fragmentsAllowed])
        ])
        let request = try ResponsesCompactionFixture.object(
            plan.summaryRequest(model: "custom", stream: false))
        #expect(request["reasoning"] == nil)
    }

    @Test("Summary turns leave the output budget to the provider instead of imposing or inheriting a limit")
    func providerOutputBudget() throws {
        let plans = try [
            ResponsesCompactionFixture.plan(),
            ResponsesCompactionFixture.plan(fields: ["max_output_tokens": 100_000]),
        ]
        for plan in plans {
            let managed = try ResponsesCompactionFixture.object(plan.summaryRequest(model: "custom", stream: false))
            #expect(managed["max_output_tokens"] == nil)
        }
    }
}
