import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Named contract compatibility")
struct ContractCompatibilityTests {
    @Test func optionalRulePreservesSourceRequirednessAndScopesTheTolerance() throws {
        let graph = try fixture()
        let rule = override(operation: "optional", pointer: "#/properties/signature")
        let incoming = try apply(graph: graph, manifest: rule)
        guard case .object(let fields, _) = incoming.nodes["#"]?.kind,
            case .object(let source, _) = incoming.sourceNodes["#"]?.kind
        else { throw FixtureError.missingRecord }
        #expect(fields.first { $0.key == "signature" }?.required == false)
        #expect(source.first { $0.key == "signature" }?.required == true)
        var other = graph
        other.swiftName = "StrictRecord"
        let unchanged = try apply(graph: other, manifest: rule)
        guard case .object(let strict, _) = unchanged.nodes["#"]?.kind else { throw FixtureError.missingRecord }
        #expect(strict.first { $0.key == "signature" }?.required == true)
    }

    @Test func nullableAndExtendedEnumsKeepExactSourceLiterals() throws {
        let graph = try fixture()
        let nullable = try apply(
            graph: graph, manifest: override(operation: "nullable", pointer: "#/properties/status"))
        #expect(try ContractEmitter(graph: nullable).presence("#/properties/status").nullable)
        let extended = try apply(
            graph: graph,
            manifest: override(
                operation: "enumValues", pointer: "#/properties/status", extra: #", "values":["future"]"#))
        guard case .enumeration(let source) = extended.sourceNodes["#/properties/status"]?.kind,
            case .enumeration(let values) = try extended.resolved("#/properties/status").kind
        else { throw FixtureError.missingRecord }
        #expect(source == ["known"])
        #expect(values == ["known", "future"])
    }

    @Test func openEnumsAndOptionalAddedFieldsRemainExplicit() throws {
        let graph = try fixture()
        let open = try apply(
            graph: graph, manifest: override(operation: "openEnum", pointer: "#/properties/status"))
        let source = try ContractSwiftEmitter.emit(graph: open).first { $0.relativePath.hasSuffix("Incoming.swift") }?
            .source
        #expect(source?.contains("OpenWireValue<IncomingStatus>") == true)
        let added = try apply(
            graph: graph,
            manifest: override(
                operation: "additionalField",
                pointer: "#/properties/namespace",
                extra: #", "schema":{"type":["string","null"]}"#))
        guard case .object(let fields, _) = added.nodes["#"]?.kind else { throw FixtureError.missingRecord }
        #expect(fields.first { $0.key == "namespace" }?.required == false)
        #expect(added.sourceNodes["#/properties/namespace"] == nil)
    }

    @Test func invalidOrUnsourcedOverridesFail() throws {
        let graph = try fixture()
        for rule in [
            override(operation: "unknown", pointer: "#/properties/signature"),
            override(operation: "optional", pointer: "#/missing"),
            override(operation: "enumValues", pointer: "#/properties/signature", extra: #", "values":["x"]"#),
            override(
                operation: "additionalField", pointer: "#/properties/signature", extra: #", "schema":{"type":"string"}"#
            ),
            override(operation: "optional", pointer: "#/properties/signature", source: ""),
        ] {
            #expect(throws: ContractGenerationError.self) {
                try apply(graph: graph, manifest: rule)
            }
        }
    }

    @Test func nullableEnumsKeepNullWhenOpenedOrExtended() throws {
        let nullable = try apply(
            graph: fixture(), manifest: override(operation: "nullable", pointer: "#/properties/status"))
        #expect(throws: ContractGenerationError.self) {
            try apply(graph: nullable, manifest: override(operation: "nullable", pointer: "#/properties/status"))
        }
        for operation in ["enumValues", "openEnum"] {
            let changed = try apply(
                graph: nullable,
                manifest: override(
                    operation: operation,
                    pointer: "#/properties/status",
                    extra: operation == "enumValues" ? #", "values":["future"]"# : ""))
            let shape = try ContractEmitter(graph: changed).presence("#/properties/status")
            #expect(shape.nullable)
            let source = try #require(
                ContractSwiftEmitter.emit(graph: changed).first { $0.relativePath.hasSuffix("Incoming.swift") }
            ).source
            #expect(source.contains(operation == "openEnum" ? "OpenWireValue<IncomingStatus>?" : "IncomingStatus?"))
        }
    }

    @Test func unknownOptionsAndVersionsCannotChangeCompatibilitySilently() throws {
        let valid = try #require(
            String(data: override(operation: "optional", pointer: "#/properties/signature"), encoding: .utf8))
        for invalid in [
            valid.replacingOccurrences(of: #""formatVersion":1"#, with: #""formatVersion":2"#),
            valid.replacingOccurrences(of: #""id":"test-rule""#, with: #""id":"test-rule","unknown":true"#),
        ] {
            #expect(throws: ContractGenerationError.self) { try ContractCompatibilityManifest.read(Data(invalid.utf8)) }
        }
    }

    @Test func compatibilityCannotWeakenARequiredTaggedDiscriminator() throws {
        var graph = try ContractSchemaReader.read(
            data: Data(
                #"""
                {
                  "anyOf": [
                    {
                      "type": "object",
                      "properties": {
                        "type": {
                          "const": "first"
                        }
                      },
                      "required": [
                        "type"
                      ]
                    },
                    {
                      "type": "object",
                      "properties": {
                        "type": {
                          "const": "second"
                        }
                      },
                      "required": [
                        "type"
                      ]
                    }
                  ]
                }
                """#
                .utf8), rootID: "SDKRecord")
        graph.swiftName = "Incoming"
        for operation in ["optional", "nullable", "openEnum"] {
            #expect(throws: ContractGenerationError.self) {
                try apply(
                    graph: graph, manifest: override(operation: operation, pointer: "#/anyOf/0/properties/type"))
            }
        }
    }

    @Test func compatibilityProtectsReferencedDiscriminatorDefinitions() throws {
        var graph = try ContractSchemaReader.read(
            data: Data(
                ##"""
                {
                  "anyOf": [
                    {
                      "$ref": "#/definitions/First"
                    },
                    {
                      "$ref": "#/definitions/Second"
                    }
                  ],
                  "definitions": {
                    "FirstTag": {
                      "const": "first"
                    },
                    "TagAlias": {
                      "$ref": "#/definitions/FirstTag"
                    },
                    "First": {
                      "type": "object",
                      "properties": {
                        "type": {
                          "$ref": "#/definitions/TagAlias"
                        },
                        "text": {
                          "type": "string"
                        }
                      },
                      "required": [
                        "type",
                        "text"
                      ]
                    },
                    "Second": {
                      "type": "object",
                      "properties": {
                        "type": {
                          "const": "second"
                        },
                        "count": {
                          "type": "number"
                        }
                      },
                      "required": [
                        "type",
                        "count"
                      ]
                    }
                  }
                }
                """##
                .utf8),
            rootID: "SDKRecord")
        graph.swiftName = "Incoming"
        for pointer in ["#/definitions/FirstTag", "#/definitions/TagAlias"] {
            for operation in ["nullable", "openEnum", "enumValues"] {
                #expect(throws: ContractGenerationError.self) {
                    try apply(
                        graph: graph,
                        manifest: override(
                            operation: operation,
                            pointer: pointer,
                            extra: operation == "enumValues" ? #", "values":["second"]"# : ""))
                }
            }
        }
        #expect(throws: ContractGenerationError.self) {
            try apply(
                graph: graph,
                manifest: override(operation: "optional", pointer: "#/anyOf/0/properties/type"))
        }
    }

    private func fixture() throws -> ContractGraph {
        var graph = try ContractSchemaReader.read(
            data: Data(
                #"{"type":"object","properties":{"signature":{"type":"string"},"status":{"enum":["known"]}},"required":["signature","status"]}"#
                    .utf8),
            rootID: "SDKRecord")
        graph.swiftName = "Incoming"
        return graph
    }

    private func override(
        operation: String, pointer: String, extra: String = "", source: String = "Pinned SDK record"
    ) -> Data {
        Data(
            """
            {"formatVersion":1,"overrides":[{"id":"test-rule","root":"SDKRecord","projection":"Incoming",
             "pointer":"\(pointer)","operation":"\(operation)","reason":"Existing provider fixture tolerance",
             "source":"\(source)","fixtures":["Tests/fixture.json"]\(extra)}]}
            """.utf8)
    }

    private enum FixtureError: Error { case missingRecord }
    private func apply(graph: ContractGraph, manifest: Data) throws -> ContractGraph {
        let rules = try ContractCompatibilityManifest.read(manifest).overrides
        return try ContractCompatibility.apply(graph: graph, rules: rules)
    }

}
