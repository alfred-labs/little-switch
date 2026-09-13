import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Chat request wire boundaries")
struct ChatRequestWireBoundaryTests {
    @Test("Responses to Chat preserves exact JSON Schema and tool output fragments")
    func requestPreservesOpaqueValues() throws {
        let body = Data(
            #"""
            {"model":"client","input":[
              {"type":"function_call","call_id":"call_1","name":"read","arguments":"{}"},
              {"type":"function_call_output","call_id":"call_1","output":{"tiny":1e-400,"huge":1e400}}
            ],"text":{"format":{"type":"json_schema","name":"result","schema":{
              "type":"object","properties":{"value":{"type":"number","maximum":1e400}}
            }}},"metadata":{"precise":18446744073709551617}}
            """#.utf8)
        let prepared = try OpenAIResponsesChatCompletions.prepare(body: body, targetModel: "provider")
        let original = try #require(JSONValue.parse(body).object)
        let request = try #require(JSONValue.parse(prepared.upstreamBody).object)
        #expect(prepared.originalBody == body)
        #expect(request["model"] == .string("provider"))
        #expect(request["metadata"] == original["metadata"])
        #expect(
            request["response_format"]?.object?["json_schema"]?.object?["schema"]
                == original["text"]?.object?["format"]?.object?["schema"])
        let outputText = try #require(request["messages"]?.array?.last?.object?["content"]?.string)
        #expect(try JSONValue.parse(Data(outputText.utf8)) == original["input"]?.array?[1].object?["output"])
    }

    @Test("Buffered Chat response echoes exact client-owned metadata")
    func responsePreservesClientMetadata() throws {
        let body = Data(#"{"model":"client","input":"hi","metadata":{"huge":1e400,"tiny":1e-400}}"#.utf8)
        let prepared = PreparedResponsesChatCompletionsRequest(
            upstreamBody: Data(), originalBody: body, originalModel: "client", streaming: false)
        let response = Data(
            #"{"choices":[{"finish_reason":"stop","message":{"content":"hi"}}]}"#.utf8)
        let projected = try OpenAIResponsesChatCompletions.project(responseBody: response, prepared: prepared)
        #expect(try JSONValue.parse(projected).object?["metadata"] == JSONValue.parse(body).object?["metadata"])
    }
}
