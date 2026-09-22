import Foundation
import LittleSwitchWire
import Testing

@testable import LittleSwitchCore

@Suite("Exact object keys across dictionary compatibility")
struct UnicodeCompatibilityTests {
    @Test func unchangedNativeReasoningNormalizationPreservesBytes() throws {
        let body = Data(
            #"{ "model" : "route", "input" : [ { "type" : "reasoning", "id" : "rs_native_opaque", "summary" : [], "\u00e9" : 1, "e\u0301" : 2 } ] }"#
                .utf8
        )

        #expect(try ResponsesProviderState.normalize(body: body, providerID: nil) == body)
    }

    @Test func unchangedNativeReasoningEgressPreservesBytes() throws {
        let body = Data(
            #"{ "model" : "route", "input" : [ { "type" : "reasoning", "id" : "rs_native_opaque", "summary" : [], "\u00e9" : 1, "e\u0301" : 2 } ] }"#
                .utf8
        )

        #expect(try ResponsesChatCompletionsReasoning.nativeRequestBody(body) == body)
    }

    @Test func rootAndOpaqueNestedKeysSurvive() throws {
        let source = Data(
            #"{"type":"text","\u00e9":1,"e\u0301":2,"input":{"\u00e9":3,"e\u0301":4},"\u0000wire.opaque":5}"#.utf8)
        var fields = try WireJSONCompatibility.fields(source)
        fields["type"] = "changed"
        let encoded = try WireJSONCompatibility.data(fields)
        let root = try #require(try WireCodec.decode(JSONValue.self, from: encoded).value.object)
        #expect(root.count == 5)
        #expect(root["type"] == "changed")
        #expect(root["\u{e9}"] == 1)
        #expect(root["e\u{301}"] == 2)
        #expect(root["input"]?.object?.count == 2)
        #expect(root["input"]?.object?["\u{e9}"] == 3)
        #expect(root["input"]?.object?["e\u{301}"] == 4)
        #expect(root["\0wire.opaque"] == 5)
    }

    @Test func asciiKeyAndEquivalentUnicodeKeyStaySeparate() throws {
        let source = Data(#"{"K":1,"\u212a":2,"type":"text"}"#.utf8)
        var fields = try WireJSONCompatibility.fields(source)
        fields["type"] = "changed"

        let encoded = try WireJSONCompatibility.data(fields)
        let decoded = try WireCodec.decode(JSONValue.self, from: encoded).value
        let expected: JSONValue = ["K": 1, "\u{212a}": 2, "type": "changed"]
        #expect(decoded == expected)
        #expect(decoded.object?.count == 3)
    }

    @Test func allClientMarkerFieldsSurviveAnAsciiMutation() throws {
        let source = Data(
            #"{"\u0000wire.opaque":1,"\u0000wire.opaque\u0000":2,"\u0000wire.opaque\u0000\u0000":{"key":"value"},"\u00e9":3,"e\u0301":4}"#
                .utf8
        )
        var fields = try WireJSONCompatibility.fields(source)
        fields["type"] = "text"

        let encoded = try WireJSONCompatibility.data(fields)
        let decoded = try WireCodec.decode(JSONValue.self, from: encoded).value
        let expected: JSONValue = [
            "\0wire.opaque": 1, "\0wire.opaque\0": 2, "\0wire.opaque\0\0": ["key": "value"],
            "\u{e9}": 3, "e\u{301}": 4, "type": "text",
        ]
        #expect(decoded == expected)
        #expect(decoded.object?.count == 6)
    }

    @Test func nestedSchemaPropertyNamesSurviveAnAsciiMutation() throws {
        let source = Data(
            #"""
            {
              "model": "route",
              "tools": [{
                "name": "inspect",
                "input_schema": {
                  "type": "object",
                  "properties": {
                    "\u00e9": {"type": "string"},
                    "e\u0301": {"type": "number"},
                    "K": {"enum": [1]},
                    "\u212a": {"enum": [2]}
                  },
                  "required": ["\u00e9", "e\u0301", "K", "\u212a"]
                }
              }]
            }
            """#.utf8)
        var fields = try WireJSONCompatibility.fields(source)
        fields["model"] = "changed"

        let encoded = try WireJSONCompatibility.data(fields)
        let decoded = try WireCodec.decode(JSONValue.self, from: encoded).value
        let expected: JSONValue = [
            "model": "changed",
            "tools": [
                [
                    "name": "inspect",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "\u{e9}": ["type": "string"], "e\u{301}": ["type": "number"],
                            "K": ["enum": [1]], "\u{212a}": ["enum": [2]],
                        ],
                        "required": ["\u{e9}", "e\u{301}", "K", "\u{212a}"],
                    ],
                ]
            ],
        ]
        #expect(decoded == expected)
        let tool = try #require(decoded.object?["tools"]?.array?.first?.object)
        #expect(tool["input_schema"]?.object?["properties"]?.object?.count == 4)
    }
}
