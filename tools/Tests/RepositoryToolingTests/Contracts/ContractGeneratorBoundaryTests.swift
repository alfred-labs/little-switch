import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Contract generator boundaries")
struct ContractGeneratorBoundaryTests {
    @Test func malformedManifestAndEnumShapesHaveDomainDiagnostics() throws {
        for manifest in [#"[]"#, #"{"formatVersion":1,"contracts":{}}"#, #"{"contracts":[]}"#] {
            #expect(throws: ContractGenerationError(contract: "projections", reason: "Invalid projection manifest")) {
                try ContractProjectionManifest.read(Data(manifest.utf8))
            }
        }
        #expect(
            throws: ContractGenerationError(
                contract: "BrokenEnum", reason: "Only distinct string enums and boolean constants are supported")
        ) {
            try ContractSchemaReader.read(data: Data(#"{"enum":{}}"#.utf8), rootID: "BrokenEnum")
        }
    }

    @Test func typeNamesCannotShadowRuntimeTypesOrOtherDeclarations() throws {
        for name in ["String", "Bool", "JSONValue", "JSONNumber", "WireObject", "Key"] {
            let graph = try ContractSchemaReader.read(data: Data(#"{"type":"object"}"#.utf8), rootID: name)
            #expect(throws: ContractGenerationError(contract: name, reason: "Swift type name collision: \(name)")) {
                try ContractSwiftEmitter.emit(graph: graph)
            }
        }
        let schema = #"{"type":"object","properties":{"first":{"type":"object"},"second":{"type":"object"}}}"#
        var graph = try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Collision")
        graph.typeNames = ["#/properties/first": "Record", "#/properties/second": "Record"]
        #expect(
            throws: ContractGenerationError(
                contract: "Collision", pointer: "#/properties/second", reason: "Swift type name collision: Record")
        ) {
            try ContractSwiftEmitter.emit(graph: graph)
        }
    }

    @Test func nestedSelectedBranchesProtectTheirOriginalTags() throws {
        let schema = #"""
            {"type":"object","properties":{"event":{"anyOf":[
              {"type":"object","properties":{"type":{"const":"known"}},"required":["type"]},
              {"type":"string"}
            ]}}}
            """#
        let graph = try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Nested")
        let data =
            ##"{"formatVersion":1,"contracts":[{"root":"Nested","swiftName":"Nested","nodes":{"#/properties/event":{"branches":[0]}}}]}"##
        let rule = try #require(ContractProjectionManifest.read(Data(data.utf8)).contracts.first)
        #expect(
            try ContractTaggedGuard.protectedPointers(graph: graph, projection: rule)
                == ["#/properties/event/anyOf/0", "#/properties/event/anyOf/0/properties/type"])
    }

    @Test func cyclicBranchAndTagAliasesFailBeforeDispatch() throws {
        for schema in [
            ##"{"oneOf":[{"$ref":"#/definitions/A"}],"definitions":{"A":{"$ref":"#/definitions/B"},"B":{"$ref":"#/definitions/A"}}}"##,
            ##"""
            {"oneOf":[{"type":"object","properties":{"type":{"$ref":"#/definitions/A"}},"required":["type"]}],
             "definitions":{"A":{"$ref":"#/definitions/B"},"B":{"$ref":"#/definitions/A"}}}
            """##,
        ] {
            let graph = try ContractSchemaReader.read(data: Data(schema.utf8), rootID: "Cycle")
            #expect(
                throws: ContractGenerationError(
                    contract: "Cycle", pointer: "#/definitions/A", reason: "Cyclic reference aliases")
            ) {
                try ContractTaggedGuard.protectedPointers(graph: graph)
            }
        }
    }

    @Test func multipleDiscriminatorCandidatesHaveStableTypePriority() throws {
        for keys in [["aaa", "type", "zzz"], ["zeta", "alpha", "middle"]] {
            let branches = (0..<2)
                .map { index in
                    let fields = keys.map { "\"\($0)\":{\"const\":\"value_\(index)\"}" }.joined(separator: ",")
                    let required = keys.map { "\"\($0)\"" }.joined(separator: ",")
                    return "{\"type\":\"object\",\"properties\":{\(fields)},\"required\":[\(required)]}"
                }
                .joined(separator: ",")
            let graph = try ContractSchemaReader.read(
                data: Data("{\"anyOf\":[\(branches)]}".utf8), rootID: "Tagged")
            let union = try #require(
                ContractSwiftEmitter.emit(graph: graph).first { $0.relativePath.hasSuffix("/Tagged.swift") })
            let selected = keys.contains("type") ? "type" : "alpha"
            #expect(union.source.contains("object.required(\"\(selected)\")"))
            #expect(union.source.contains("case unknown(type: String, payload: JSONValue)"))
        }
    }

    @Test func formattingAcceptsEmptySwiftAndRejectsInvalidSyntax() throws {
        #expect(try ContractSwiftFormat.format("").isEmpty)
        #expect(
            throws: ContractGenerationError(contract: "swift-format", reason: "Unable to format generated Swift")
        ) {
            try ContractSwiftFormat.format("public struct Broken {")
        }
    }
}
