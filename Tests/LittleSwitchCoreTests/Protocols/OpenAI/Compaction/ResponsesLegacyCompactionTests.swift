import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Compaction checkpoints from earlier gateway builds")
struct ResponsesLegacyCompactionTests {
    private let legacy: [String: Any] = [
        "type": "compaction",
        "encrypted_content": #"{"type":"little_switch_compaction","version":1,"summary":"Earlier work."}"#,
    ]

    @Test("Summary-only v1 checkpoints remain readable by either provider destination", arguments: [false, true])
    func restoresLegacy(native: Bool) throws {
        let body = try ResponsesCompactionFixture.data(["model": "route", "input": [legacy]])
        let normalized = try ResponsesProviderState.normalize(body: body, providerID: native ? nil : UUID())
        let expected: [String: Any] = [
            "model": "route",
            "input": [
                [
                    "type": "message", "role": "assistant",
                    "content": [["type": "output_text", "text": "Earlier work."]],
                ]
            ],
        ]
        #expect(normalized == (try ResponsesCompactionFixture.data(expected)))
        #expect(try !ResponsesProviderState.requiresNativeRecovery(body))
    }

    @Test("Compacting a legacy checkpoint retains foreign reasoning for the native return")
    func recompactsLegacy() throws {
        let native: [String: Any] = [
            "type": "reasoning", "id": "rs_native_opaque", "encrypted_content": "native-state",
        ]
        let request = try ResponsesCompactionFixture.request(items: [legacy, native])
        let plan = try #require(try ResponsesCompactionPlan.prepare(body: request, providerID: UUID()))
        let summaryRequest = try plan.summaryRequest(model: "custom", stream: false)
        #expect(try #require(String(data: summaryRequest, encoding: .utf8)).contains("Earlier work."))
        #expect(!summaryRequest.contains(Data("native-state".utf8)))
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response())
        let retained = try #require(try ResponsesCompactionFixture.payload(result)["retained"] as? [[String: Any]])
        #expect(try ResponsesCompactionFixture.data(retained) == ResponsesCompactionFixture.data([native]))
    }
}
