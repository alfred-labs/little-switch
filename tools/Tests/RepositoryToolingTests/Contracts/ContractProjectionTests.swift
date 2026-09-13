import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Explicit contract projections")
struct ContractProjectionTests {
    @Test func rootFieldProjectionOmitsUnconsumedConstantMetadata() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(
                #"{"type":"object","properties":{"type":{"const":"record"},"kept":{"type":"string"},"dropped":{"type":"number"}},"required":["type","kept","dropped"]}"#
                    .utf8), rootID: "Original")
        let manifest = Data(
            #"{"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","fields":["kept"]}]}"#.utf8)
        let projected = try project(graph: graph, manifest: manifest)
        let source = try #require(
            ContractSwiftEmitter.emit(graph: projected).first { $0.relativePath.hasSuffix("Projected.swift") }
        ).source
        #expect(!source.contains("public var type:"))
        #expect(!source.contains("public var dropped"))
        guard case .object(let original, _) = projected.sourceNodes["#"]?.kind else {
            Issue.record("Source record missing")
            return
        }
        #expect(original.map(\.key) == ["dropped", "kept", "type"])
    }

    @Test func nestedSelectionsNameTypesAndRetainTaggedBranchDiscriminators() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(
                ##"""
                {"type":"object","properties":{"content":{"anyOf":[{"$ref":"#/definitions/Text"},{"$ref":"#/definitions/Future"}]}},
                 "definitions":{
                   "Text":{"type":"object","properties":{"type":{"const":"text"},"text":{"type":"string"},"ignored":{"type":"number"}},"required":["type","text","ignored"]},
                   "Future":{"type":"object","properties":{"type":{"const":"future"}},"required":["type"]}
                 }}
                """##.utf8), rootID: "Original")
        let manifest = Data(
            ##"""
            {"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","nodes":{
              "#/properties/content":{"branches":[0],"name":"Content"},
              "#/definitions/Text":{"fields":["text"],"name":"TextBlock"}
            }}]}
            """##.utf8)
        let projected = try project(graph: graph, manifest: manifest)
        let output = try ContractSwiftEmitter.emit(graph: projected)
        let text = try #require(output.first { $0.relativePath.hasSuffix("TextBlock.swift") }).source
        #expect(text.contains("public var type: TextBlockType"))
        #expect(!text.contains("public var ignored:"))
        let content = try #require(output.first { $0.relativePath.hasSuffix("Content.swift") }).source
        #expect(content.contains("case text(TextBlock)"))
        #expect(content.contains("case unknown(type: String, payload: JSONValue)"))
    }

    @Test func opaqueSubtreeIsExplicitAndRetainsSourceConstraints() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(
                #"{"type":"object","properties":{"value":{"type":"string","enum":["a","b"]}},"required":["value"]}"#
                    .utf8), rootID: "Original")
        let manifest = Data(
            ##"{"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","opaque":["#/properties/value"]}]}"##
                .utf8)
        let projected = try project(graph: graph, manifest: manifest)
        let source = try #require(ContractSwiftEmitter.emit(graph: projected).first).source
        #expect(source.contains("public var value: JSONValue?"))
        guard case .enumeration(let values) = projected.sourceNodes["#/properties/value"]?.kind else {
            Issue.record("Source enum missing")
            return
        }
        #expect(values == ["a", "b"])
    }

    @Test func selectsExplicitUnionBranchesInSourceOrder() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(
                #"""
                {"anyOf":[
                  {"type":"object","properties":{"type":{"const":"first"}},"required":["type"]},
                  {"type":"object","properties":{"type":{"const":"second"}},"required":["type"]}
                ]}
                """#
                .utf8), rootID: "Original")
        let manifest = Data(
            #"{"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","branches":[1]}]}"#.utf8)
        let projected = try project(graph: graph, manifest: manifest)
        let source = try #require(
            ContractSwiftEmitter.emit(graph: projected).first { $0.relativePath.hasSuffix("Projected.swift") }
        ).source
        #expect(source.contains("case second("))
        #expect(!source.contains("case first("))
        #expect(source.contains("case unknown(type: String, payload: JSONValue)"))
    }

    @Test func rejectsInvalidProjectionInstructions() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(#"{"type":"string","enum":["a"]}"#.utf8), rootID: "Original")
        for rule in [
            #"{"root":"Original","swiftName":"Projected","fields":["missing"]}"#,
            #"{"root":"Original","swiftName":"bad name"}"#,
            #"{"root":"Original","swiftName":"Projected","importModule":"Injected"}"#,
            #"{"root":"Original","swiftName":"Projected","unknown":true}"#,
            ##"{"root":"Original","swiftName":"Projected","pointer":"#/missing"}"##,
            ##"{"root":"Original","swiftName":"Projected","nodes":{"#":{"unknown":true}}}"##,
            ##"{"root":"Original","swiftName":"Projected","nodes":{"#/missing":{"name":"Missing"}}}"##,
        ] {
            let data = Data("{\"formatVersion\":1,\"contracts\":[\(rule)]}".utf8)
            #expect(throws: ContractGenerationError.self) { try project(graph: graph, manifest: data) }
        }
    }

    @Test func publicKeysMustBeExplicitlySelected() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(#"{"type":"object","properties":{"model":{"type":"string"}}}"#.utf8), rootID: "Routing")
        let manifest = Data(
            #"{"formatVersion":1,"contracts":[{"root":"Routing","swiftName":"Routing","publicKeys":true}]}"#.utf8)
        let projected = try project(graph: graph, manifest: manifest)
        #expect(
            try ContractSwiftEmitter.emit(graph: projected)[0].source.contains(
                "public enum Key: String, CaseIterable, Sendable"))
        #expect(
            try ContractSwiftEmitter.emit(graph: graph)[0].source.contains(
                "private enum Key: String, CaseIterable, Sendable"))
    }

    @Test func publicKeysOnUnionExposeOnlyReachableRecordKeys() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(
                #"""
                {"anyOf":[
                  {"type":"object","properties":{"type":{"const":"first"},"value":{"type":"string"}},"required":["type","value"]},
                  {"type":"object","properties":{"type":{"const":"second"}},"required":["type"]}
                ]}
                """#.utf8), rootID: "Original")
        let manifest = Data(
            #"{"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","publicKeys":true}]}"#.utf8)
        let output = try ContractSwiftEmitter.emit(graph: project(graph: graph, manifest: manifest))
        let union = try #require(output.first { $0.relativePath.hasSuffix("Projected.swift") }).source
        #expect(!union.contains("enum Key"))
        for name in ["ProjectedFirst", "ProjectedSecond"] {
            let record = try #require(output.first { $0.relativePath.hasSuffix("\(name).swift") }).source
            #expect(record.contains("public enum Key: String, CaseIterable, Sendable"))
        }
    }

    @Test func publicKeysRequireARecordInTheSelectedGraph() throws {
        let manifest = Data(
            #"{"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","publicKeys":true}]}"#.utf8)
        for schema in [
            #"{"type":"string"}"#,
            #"{"anyOf":[{"type":"string"},{"type":"boolean"}]}"#,
            #"{"type":"object"}"#,
            #"{"type":"string","definitions":{"Unused":{"type":"object","properties":{"value":{"type":"string"}}}}}"#,
            ##"{"anyOf":[{"$ref":"#"},{"type":"boolean"}]}"##,
        ] {
            let graph = try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Original")
            #expect(throws: ContractGenerationError.self) { try project(graph: graph, manifest: manifest) }
        }
        let graph = try ContractSchemaReader.read(
            data: Data(#"{"type":"object","properties":{"value":{"type":"string"}}}"#.utf8), rootID: "Original")
        let emptySelection = Data(
            #"{"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","publicKeys":true,"fields":[]}]}"#
                .utf8)
        #expect(throws: ContractGenerationError.self) { try project(graph: graph, manifest: emptySelection) }
        let opaqueSelection = Data(
            ##"{"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","publicKeys":true,"opaque":["#"]}]}"##
                .utf8)
        #expect(throws: ContractGenerationError.self) { try project(graph: graph, manifest: opaqueSelection) }
    }

    @Test func publicKeysFollowSelectedArrayAndAdditionalValueRecords() throws {
        let manifest = Data(
            #"{"formatVersion":1,"contracts":[{"root":"Original","swiftName":"Projected","publicKeys":true}]}"#.utf8)
        for schema in [
            #"{"anyOf":[{"type":"string"},{"type":"array","items":{"type":"object","properties":{"value":{"type":"string"}}}}]}"#,
            #"{"type":"object","additionalProperties":{"type":"object","properties":{"value":{"type":"string"}}}}"#,
        ] {
            let graph = try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Original")
            let output = try ContractSwiftEmitter.emit(graph: project(graph: graph, manifest: manifest))
            #expect(output.contains { $0.source.contains("public enum Key: String, CaseIterable, Sendable") })
        }
    }
    private func project(graph: ContractGraph, manifest: Data) throws -> ContractGraph {
        let rule = try #require(ContractProjectionManifest.read(manifest).contracts.first)
        return try ContractProjection.apply(graph: graph, rule: rule)
    }

    @Test func invalidNestedSelectionAndManifestFailBeforeEmission() throws {
        let graph = try ContractSchemaReader.read(
            data: Data(#"{"type":"object","properties":{"value":{"type":"string"}}}"#.utf8),
            rootID: "Original")
        for selection in [
            ##""nodes":{"#":{"name":"bad name"}}"##,
            #""fields":["unknown"]"#,
            #""fields":["value","value"]"#,
            #""branches":[0]"#,
        ] {
            let manifest = Data(
                "{\"formatVersion\":1,\"contracts\":[{\"root\":\"Original\",\"swiftName\":\"Projected\",\(selection)}]}"
                    .utf8)
            #expect(throws: ContractGenerationError.self) { try project(graph: graph, manifest: manifest) }
        }
        for manifest in ["{", #"{"formatVersion":2,"contracts":[]}"#] {
            #expect(throws: ContractGenerationError.self) { try ContractProjectionManifest.read(Data(manifest.utf8)) }
        }
    }

}
