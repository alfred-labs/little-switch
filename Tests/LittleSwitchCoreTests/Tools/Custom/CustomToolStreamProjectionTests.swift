import AsyncHTTPClient
import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import NIOCore
import Testing

@testable import LittleSwitchCore

@Suite("Bounded custom tool stream restoration")
struct CustomToolStreamProjectionTests {
    @Test("Responses restores done and final snapshots at every byte boundary without leaking the envelope")
    func responsesFragments() async throws {
        let chunks = [
            #"""
            {
              "type": "response.output_item.added",
              "output_index": 0,
              "item": {
                "type": "function_call",
                "id": "fc",
                "call_id": "call",
                "name": "exec",
                "arguments": "",
                "status": "in_progress"
              }
            }
            """#,
            #"{"type":"response.function_call_arguments.delta","output_index":0,"item_id":"fc","delta":"{\"input\":\"a"}"#,
            #"{"type":"response.function_call_arguments.delta","output_index":0,"item_id":"fc","delta":"\\r\\n🐈\"}"}"#,
            #"{"type":"response.function_call_arguments.done","output_index":0,"item_id":"fc","arguments":"{\"input\":\"a\\r\\n🐈\"}"}"#,
            #"""
            {
              "type": "response.output_item.done",
              "output_index": 0,
              "item": {
                "type": "function_call",
                "id": "fc",
                "call_id": "call",
                "name": "exec",
                "arguments": "{\"input\":\"a\\r\\n🐈\"}",
                "status": "completed"
              }
            }
            """#,
            #"""
            {
              "type": "response.completed",
              "response": {
                "output": [
                  {
                    "type": "function_call",
                    "id": "fc",
                    "call_id": "call",
                    "name": "exec",
                    "arguments": "{\"input\":\"a\\r\\n🐈\"}",
                    "status": "completed"
                  }
                ]
              }
            }
            """#,
        ]
        let source = chunks.map { "data: " + $0.replacingOccurrences(of: "\n", with: "\ndata: ") + "\n\n" }.joined()
        for bytes in [[Data(source.utf8)], source.utf8.map { Data([$0]) }] {
            let output = try await restore(bytes, wire: .responses)
            let events = try frames(output)
            #expect(!events.contains { $0.data.contains(Data("function_call".utf8)) })
            let done = try #require(events.first { $0.data.contains(Data("custom_tool_call_input.done".utf8)) })
            #expect(try JSONValue.parse(done.data).object?["input"] == .string("a\r\n🐈"))
            let final = try #require(events.last)
            let item = try JSONValue.parse(final.data).object?["response"]?.object?["output"]?.array?.first
            #expect(item?.object?["type"] == .string("custom_tool_call"))
            #expect(item?.object?["input"] == .string("a\r\n🐈"))
        }
    }

    @Test("Chat partial names and parallel calls restore only declared custom identities")
    func chatFragments() async throws {
        let source = """
            data: {"choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[
            data: {"index":0,"id":"a","type":"function","function":{"name":"ex","arguments":"{\\\"input\\\":\\\""}},
            data: {"index":1,"id":"b","type":"function","function":{"name":"echo","arguments":"{}"}}]},"finish_reason":null}]}

            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"ec","arguments":"x\\\"}"}}]},"finish_reason":null}]}

            data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

            data: [DONE]


            """
        let output = try await restore([Data(source.utf8)], wire: .chatCompletions)
        let calls = try frames(output).filter { !$0.terminal }.flatMap { frame in
            (try JSONValue.parse(frame.data).object?["choices"]?.array ?? []).flatMap {
                $0.object?["delta"]?.object?["tool_calls"]?.array ?? []
            }
        }
        #expect(calls.count == 2)
        #expect(calls.first?.object?["function"]?.object?["name"] == .string("echo"))
        #expect(calls.last?.object?["custom"] == .object(["name": .string("exec"), "input": .string("x")]))
    }

    @Test("Ordinary frames retain their original event metadata and bytes")
    func ordinaryIdentity() async throws {
        let source = Data(
            ": keep\r\nid: 3\r\nretry: 10\r\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\r\n\r\ndata: [DONE]\n\n"
                .utf8)
        #expect(try await restore([source], wire: .chatCompletions) == source)
    }

    @Test("Invalid complete envelopes never become executable custom input")
    func invalidEnvelope() async throws {
        let source = Data(
            """
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"a","type":"function",
            data: "function":{"name":"exec","arguments":"{\\\"input\\\":null}"}}]},"finish_reason":"tool_calls"}]}

            data: [DONE]


            """.utf8)
        await #expect(throws: (any Swift.Error).self) { try await restore([source], wire: .chatCompletions) }
    }

    @Test("Truncated custom calls fail at EOF")
    func missingTerminal() async throws {
        let source = Data(
            """
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"a","type":"function",
            data: "function":{"name":"exec","arguments":""}}]}}]}


            """.utf8)
        await #expect(throws: (any Swift.Error).self) { try await restore([source], wire: .chatCompletions) }
    }

    @Test("Chat identity fields can arrive after the first call fragment", arguments: [false, true])
    func lateIdentity(explicitNulls: Bool) async throws {
        let source = """
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"type":"function","function":{}}]}}]}

            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"a",
            data: "function":{"name":"exec","arguments":"{\\\"input\\\":\\\"x\\\"}"}}]},"finish_reason":"tool_calls"}]}

            data: [DONE]


            """
        let wire =
            explicitNulls
            ? source.replacingOccurrences(of: "\"function\":{}", with: "\"id\":null,\"function\":null") : source
        let output = try await restore([Data(wire.utf8)], wire: .chatCompletions)
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(text.contains("\"custom\""))
        #expect(!text.contains("\"function\""))
    }

    @Test("Chat rejects a canonically equivalent changed call ID")
    func unicodeIdentity() async throws {
        let source = #"""
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"é",
            data: "type":"function","function":{"name":"exec","arguments":""}}]}}]}

            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"e\u0301",
            data: "function":{"arguments":"{\"input\":\"x\"}"}}]},"finish_reason":"tool_calls"}]}

            data: [DONE]


            """#
        await #expect(throws: CustomToolProjection.Error.invalidResponse) {
            try await restore([Data(source.utf8)], wire: .chatCompletions)
        }
    }

    @Test("A repeated ordinary function name that prefixes a custom name is not appended")
    func ordinaryPrefix() async throws {
        let body = Data(
            #"{"tools":[{"type":"custom","custom":{"name":"executor"}},{"type":"function","function":{"name":"exec"}}]}"#
                .utf8)
        let projection = try CustomToolProjection.prepare(body: body, wire: .chatCompletions, adapt: true)
        var state = CustomToolStreamProjection(projection: projection, maximumBytes: 4_096)
        let source = Data(
            """
            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"a","type":"function","function":{"name":"exec","arguments":"{"}}]}}]}

            data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"exec","arguments":"}"}}]},"finish_reason":"tool_calls"}]}


            """.utf8)
        let events = try frames(source)
        _ = try state.consume(events[0])
        guard case .replace(let result) = try state.consume(events[1]) else {
            Issue.record("Expected complete call")
            return
        }
        let call = result.object?["choices"]?.array?.first?.object?["delta"]?.object?["tool_calls"]?.array?.first
        #expect(call?.object?["function"] == .object(["name": .string("exec"), "arguments": .string("{}")]))
    }

    private func restore(_ chunks: [Data], wire: ProviderToolContract.Wire) async throws -> Data {
        let body =
            wire == .responses
            ? #"{"tools":[{"type":"custom","name":"exec"},{"type":"function","name":"echo"}]}"#
            : #"{"tools":[{"type":"custom","custom":{"name":"exec"}},{"type":"function","function":{"name":"echo"}}]}"#
        let projection = try CustomToolProjection.prepare(body: Data(body.utf8), wire: wire, adapt: true)
        let source = DemandTrackedBodySequence(chunks: chunks)
        let response = try await CustomToolResponse.restored(
            HTTPClientResponse(status: .ok, headers: ["content-type": "text/event-stream"], body: .stream(source)),
            projection: projection,
            maximumBytes: 4_096)
        return Data(try await response.body.collect(upTo: 65_536).readableBytesView)
    }

    private func frames(_ data: Data) throws -> [ServerSentEventFrame] {
        var decoder = ServerSentEventDecoder(maximumFrameBytes: 65_536)
        return try decoder.append(ByteBuffer(bytes: data)) + decoder.finish()
    }
}
