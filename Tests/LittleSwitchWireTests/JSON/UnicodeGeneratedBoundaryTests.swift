import Foundation
import LittleSwitchWire
import Testing

@Suite("Unicode property names through generated boundaries")
struct UnicodeGeneratedBoundaryTests {
    @Test func knownUnionRetainsExactAdditionalFieldNames() throws {
        let source = Data(
            #"{"type":"text","text":"ok","\u00e9":1,"e\u0301":2,"K":3,"\u212a":4}"#.utf8)
        let decoded = try WireCodec.decode(AnthropicContentBlockParam.self, from: source).value
        guard case .text(let text) = decoded else {
            Issue.record("Expected the known text union branch")
            return
        }
        #expect(text.additionalFields.count == 4)

        let encoded = try WireCodec.encode(decoded)
        let result = try WireCodec.decode(JSONValue.self, from: encoded).value
        let expected: JSONValue = [
            "type": "text", "text": "ok", "\u{e9}": 1, "e\u{301}": 2, "K": 3, "\u{212a}": 4,
        ]
        #expect(result == expected)
        #expect(result.object?.count == 6)
    }

    @Test func unknownUnionRetainsExactPropertyNames() throws {
        let source = Data(
            #"{"type":"future_block","\u00e9":{"K":1,"\u212a":2},"e\u0301":3}"#.utf8)
        let decoded = try WireCodec.decode(AnthropicContentBlockParam.self, from: source).value
        guard case .unknown(let type, _) = decoded else {
            Issue.record("Expected the unknown union branch")
            return
        }
        #expect(type == "future_block")

        let encoded = try WireCodec.encode(decoded)
        let result = try WireCodec.decode(JSONValue.self, from: encoded).value
        let expected: JSONValue = [
            "type": "future_block", "\u{e9}": ["K": 1, "\u{212a}": 2], "e\u{301}": 3,
        ]
        #expect(result == expected)
        #expect(result.object?.count == 3)
        #expect(result.object?["\u{e9}"]?.object?.count == 2)
    }

    @Test func generatedToolSchemaRetainsExactPropertyNames() throws {
        let source = Data(
            #"""
            {
              "name": "inspect",
              "input_schema": {
                "type": "object",
                "properties": {"\u00e9": {"type": "string"}, "e\u0301": {"type": "number"}},
                "required": ["\u00e9", "e\u0301"]
              }
            }
            """#.utf8)
        let decoded = try WireCodec.decode(AnthropicToolDefinition.self, from: source).value
        let encoded = try WireCodec.encode(decoded)
        let result = try WireCodec.decode(JSONValue.self, from: encoded).value
        let expected: JSONValue = [
            "name": "inspect",
            "input_schema": [
                "type": "object",
                "properties": ["\u{e9}": ["type": "string"], "e\u{301}": ["type": "number"]],
                "required": ["\u{e9}", "e\u{301}"],
            ],
        ]
        #expect(result == expected)
        #expect(result.object?["input_schema"]?.object?["properties"]?.object?.count == 2)
    }
}
