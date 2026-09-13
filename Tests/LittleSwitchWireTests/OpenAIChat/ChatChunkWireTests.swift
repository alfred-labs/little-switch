import Foundation
import LittleSwitchWire
import Testing

@Suite("Official Chat chunk projection and provider compatibility")
struct ChatChunkWireTests {
    @Test func preservesProviderContinuationsAndExactExtras() throws {
        let data = Data(
            #"""
            {"id":"chat","object":"chat.completion.chunk","created":1,"model":"future-model",
             "choices":[{"index":0,"delta":{"role":null,"content":null,"refusal":null,"tool_calls":[
               {"index":0,"type":null,"id":null,"function":{"name":null,"arguments":"Δ","namespace":"workspace"},
                "vendor":18446744073709551615}]},"finish_reason":null}],
             "usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":null,
               "prompt_tokens_details":{"cached_tokens":1,"cache_write_tokens":2},"completion_tokens_details":null},
             "vendor":1e-400}
            """#
            .utf8)
        let document = try WireCodec.decode(OpenAIChatChunk.self, from: data)
        let choice = try #require(document.value.choices.first)
        #expect(choice.delta.role == .null)
        #expect(choice.finishReason == .null)
        let tool = try #require(choice.delta.toolCalls.value?.first)
        #expect(tool.id == .null)
        #expect(tool.type == .null)
        #expect(tool.function?.name == .null)
        #expect(tool.function?.namespace == .value("workspace"))
        #expect(document.originalData == data)
        #expect(try JSONValue.parse(WireCodec.encode(document.value)) == JSONValue.parse(data))
    }

    @Test func omissionAndNullRemainDistinctUntilCoreNormalizesThem() throws {
        let data = Data(
            #"{"id":"chat","object":"chat.completion.chunk","created":1,"model":"route","choices":[{"index":0,"delta":{}}],"usage":{"prompt_tokens":0,"completion_tokens":0}}"#
                .utf8)
        let chunk = try WireCodec.decode(OpenAIChatChunk.self, from: data).value
        let choice = try #require(chunk.choices.first)
        #expect(choice.finishReason == .absent)
        #expect(choice.delta.role == .absent)
        guard case .absent = choice.delta.toolCalls else {
            Issue.record("Omitted tool_calls must remain absent")
            return
        }
        #expect(chunk.usage.value?.totalTokens == .absent)
        #expect(try JSONValue.parse(WireCodec.encode(chunk)) == JSONValue.parse(data))
    }

    @Test(
        "Closed reasons include only official and documented provider cases", arguments: OpenAIChatFinishReason.allCases
    )
    func finishReasons(reason: OpenAIChatFinishReason) throws {
        #expect(try OpenAIChatFinishReason(wireJSON: reason.wireJSON()) == reason)
    }

    @Test func futureReasonsAndMalformedKnownFieldsAreRejected() throws {
        for (field, value) in [
            ("finish_reason", #""future_reason""#),
            ("delta", "null"),
            ("index", "true"),
        ] {
            var choice = try WireObject(JSONValue.parse(Data(#"{"index":0,"delta":{},"finish_reason":null}"#.utf8)))
            try choice.set(JSONValue.parse(Data(value.utf8)), for: field)
            #expect(throws: WireCodingError.self) {
                try OpenAIChatChoice(wireJSON: choice.wireJSON)
            }
        }
    }

    @Test func nonNullContinuationFieldsStillValidateTheirTypes() throws {
        let malformed = [
            #"{"index":0,"type":false}"#,
            #"{"index":0,"id":42}"#,
            #"{"index":0,"function":{"name":false}}"#,
            #"{"index":0,"custom":{"namespace":[]}}"#,
            #"{"index":0,"custom":{"input":null}}"#,
        ]
        for json in malformed {
            #expect(throws: WireCodingError.self) {
                try WireCodec.decode(OpenAIChatToolDelta.self, from: Data(json.utf8))
            }
        }
    }
}
