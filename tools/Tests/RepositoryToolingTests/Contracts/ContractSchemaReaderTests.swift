import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Contract schema reader")
struct ContractSchemaReaderTests {
    @Test func readsEveryPinnedSDKSchemaWithoutExpandingReferences() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("schemas/upstream")
        let schemas = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".schema.json") }
        let roots = try JSONDecoder().decode(
            ContractRootsManifest.self, from: Data(contentsOf: root.appendingPathComponent("schemas/roots.json")))
        #expect(
            Set(schemas.map(\.lastPathComponent)) == Set(roots.roots.map(\.schema)).union(["PresenceProbe.schema.json"])
        )
        for schema in schemas {
            let graph = try ContractSchemaReader.read(data: Data(contentsOf: schema), rootID: schema.lastPathComponent)
            #expect(!graph.nodes.isEmpty)
        }
    }

    @Test func honorsEnumConstraintWhenTypeIncludesNull() throws {
        let data = Data(
            #"""
            {"type":"object","properties":{
              "allowed":{"type":["string","null"],"enum":["a",null]},
              "denied":{"type":["string","null"],"enum":["a"]}
            },"required":["allowed","denied"]}
            """#
            .utf8)
        let files = try ContractSwiftEmitter.emit(graph: ContractSchemaReader.read(data: data, rootID: "NullableEnum"))
        let record = try #require(files.first { $0.relativePath.hasSuffix("NullableEnum.swift") })
        #expect(record.source.contains("public var allowed: NullableEnumAllowed?"))
        #expect(record.source.contains("public var denied: NullableEnumDenied\n"))
    }

    @Test func representsUnionsOfScalarTypes() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(#"{"type":["string","number","boolean"]}"#.utf8), rootID: "ScalarUnion")
        let files = try ContractSwiftEmitter.emit(graph: graph)
        #expect(files[0].source.contains("case variant1(String)"))
        #expect(files[0].source.contains("case variant2(JSONNumber)"))
        #expect(files[0].source.contains("case variant3(Bool)"))
    }

    @Test func openStringUnionKeepsStringAndIndependentNullability() throws {
        let data = Data(
            #"""
            {"type":"object","properties":{
              "model":{"anyOf":[{"type":"string"},{"type":"string","enum":["known"]}]},
              "nullable":{"anyOf":[{"type":"string"},{"type":"string","const":"known"},{"type":"null"}]}
            },"required":["model","nullable"]}
            """#.utf8)
        let files = try ContractSwiftEmitter.emit(graph: ContractSchemaReader.read(data: data, rootID: "OpenModel"))
        #expect(files.count == 1)
        #expect(files[0].source.contains("public var model: String\n"))
        #expect(files[0].source.contains("public var nullable: String?\n"))
    }

    @Test func reportsUnsupportedAssertionWithSourcePointer() {
        #expect(
            throws: ContractGenerationError(
                contract: "Broken", pointer: "#/properties/code/pattern", reason: "Unsupported assertion pattern")
        ) {
            try ContractSchemaReader.read(
                data: Data(#"{"type":"object","properties":{"code":{"type":"string","pattern":"a"}}}"#.utf8),
                rootID: "Broken")
        }
    }

    @Test func rejectsUnsupportedCombinationsAndInvalidSchemas() {
        for schema in [
            #"{"type":"integer"}"#,
            #"{"type":"object","required":["missing"]}"#,
            #"{"type":"number","const":1}"#,
            #"{"type":"string","enum":["a","a"]}"#,
            ##"{"$ref":"other.json#/A"}"##,
            #"{"anyOf":[{"type":"string"}],"type":"object"}"#,
        ] {
            #expect(throws: ContractGenerationError.self) {
                try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Broken")
            }
        }
    }

    @Test func rejectsImpossibleRecordCycleButAllowsArrayIndirection() throws {
        let recursive = Data(##"{"type":"object","properties":{"child":{"$ref":"#"}}}"##.utf8)
        #expect(throws: ContractGenerationError.self) {
            try ContractSwiftEmitter.emit(graph: ContractSchemaReader.read(data: recursive, rootID: "Recursive"))
        }
        let array = Data(##"{"type":"object","properties":{"children":{"type":"array","items":{"$ref":"#"}}}}"##.utf8)
        let files = try ContractSwiftEmitter.emit(graph: ContractSchemaReader.read(data: array, rootID: "Recursive"))
        #expect(files[0].source.contains("public var children: [Recursive]?"))
    }

    @Test func malformedSchemasReportTheExactRejectedConstraint() {
        let cases: [String: (pointer: String, reason: String)] = [
            "{": ("#", "Invalid schema JSON"),
            #"{"$schema":"https://json-schema.org/draft/2020-12/schema"}"#:
                ("#/$schema", "Unsupported schema dialect"),
            #"{"definitions":[]}"#: ("#/definitions", "Expected definitions object"),
            #"{"oneOf":[]}"#: ("#", "Expected nonempty union branches"),
            #"{"type":["string","string"]}"#: ("#/type", "Expected distinct JSON type names"),
            #"{"type":["string",false]}"#: ("#/type", "Expected distinct JSON type names"),
            #"{"enum":["a"],"const":"a"}"#: ("#", "Combined enum and const is unsupported"),
            #"{"type":"number","enum":["a"]}"#: ("#", "Enum type mismatch"),
            #"{"type":"object","properties":[]}"#: ("#", "Invalid properties"),
            #"{"type":"string","items":{}}"#: ("#/items", "Unsupported assertion combination"),
        ]
        for (schema, expected) in cases {
            #expect(
                throws: ContractGenerationError(
                    contract: "Malformed", pointer: expected.pointer, reason: expected.reason)
            ) {
                try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Malformed")
            }
        }
    }
}
