import Foundation
import LittleSwitchWire
import Testing

@Suite
struct AnthropicMessageWireTests {
    @Test func preservesUnknownBlock() throws {
        let data = Data(#"{"type":"future_block","vendor":{"n":18446744073709551615}}"#.utf8)
        let document = try WireCodec.decode(AnthropicContentBlock.self, from: data)
        #expect(document.originalData == data)
        #expect(try WireCodec.encode(document.value) == data)
    }

    @Test(arguments: [
        #"{"type":"text"}"#,
        #"{"type":"thinking","thinking":"x","signature":false}"#,
        #"{"type":"tool_use","id":true,"name":"f","input":{}}"#,
        #"{"type":"web_search_tool_result","tool_use_id":"id","content":true}"#,
    ])
    func rejectsMalformedKnownBlocks(_ json: String) throws {
        #expect(throws: WireCodingError.self) {
            try WireCodec.decode(AnthropicContentBlock.self, from: Data(json.utf8))
        }
    }

    @Test func incomingMessageSelectsOnlyConsumedMetadata() throws {
        let data = Data(#"{"id":"msg","type":false,"role":17,"model":{},"content":[],"usage":{}}"#.utf8)
        let message = try WireCodec.decode(AnthropicMessage.self, from: data).value
        #expect(message.id == "msg")
        #expect(message.content.isEmpty)
        #expect(message.additionalFields["type"] == .boolean(false))
        #expect(try WireCodec.encode(message).isEmpty == false)
    }

    @Test func fixtureBackedIncomingOmissionsRemainDistinct() throws {
        for json in [
            #"{"type":"text","text":"x"}"#,
            #"{"type":"text","text":"x","citations":null}"#,
            #"{"type":"thinking","thinking":"x"}"#,
            #"{"type":"tool_use","id":"id","name":"f","input":{}}"#,
            #"{"type":"server_tool_use","id":"id","name":"future_tool","input":{}}"#,
            #"{"type":"web_search_tool_result","tool_use_id":"id","content":[]}"#,
            #"{"type":"text","text":"x","citations":[{"type":"char_location","cited_text":"x","document_index":0,"start_char_index":0,"end_char_index":1}]}"#,
            #"{"type":"text","text":"x","citations":[{"type":"page_location","cited_text":"x","document_index":0,"start_page_number":0,"end_page_number":1}]}"#,
            #"{"type":"text","text":"x","citations":[{"type":"content_block_location","cited_text":"x","document_index":0,"start_block_index":0,"end_block_index":1}]}"#,
            #"""
            {"type":"text","text":"x","citations":[
              {"type":"search_result_location","cited_text":"x","source":"s","search_result_index":0,"start_block_index":0,"end_block_index":1}
            ]}
            """#,
        ] {
            let document = try WireCodec.decode(AnthropicContentBlock.self, from: Data(json.utf8))
            #expect(try document.value.wireJSON() == JSONValue.parse(json))
        }
    }

    @Test func usageAndTerminalUpdatesPreservePresence() throws {
        let absent = try WireCodec.decode(AnthropicUsageFields.self, from: Data("{}".utf8)).value
        let null = try WireCodec.decode(
            AnthropicUsageFields.self,
            from: Data(#"{"input_tokens":null,"output_tokens":null,"cache_creation":null,"service_tier":null}"#.utf8)
        ).value
        #expect(absent.inputTokens == .absent)
        #expect(null.inputTokens == .null)
        #expect(null.outputTokens == .null)
        let event = try WireCodec.decode(
            AnthropicStreamEvent.self,
            from: Data(#"{"type":"message_delta","delta":{"stop_reason":"future_reason"},"usage":{}}"#.utf8)
        ).value
        #expect(
            try event.wireJSON()
                == JSONValue.parse(#"{"type":"message_delta","delta":{"stop_reason":"future_reason"},"usage":{}}"#))
    }

    @Test func accumulatorCitationProjectionRetainsPartialPayloadForPublicValidation() throws {
        let citation = try JSONValue.parse(
            #"{"type":"web_search_result_location","url":"https://example.com/","title":"Example","vendor":1e400}"#
        )
        let source: JSONValue = ["type": "text", "text": "answer", "citations": .array([citation])]
        let incoming = try AnthropicIncomingContentBlock(wireJSON: source)
        #expect(try incoming.wireJSON() == source)
        #expect(try AnthropicCitationIdentity(wireJSON: citation).wireJSON() == citation)
        #expect(throws: WireCodingError.self) { try AnthropicContentBlock(wireJSON: source) }
        #expect(throws: WireCodingError.self) {
            try AnthropicCitationIdentity(wireJSON: ["type": .boolean(true)])
        }
    }

    @Test func citationDeltaRetainsMissingNullAndValueStates() throws {
        let absent = try AnthropicCitationsDelta(wireJSON: ["type": "citations_delta"])
        let null = try AnthropicCitationsDelta(wireJSON: ["type": "citations_delta", "citation": .null])
        let value = try AnthropicCitationsDelta(
            wireJSON: ["type": "citations_delta", "citation": ["type": "future_citation"]]
        )
        #expect(absent.citation == .absent)
        #expect(null.citation == .null)
        #expect(value.citation == .value(["type": "future_citation"]))
    }

    @Test func inputBlocksKeepImageAndPortableHistoryShapes() throws {
        for json in [
            #"{"role":"assistant","content":[{"type":"thinking","thinking":"x"},{"type":"server_tool_use","id":"id","name":"future_tool","input":{}}]}"#,
            #"""
            {"role":"user","content":[
              {"type":"image","source":{"type":"base64","data":"abc","media_type":"image/png"}},
              {"type":"tool_result","tool_use_id":"id","content":"ok"}
            ]}
            """#,
        ] {
            let message = try WireCodec.decode(AnthropicMessageParam.self, from: Data(json.utf8)).value
            #expect(try message.wireJSON() == JSONValue.parse(json))
        }
        #expect(throws: WireCodingError.self) {
            try WireCodec.decode(
                AnthropicMessageParam.self,
                from: Data(
                    #"{"role":"user","content":[{"type":"image","source":{"type":"base64","data":7,"media_type":"image/png"}}]}"#
                        .utf8)
            )
        }
    }

    @Test func legacyEffortPresenceSurvivesProjection() throws {
        let request = try WireCodec.decode(
            AnthropicThinkingRequest.self,
            from: Data(#"{"thinking":{"type":"disabled"},"reasoning_effort":null,"vendor":1e400}"#.utf8)
        ).value
        #expect(request.reasoningEffort == .null)
        #expect(request.additionalFields["vendor"] == .numberLiteral(try JSONNumber("1e400")))
    }
}
