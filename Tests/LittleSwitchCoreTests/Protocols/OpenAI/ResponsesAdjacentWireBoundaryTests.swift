import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Responses adjacent exact wire boundaries")
struct ResponsesAdjacentWireBoundaryTests {
    @Test("Opaque schemas carry exact numbers without declaring nested tool identities")
    func schemaNumbersDoNotAuthorizeTools() throws {
        let request = Data(
            #"{"tools":[{"type":"function","name":"read","parameters":{"maximum":1e400,"tools":[{"type":"function","name":"write"}]}}]}"#
                .utf8)
        let contract = try ProviderToolContract(wire: .responses, requestBody: request)
        try contract.validateBuffered(
            Data(
                #"{"output":[{"type":"function_call","name":"read","arguments":"{}"}],"vendor":1e400}"#.utf8))
        #expect(throws: ProviderToolContract.Error.undeclaredTool(name: "write")) {
            try contract.validateBuffered(
                Data(
                    #"{"output":[{"type":"function_call","name":"write","arguments":"{}"}],"vendor":1e400}"#.utf8))
        }
    }

    @Test("Exact numeric Chat indices work while opaque metadata stays outside identity policy")
    func contractStreamNumbers() throws {
        var contract = try ProviderToolContract(
            wire: .chatCompletions,
            requestBody: Data(#"{"tools":[{"type":"function","function":{"name":"read"}}]}"#.utf8))
        try contract.validateFrame(
            ServerSentEventFrame(
                event: nil,
                data: Data(
                    #"{"choices":[{"index":0e0,"delta":{"tool_calls":[{"index":0.0,"type":"function","function":{"name":"read"}}]}}],"vendor":1e400}"#
                        .utf8),
                terminal: false))
        try contract.finish()
    }

    @Test("The compaction probe leaves an ordinary exact request alone")
    func ordinaryCompactionProbe() throws {
        let request = Data(#"{"model":"client","input":"hello","vendor":1e400}"#.utf8)
        #expect(try ResponsesCompactionPlan.prepare(body: request) == nil)
    }

    @Test("Compaction retains and expands opaque transcript numbers exactly")
    func retainedCompactionNumbers() throws {
        let request = Data(
            #"{"model":"client","stream":true,"input":[{"type":"message","role":"user","content":"keep","vendor":{"huge":1e400,"tiny":1e-400}},{"type":"compaction_trigger"}]}"#
                .utf8)
        let original = try #require(JSONValue.parse(request).object?["input"]?.array?.first)
        let plan = try #require(try ResponsesCompactionPlan.prepare(body: request))
        #expect(try JSONValue.parse(#require(plan.items.first)) == original)
        let result = try plan.complete(responseBody: ResponsesCompactionFixture.response(refs: ["item_000001"]))
        let item = try WireJSONCompatibility.fields(result.itemJSON)
        let expanded = try #require(try ResponsesCompactionPayload.expand(item: item))
        #expect(try WireJSONCompatibility.value(#require(expanded.last)) == original)
    }

    @Test("The legacy public history entry point accepts exact opaque fields")
    func portableSearchHistory() throws {
        let original = try JSONValue.parse(
            Data(
                #"{"type":"web_search_call","id":"search_1","vendor":{"huge":1e400,"tiny":1e-400}}"#.utf8))
        let fields = try #require(WireJSONCompatibility.view(original) as? [String: Any])
        let message = try PortableResponsesHistory.message(for: fields)
        let content = try #require(message["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        #expect(try JSONValue.parse(Data(text.dropFirst("[Previous web search]\n".count).utf8)) == original)
    }

    @Test("Exact numeric history keeps the existing repeated exchange cap")
    func legacyHistoryDeduplication() throws {
        let request = Data(
            #"""
            {"input":[
              {"type":"function_call","call_id":"a","name":"read","arguments":"{}"},
              {"type":"function_call_output","call_id":"a","output":1e400},
              {"type":"function_call","call_id":"b","name":"read","arguments":"{}"},
              {"type":"function_call_output","call_id":"b","output":1e400},
              {"type":"function_call","call_id":"c","name":"read","arguments":"{}"},
              {"type":"function_call_output","call_id":"c","output":1e400},
              {"type":"function_call","call_id":"d","name":"read","arguments":"{}"},
              {"type":"function_call_output","call_id":"d","output":1e400}
            ]}
            """#
            .utf8)
        let fields = try WireJSONCompatibility.fields(request)
        let input = try #require(fields["input"] as? [[String: Any]])
        let collapsed = ResponsesHistoryDeduplication.collapsed(input)
        #expect(collapsed.count == 6)
        #expect(collapsed.first?["call_id"] as? String == "b")
    }
}
