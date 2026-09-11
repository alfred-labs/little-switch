import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Responses portable compaction payload")
struct ResponsesCompactionPayloadTests {
    @Test("Payload expansion preserves original Responses objects and identities")
    func expandsOwned() throws {
        let retained: [[String: Any]] = [
            ["type": "function_call", "call_id": "call", "namespace": "a.b", "name": "c", "arguments": "{}"],
            ["type": "function_call_output", "call_id": "call", "output": "done"],
            ["type": "function_call_output", "namespace": "a", "name": "b.c", "output": "tasking"],
        ]
        let item = try ResponsesCompactionFixture.owned(summary: "The earlier task.", retained: retained)
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: item))
        #expect(expanded.first?["role"] as? String == "assistant")
        #expect(try ResponsesCompactionFixture.text(expanded[0]).contains("The earlier task."))
        #expect(
            try ResponsesCompactionFixture.data(Array(expanded.dropFirst()))
                == ResponsesCompactionFixture.data(retained))
    }

    @Test(
        "Unknown provider payloads stay opaque",
        arguments: [
            #"{}"#, #"{"type":"message","encrypted_content":"opaque"}"#,
            #"{"type":"compaction"}"#, #"{"type":"compaction","encrypted_content":7}"#,
            #"{"type":"compaction","encrypted_content":"opaque"}"#,
            #"{"type":"compaction","encrypted_content":"{\"type\":\"foreign\",\"version\":1}"}"#,
        ])
    func foreign(text: String) throws {
        #expect(try ResponsesCompactionPayload.expand(item: ResponsesCompactionFixture.object(Data(text.utf8))) == nil)
    }

    @Test(
        "Malformed owned payloads cannot inject controls or silently discard retained state",
        arguments: [
            #"{"type":"little_switch_compaction","version":2,"summary":"s","retained":[]}"#,
            #"{"type":"little_switch_compaction","version":true,"summary":"s","retained":[]}"#,
            #"{"type":"little_switch_compaction","summary":"s","retained":[]}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":" ","retained":[]}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":null,"retained":[]}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":"s","retained":null}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":"s","retained":[null]}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":"s","retained":[{}]}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":"s","retained":[{"type":"compaction"}]}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":"s","retained":[{"type":"compaction_trigger"}]}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":"s","retained":[{"type":"item_reference","id":"server"}]}"#,
            #"{"type":"little_switch_compaction","version":1,"summary":"s","retained":[],"unexpected":true}"#,
        ])
    func invalid(text: String) {
        #expect(throws: ResponsesCompactionError.invalidPayload) {
            try ResponsesCompactionPayload.expand(item: ["type": "compaction", "encrypted_content": text])
        }
    }
}
