import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Swift contract generation")
struct ContractSwiftEmitterTests {
    @Test func delegatingInitializerDoesNotEscapeKeywordArgumentLabels() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(#"{"type":"object","properties":{"class":{"type":"string"}},"required":["class"]}"#.utf8),
            rootID: "Keyword")
        let source = try #require(ContractSwiftEmitter.emit(graph: graph).first).source
        #expect(source.contains("class: try object.required(Key.`class`.rawValue)"))
        #expect(!source.contains("`class`: try object.required"))
        #expect(source.contains("self.`class` = `class`"))
    }

    @Test func decodingDelegatesToThePublicMemberwiseInitializer() throws {
        let data = Data(#"{"type":"object","properties":{"amount":{"type":"number"}},"required":["amount"]}"#.utf8)
        let graph = try ContractSchemaReader.read(data: data, rootID: "Constructor")
        let source = try #require(ContractSwiftEmitter.emit(graph: graph).first).source
        #expect(source.components(separatedBy: "self.amount =").count - 1 == 1)
        #expect(source.contains("self.init("))
        #expect(source.contains("amount: try object.required(Key.amount.rawValue)"))
    }

    @Test func generatesClosedEnumAndStableOutput() throws {
        let data = Data(#"{"type":"string","enum":["end_turn","tool_use"]}"#.utf8)
        let graph = try ContractSchemaReader.read(data: data, rootID: "AnthropicStopReason")
        let output = try ContractSwiftEmitter.emit(graph: graph)
        #expect(output.map(\.relativePath) == ["Anthropic/AnthropicStopReason.swift"])
        let source = try #require(output.first?.source)
        #expect(source.contains("case endTurn = \"end_turn\""))
        #expect(source.contains("case toolUse = \"tool_use\""))
        #expect(source.contains("WireCodable"))
        #expect(try ContractSwiftEmitter.emit(graph: graph) == output)
    }

    @Test func keepsRequiredAndNullableIndependent() throws {
        let data = Data(
            #"""
            {"type":"object","properties":{
              "required":{"type":"string"},"nullable":{"type":["string","null"]},
              "optional":{"type":"string"},"presence":{"type":["string","null"]}
            },"required":["required","nullable"]}
            """#
            .utf8)
        let graph = try ContractSchemaReader.read(data: data, rootID: "PresenceFixture")
        let output = try ContractSwiftEmitter.emit(graph: graph)
        let source = try #require(output.first?.source)
        #expect(source.contains("public var required: String"))
        #expect(source.contains("public var nullable: String?"))
        #expect(source.contains("public var optional: String?"))
        #expect(source.contains("public var presence: JSONPresence<String>"))
        #expect(source.contains("object.nullable(Key.nullable.rawValue)"))
        #expect(source.contains("object.optional(Key.optional.rawValue)"))
        #expect(source.contains("object.presence(Key.presence.rawValue)"))
    }

    @Test func rejectsUnknownAssertionsAndReferences() {
        for schema in [#"{"type":"string","pattern":"secret"}"#, ##"{"$ref":"#/definitions/Missing"}"##] {
            #expect(throws: ContractGenerationError.self) {
                try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Broken")
            }
        }
    }

    @Test func rejectsSwiftNameCollisions() throws {
        let data = Data(#"{"type":"string","enum":["tool-use","tool_use"]}"#.utf8)
        #expect(throws: ContractGenerationError.self) {
            let graph = try ContractSchemaReader.read(data: data, rootID: "Collision")
            _ = try ContractSwiftEmitter.emit(graph: graph)
        }
        for field in ["wireJSON", "additionalFields"] {
            let data = Data("{\"type\":\"object\",\"properties\":{\"\(field)\":{\"type\":\"string\"}}}".utf8)
            #expect(throws: ContractGenerationError.self) {
                try ContractSwiftEmitter.emit(graph: ContractSchemaReader.read(data: data, rootID: "Collision"))
            }
        }
    }

    @Test func resolvesReferencedTaggedUnion() throws {
        let data = Data(
            ##"""
            {"anyOf":[{"$ref":"#/definitions/Text"},{"$ref":"#/definitions/Tool"}],"definitions":{
              "Text":{"type":"object","properties":{
                "type":{"const":"text","type":"string"},"text":{"type":"string"}
              },"required":["type","text"]},
              "Tool":{"type":"object","properties":{
                "type":{"const":"tool","type":"string"},"input":{}
              },"required":["type","input"]}
            }}
            """##
            .utf8)
        let graph = try ContractSchemaReader.read(data: data, rootID: "AnthropicContentBlock")
        let output = try ContractSwiftEmitter.emit(graph: graph)
        let union = try #require(output.first { $0.relativePath.hasSuffix("AnthropicContentBlock.swift") }?.source)
        #expect(union.contains("case text("))
        #expect(union.contains("case tool("))
        #expect(union.contains("case unknown(type: String, payload: JSONValue)"))
        #expect(union.contains("switch discriminator"))
    }

    @Test func keepsUnrelatedStatusEnumsSeparateAndRejectsTagCollisions() throws {
        let data = Data(
            #"""
            {"type":"object","properties":{
              "first":{"type":"object","properties":{"status":{"enum":["one"]}}},
              "second":{"type":"object","properties":{"status":{"enum":["two"]}}}
            }}
            """#.utf8)
        let files = try ContractSwiftEmitter.emit(graph: ContractSchemaReader.read(data: data, rootID: "Statuses"))
        #expect(files.contains { $0.relativePath.hasSuffix("StatusesFirstStatus.swift") })
        #expect(files.contains { $0.relativePath.hasSuffix("StatusesSecondStatus.swift") })
        let collision = Data(
            #"""
            {"anyOf":[
              {"type":"object","properties":{"type":{"const":"same"}},"required":["type"]},
              {"type":"object","properties":{"type":{"const":"same"}},"required":["type"]}
            ]}
            """#.utf8)
        #expect(throws: ContractGenerationError.self) {
            try ContractSwiftEmitter.emit(graph: ContractSchemaReader.read(data: collision, rootID: "Collision"))
        }
    }

    @Test func opaqueAdditionalValuesNeedNoThrowingValidation() throws {
        let data = Data(#"{"type":"object","additionalProperties":{}}"#.utf8)
        let files = try ContractSwiftEmitter.emit(graph: ContractSchemaReader.read(data: data, rootID: "OpaqueMap"))
        #expect(!files[0].source.contains("try JSONValue(wireJSON: value)"))
    }

    @Test func rejectsNullableOneOfWhenNullCanMatchMoreThanOneBranch() throws {
        let alternatives = [
            #"[{}, {"type":"null"}]"#,
            #"[{"type":"string"}, {"type":"null"}, {"type":"null"}]"#,
            #"[{"anyOf":[{"type":"string"},{"type":"null"}]}, {"type":"null"}]"#,
        ]
        for branches in alternatives {
            let data = Data(
                "{\"type\":\"object\",\"properties\":{\"value\":{\"oneOf\":\(branches)}},\"required\":[\"value\"]}"
                    .utf8)
            let graph = try ContractSchemaReader.read(data: data, rootID: "AmbiguousNull")
            do {
                _ = try ContractSwiftEmitter.emit(graph: graph)
                Issue.record("Ambiguous nullable oneOf must fail generation")
            } catch let error as ContractGenerationError {
                #expect(error.contract == "AmbiguousNull")
                #expect(error.pointer == "#/properties/value")
            }
        }
    }
}
