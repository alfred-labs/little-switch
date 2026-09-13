import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic exact wire migration")
struct AnthropicWireMigrationTests {
    @Test func modelTurnRetainsOpaqueFuturePayloadWithoutNumberCoercion() throws {
        let body = Data(#"{"id":"msg","content":[{"type":"future_block","vendor":{"n":1e400}}],"usage":{}}"#.utf8)
        let turn = try AnthropicWebSearch.parseModelTurn(body)
        #expect(
            try JSONValue.parse(turn.contentJSON)
                == JSONValue.parse(#"[{"type":"future_block","vendor":{"n":1e400}}]"#))
    }

    @Test func partialCitationsRemainIncomingUntilThePublicBoundaryValidatesThem() throws {
        let body = Data(
            #"{"id":"msg","content":[{"type":"text","text":"answer","citations":[{"type":"web_search_result_location","url":"https://example.com/","title":"Example","vendor":1e400}]}],"usage":{}}"#
                .utf8
        )
        let turn = try AnthropicWebSearch.parseModelTurn(body)
        #expect(try JSONValue.parse(turn.contentJSON) == JSONValue.parse(body).object?["content"])
        #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
            try AnthropicWebSearch.responseContent(traces: [], finalTurn: turn)
        }
    }

    @Test func thinkingFallbackPreservesEveryOpaqueNumber() throws {
        let body = Data(#"{"thinking":{"type":"disabled"},"vendor":{"n":1e400}}"#.utf8)
        let rewritten = try AnthropicThinkingCompatibility.applying(.lowEffort, to: body)
        #expect(
            try JSONValue.parse(rewritten)
                == JSONValue.parse(
                    #"{"thinking":{"type":"disabled"},"output_config":{"effort":"low"},"vendor":{"n":1e400}}"#))
    }

    @Test func usageCountersRejectBooleanAndFractionalValues() {
        for value in ["true", "1.5", "-1"] {
            let body = Data("{\"id\":\"msg\",\"content\":[],\"usage\":{\"input_tokens\":\(value)}}".utf8)
            #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
                try AnthropicWebSearch.parseModelTurn(body)
            }
        }
    }

    @Test func countProjectionRetainsExactOpaqueToolSchemas() throws {
        let body = Data(
            #"{"model":"m","messages":[],"tools":[{"name":"tool","input_schema":{"example":1e400}}],"stream":true}"#
                .utf8)
        let projected = try AnthropicCountTokensRequest.project(body)
        #expect(
            try JSONValue.parse(projected)
                == JSONValue.parse(
                    #"{"model":"m","messages":[],"tools":[{"name":"tool","input_schema":{"example":1e400}}]}"#))
    }

    @Test func initialUsagePatchKeepsOpaqueNumbersAndUnmodifiedBytes() {
        let frame = Data(
            "event: message_start\ndata: {\"type\":\"message_start\", \"message\": {\"usage\":{\"input_tokens\":0},\"vendor\":1e400}}\n\n"
                .utf8)
        var normalizer = AnthropicInitialUsageNormalizer()
        #expect(normalizer.append(frame) == .estimateRequired)
        let output = normalizer.resolve(.native(9)).reduce(into: Data()) { $0.append($1) }
        #expect(
            output
                == Data(
                    "event: message_start\ndata: {\"type\":\"message_start\", \"message\": {\"usage\":{\"input_tokens\":9},\"vendor\":1e400}}\n\n"
                        .utf8))
    }
}
