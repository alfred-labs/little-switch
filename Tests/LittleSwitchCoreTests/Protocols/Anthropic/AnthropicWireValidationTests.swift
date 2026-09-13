import Foundation
import LittleSwitchTransport
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic wire validation at adapter boundaries")
struct AnthropicWireValidationTests {
    @Test func countProjectionPreservesSpecificHistoryErrors() {
        let invalid = Data(
            #"{"model":"m","messages":[{"role":"assistant","content":[{"type":"server_tool_use","id":"server","name":"web_search","input":{}}]}]}"#
                .utf8)
        #expect(throws: PortableToolHistory.Error.invalidServerHistory) {
            try AnthropicCountTokensRequest.project(invalid)
        }
        let opaque = Data(
            #"""
            {"model":"m","messages":[{"role":"assistant","content":[
              {"type":"server_tool_use","id":"server","name":"web_search","input":{}},
              {"type":"web_search_tool_result","tool_use_id":"server","content":[
                {"type":"web_search_result","title":"Source","url":"https://example.com/",
                 "encrypted_content":"foreign-opaque","page_age":null}]}]}]}
            """#.utf8)
        #expect(throws: PortableWebSearchHistory.Error.unsupportedOpaqueContent) {
            try AnthropicCountTokensRequest.project(opaque)
        }
    }

    @Test func booleanContentHasItsOwnTokenCost() throws {
        #expect(try TokenEstimator.estimate(root: ["system": .boolean(true)]) == 1)
    }

    @Test func absentStreamPayloadsAndUnboundCitationsFail() throws {
        var empty = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try empty.consume(frame("message_start", #"{"type":"message_start"}"#))
        }
        var started = try startedAccumulator()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try started.consume(frame("content_block_start", #"{"type":"content_block_start","index":0}"#))
        }
        try started.consume(
            frame(
                "content_block_start",
                #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"answer"}}"#))
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try started.consume(
                frame(
                    "content_block_delta",
                    #"{"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":null}}"#))
        }
    }

    @Test func aSecondMessageStartCannotReplaceTheOpenTurn() throws {
        var accumulator = try startedAccumulator()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try accumulator.consume(
                frame(
                    "message_start", #"{"type":"message_start","message":{"id":"replacement","content":[],"usage":{}}}"#
                ))
        }
        try accumulator.consume(
            frame(
                "message_delta",
                #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":0}}"#
            ))
        try accumulator.consume(frame("message_stop", #"{"type":"message_stop"}"#))
        #expect(try accumulator.finish().id == "msg")
    }

    @Test func contentStartCannotSkipTheNextBlockIndex() throws {
        var accumulator = try startedAccumulator()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try accumulator.consume(
                frame(
                    "content_block_start",
                    #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":"skipped"}}"#))
        }
        let event = try accumulator.consume(
            frame(
                "content_block_start",
                #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"accepted"}}"#))
        #expect(
            event
                == .contentStart(
                    index: 0, blockJSON: Data(#"{"text":"accepted","type":"text"}"#.utf8)))
    }

    @Test(arguments: [
        #"{"type":"server_tool_use","id":"","name":"web_search","input":{}}"#,
        #"{"type":"server_tool_use","id":"server","name":"","input":{}}"#,
        #"{"type":"server_tool_use","id":"server","name":"web_search","input":null}"#,
    ])
    func serverToolStartRequiresIdentityAndEmptyInput(block: String) throws {
        var accumulator = try startedAccumulator()
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try accumulator.consume(
                frame(
                    "content_block_start", "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":\(block)}"))
        }
    }

    @Test func serverToolFragmentsRemainExactThroughBothStreamAdapters() throws {
        var accumulator = try startedAccumulator()
        for event in [
            frame(
                "content_block_start",
                #"{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"server","name":"web_search","input":{}}}"#
            ),
            frame(
                "content_block_delta",
                #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"large\":1e400,\"tiny\":1e-400}"}}"#
            ),
            frame("content_block_stop", #"{"type":"content_block_stop","index":0}"#),
            frame(
                "message_delta",
                #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1}}"#
            ),
            frame("message_stop", #"{"type":"message_stop"}"#),
        ] { try accumulator.consume(event) }
        let turn = try accumulator.finish()
        let expected = try JSONValue.parse(#"{"large":1e400,"tiny":1e-400}"#)
        #expect(try JSONValue.parse(turn.contentJSON).array?.first?.object?["input"] == expected)
        let events = try anthropicLiveEvents(for: turn)
        let inputs = try events.compactMap { event -> JSONValue? in
            guard case .contentDelta(_, let data) = event else { return nil }
            let delta = try WireCodec.decode(AnthropicInputJSONDelta.self, from: data).value
            return try JSONValue.parse(delta.partialJson)
        }
        #expect(inputs == [expected])
    }

    @Test func liveFallbackRejectsNonObjectToolInput() {
        let turn = bareAnthropicTurn(
            contentJSON: Data(
                #"[{"type":"server_tool_use","id":"server","name":"web_search","input":42}]"#.utf8))
        #expect(throws: GatewayAnthropicLiveError.self) { try anthropicLiveEvents(for: turn) }
    }

    private func startedAccumulator() throws -> AnthropicStreamingTurnAccumulator {
        var accumulator = AnthropicStreamingTurnAccumulator(maximumTurnBytes: 4_096)
        try accumulator.consume(
            frame(
                "message_start", #"{"type":"message_start","message":{"id":"msg","content":[],"usage":{}}}"#))
        return accumulator
    }

    private func frame(_ event: String, _ json: String) -> ServerSentEventFrame {
        ServerSentEventFrame(event: event, data: Data(json.utf8), terminal: false)
    }
}
